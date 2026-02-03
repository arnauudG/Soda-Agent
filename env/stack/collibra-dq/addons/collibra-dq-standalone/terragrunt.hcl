# env/stack/collibra-dq/addons/collibra-dq-standalone/terragrunt.hcl
# Collibra DQ Spark Standalone EC2 instance

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "common" {
  path = find_in_parent_folders("common.hcl")
}

locals {
  org              = include.root.locals.org
  env              = include.root.locals.env
  aws_region       = include.root.locals.aws_region
  common_tags      = include.root.locals.common_tags
  collibra_dq_config = include.root.locals.collibra_dq_config

  # Collibra DQ configuration from environment variables
  owl_base               = get_env("COLLIBRA_DQ_OWL_BASE", "/opt/collibra-dq")
  spark_package          = get_env("COLLIBRA_DQ_SPARK_PACKAGE", "spark-3.5.6-bin-hadoop3.tgz")
  dq_admin_user_password = get_env("COLLIBRA_DQ_ADMIN_PASSWORD", "")
  dq_package_filename    = get_env("COLLIBRA_DQ_PACKAGE_FILENAME", "dq-2025.11-SPARK356-JDK17-package-full.tar")
  license_key            = get_env("COLLIBRA_DQ_LICENSE_KEY", "")
  license_name           = get_env("COLLIBRA_DQ_LICENSE_NAME", "collibra-partners")

  # S3 bucket for package storage
  package_bucket_name = "${get_aws_account_id()}-${local.org}-${local.env}-packages-${local.aws_region}"
  package_s3_key      = "collibra-dq/${local.dq_package_filename}"
}

dependency "vpc" {
  config_path = "../../network/vpc"
  skip_outputs = false
  mock_outputs = {
    vpc_id          = "vpc-123456"
    private_subnets = ["subnet-123456", "subnet-789012"]
    public_subnets  = ["subnet-345678", "subnet-901234"]
    vpc_cidr_block  = "10.10.0.0/16"
  }
  # Allow mocks for destroy because VPC might be destroyed before EC2 instance
  # Terragrunt will read real outputs during apply if skip_outputs = false
  mock_outputs_allowed_terraform_commands = ["init", "plan", "validate", "destroy"]
}

dependency "rds" {
  config_path = "../../database/rds-collibra-dq/rds"
  skip_outputs = false
  mock_outputs = {
    db_instance_address  = "mock-rds-endpoint.rds.amazonaws.com"
    db_instance_port     = 5432
    db_instance_name     = "dqMetastore"
    db_instance_username = "collibra_dq_admin"
    db_instance_password = "mock-password"
  }
  # Allow mocks for destroy because RDS might be destroyed before EC2 instance
  # Terragrunt will read real outputs during apply if skip_outputs = false
  mock_outputs_allowed_terraform_commands = ["init", "plan", "validate", "destroy"]
}

dependency "sg_collibra_dq" {
  config_path = "./sg-collibra-dq"
  skip_outputs = false
  mock_outputs = {
    security_group_id = "sg-mock-collibra-dq"
  }
  # Allow mocks for destroy because security group might be destroyed before EC2 instance
  # Terragrunt will read real outputs during apply if skip_outputs = false
  mock_outputs_allowed_terraform_commands = ["init", "plan", "validate", "destroy"]
}

dependency "package_upload" {
  config_path  = "./package-upload"
  skip_outputs = false
  mock_outputs = {
    s3_url          = "s3://mock-bucket/collibra-dq/mock-package.tar.gz"
    package_uploaded = false
    bucket_name     = "mock-bucket"
  }
  # Allow mocks for destroy because package upload might be destroyed before EC2 instance
  mock_outputs_allowed_terraform_commands = ["init", "plan", "validate", "destroy"]
}

dependencies {
  paths = [
    "../../network/vpc",
    "../../database/rds-collibra-dq/rds",
    "./sg-collibra-dq",
    "./package-upload"  # Ensure package is uploaded to S3 before EC2 instance is created
  ]
}

terraform {
  source = "${include.root.locals.modules_root}/application/collibra-dq-standalone"
}

inputs = {
  name   = "${local.org}-${local.env}-collibra-dq-standalone"
  region = local.aws_region

  # Instance configuration
  instance_type     = local.collibra_dq_config.instance_type
  ami_ssm_parameter = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"

  # Network configuration - private subnet, access via ALB
  subnet_id                   = dependency.vpc.outputs.private_subnets[0]
  associate_public_ip_address = false
  vpc_security_group_ids      = [dependency.sg_collibra_dq.outputs.security_group_id]

  # Storage configuration
  root_block_device = {
    volume_size           = local.collibra_dq_config.volume_size
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true
  }

  # IAM configuration
  create_iam_instance_profile = true
  iam_role_use_name_prefix    = false
  # Suffix the role name with the VPC id suffix to avoid colliding with legacy roles from previous stacks.
  iam_role_name               = "${local.org}-${local.env}-collibra-dq-standalone-${substr(replace(dependency.vpc.outputs.vpc_id, "vpc-", ""), length(replace(dependency.vpc.outputs.vpc_id, "vpc-", "")) - 6, 6)}-role"

  iam_role_policies = {
    ssm             = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    s3_read         = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    cloudwatch_logs = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  }

  # Metadata options
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  placement_group = null
  tenancy         = "default"
  ebs_optimized   = true
  monitoring      = true

  # Collibra DQ configuration
  owl_base               = local.owl_base
  owl_metastore_user     = dependency.rds.outputs.db_instance_username
  owl_metastore_pass     = dependency.rds.outputs.db_instance_password
  postgresql_host        = dependency.rds.outputs.db_instance_address
  postgresql_port        = dependency.rds.outputs.db_instance_port
  postgresql_database    = dependency.rds.outputs.db_instance_name
  spark_package          = local.spark_package
  dq_admin_user_password = local.dq_admin_user_password
  # Package URL: Priority order:
  # 1. Explicit env var (COLLIBRA_DQ_PACKAGE_URL) - for GitHub releases, CDN, or pre-signed URLs
  # 2. Fallback to S3 package-upload dependency output
  # Set COLLIBRA_DQ_PACKAGE_URL to bypass S3 upload entirely (faster deployment)
  dq_package_url         = get_env("COLLIBRA_DQ_PACKAGE_URL", "") != "" ? get_env("COLLIBRA_DQ_PACKAGE_URL", "") : dependency.package_upload.outputs.s3_url
  dq_package_filename    = local.dq_package_filename
  license_key            = local.license_key
  license_name           = local.license_name

  # Install script in S3 (avoids EC2 user data 16KB limit)
  install_script_bucket_name = local.package_bucket_name
  install_script_s3_key      = "collibra-dq/install_collibra_dq.sh"

  tags = merge(local.common_tags, {
    Component = "collibra-dq-standalone"
    Stack     = "collibra-dq"
    Name      = "${local.org}-${local.env}-collibra-dq-standalone"
  })
}
