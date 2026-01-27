# env/<env>/<region>/addons/collibra-dq-standalone/terragrunt.hcl
# Collibra DQ Spark Standalone configuration - EC2-based deployment

include "env" {
  path = "../../../root.hcl"
}

locals {
  parent = read_terragrunt_config("../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  # Extract region from path: env/dev/eu-west-1/addons/collibra-dq-standalone
  path_parts = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 3
  aws_region   = local.path_parts[local.region_index]
  
  modules_root = local.parent.locals.modules_root
  
  # Common tags
  common_tags = merge(local.parent.locals.common_tags, {
    Region    = local.aws_region
    Component = "collibra-dq-standalone"
  })
  
  # State bucket and lock table names
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
  
  # Instance configuration
  instance_config = {
    instance_type = "m5.xlarge"  # Minimum recommended for Collibra DQ
    volume_size   = 100          # GB - enough for DQ installation and data
  }
  
  # Collibra DQ configuration from environment variables
  owl_base                  = get_env("COLLIBRA_DQ_OWL_BASE", "/opt/collibra-dq")
  owl_metastore_user        = get_env("COLLIBRA_DQ_METASTORE_USER", "collibra_dq_admin")
  owl_metastore_pass        = get_env("COLLIBRA_DQ_METASTORE_PASS", "")
  spark_package             = get_env("COLLIBRA_DQ_SPARK_PACKAGE", "spark-3.5.6-bin-hadoop3.tgz")
  dq_admin_user_password    = get_env("COLLIBRA_DQ_ADMIN_PASSWORD", "")
  dq_package_url            = get_env("COLLIBRA_DQ_PACKAGE_URL", "")
  dq_package_filename       = get_env("COLLIBRA_DQ_PACKAGE_FILENAME", "dq-full-package.tar.gz")
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "addons/collibra-dq-standalone/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = local.lock_table
    encrypt        = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    provider "aws" { region = "${local.aws_region}" }
  HCL
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    terraform {
      backend "s3" {}
    }
  HCL
}

# Dependencies
dependency "vpc" {
  config_path = "../../../network/vpc"
  mock_outputs = {
    vpc_id            = "vpc-123456"
    private_subnets   = ["subnet-123456", "subnet-789012"]
    public_subnets    = ["subnet-345678", "subnet-901234"]
    vpc_cidr_block    = "10.10.0.0/16"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependency "rds" {
  config_path = "../../../database/rds-collibra-dq/rds"
  mock_outputs = {
    db_instance_address = "mock-rds-endpoint.rds.amazonaws.com"
    db_instance_port    = 5432
    db_instance_name    = "dqMetastore"
    db_instance_username = "collibra_dq_admin"
    db_instance_password = "mock-password"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependency "sg_collibra_dq" {
  config_path = "./sg-collibra-dq"
  mock_outputs = {
    security_group_id = "sg-mock-collibra-dq"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependencies {
  paths = [
    "../../../network/vpc",
    "../../../database/rds-collibra-dq/rds",
    "./sg-collibra-dq"
  ]
}

# Note: ALB and target group attachment are deployed separately
# Deploy order: 1) sg-collibra-dq, 2) collibra-dq-standalone, 3) alb/sg-alb, 4) alb, 5) alb/target-group-attachment

terraform {
  source = "${local.modules_root}/application/collibra-dq-standalone"
}

inputs = {
  name = "${local.org}-${local.env}-collibra-dq-standalone"
  region = local.aws_region

  # Instance configuration
  instance_type     = local.instance_config.instance_type
  ami_ssm_parameter = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  
  # Network configuration
  # Using private subnet - access via ALB only (more secure)
  subnet_id                   = dependency.vpc.outputs.private_subnets[0]
  associate_public_ip_address = false  # No public IP needed - access via ALB
  vpc_security_group_ids      = [dependency.sg_collibra_dq.outputs.security_group_id]
  
  # Storage configuration
  root_block_device = [{
    volume_size           = local.instance_config.volume_size
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true
  }]
  
  # IAM configuration
  create_iam_instance_profile = true
  iam_role_use_name_prefix    = false
  iam_role_name               = "${local.org}-${local.env}-collibra-dq-standalone-role"
  
  iam_role_policies = {
    ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    # S3 access for downloading DQ package (if stored in S3)
    s3_read = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    # CloudWatch Logs for observability
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
  ebs_optimized   = true  # Enable for m5.xlarge
  monitoring      = true
  
  # Collibra DQ configuration
  owl_base               = local.owl_base
  owl_metastore_user     = local.owl_metastore_user
  owl_metastore_pass     = local.owl_metastore_pass
  postgresql_host        = dependency.rds.outputs.db_instance_address
  postgresql_port        = dependency.rds.outputs.db_instance_port
  postgresql_database    = dependency.rds.outputs.db_instance_name
  spark_package          = local.spark_package
  dq_admin_user_password = local.dq_admin_user_password
  dq_package_url         = local.dq_package_url
  dq_package_filename    = local.dq_package_filename
  
  tags = merge(local.common_tags, {
    Name = "${local.org}-${local.env}-collibra-dq-standalone"
  })
}
