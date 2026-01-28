# env/<env>/<region>/addons/collibra-dq-standalone/terragrunt.hcl
# Collibra DQ Spark Standalone configuration - EC2-based deployment

# Note: We don't use include here to avoid nested includes
# Instead, we read the env-level root.hcl directly
locals {
  parent = read_terragrunt_config("../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  # Extract region from path: env/prod/eu-west-1/addons/collibra-dq-standalone
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
  # For prod: using m5.xlarge (4 vCPU, 16GB RAM) - recommended for production workloads
  instance_config = {
    instance_type = "m5.xlarge"  # Prod: 4 vCPU, 16GB RAM - suitable for production workloads
    volume_size   = 200          # GB - larger volume for production data
  }
  
  # Collibra DQ configuration from environment variables
  owl_base                  = get_env("COLLIBRA_DQ_OWL_BASE", "/opt/collibra-dq")
  # Note: owl_metastore_user and owl_metastore_pass are retrieved from RDS dependency outputs
  # No need to set COLLIBRA_DQ_METASTORE_USER or COLLIBRA_DQ_METASTORE_PASS - uses RDS credentials automatically
  spark_package             = get_env("COLLIBRA_DQ_SPARK_PACKAGE", "spark-3.5.6-bin-hadoop3.tgz")
  dq_admin_user_password    = get_env("COLLIBRA_DQ_ADMIN_PASSWORD", "")
  dq_package_filename       = get_env("COLLIBRA_DQ_PACKAGE_FILENAME", "dq-2025.11-SPARK356-JDK17-package-full.tar.gz")
  license_key               = get_env("COLLIBRA_DQ_LICENSE_KEY", "")
  # Default license name for new installs (can be overridden via environment variable)
  license_name              = get_env("COLLIBRA_DQ_LICENSE_NAME", "collibra-partners")
  
  # Package file path (relative to project root)
  # Automatically detects package file in packages/collibra-dq/ directory
  # From: env/prod/eu-west-1/addons/collibra-dq-standalone
  # To: packages/collibra-dq/ (at project root)
  # Path: collibra-dq-standalone -> addons -> eu-west-1 -> prod -> env -> project root
  # So: ../../../../../packages/collibra-dq/
  package_local_path = "${get_terragrunt_dir()}/../../../../../packages/collibra-dq/${local.dq_package_filename}"
  
  # S3 bucket for package storage (will be created if it doesn't exist)
  package_bucket_name = "${get_aws_account_id()}-${local.org}-${local.env}-packages-${local.aws_region}"
  package_s3_key      = "collibra-dq/${local.dq_package_filename}"
  
  # Determine package URL: 
  # 1. Use environment variable if set (highest priority)
  # 2. Use S3 URL (package will be uploaded by package-upload step)
  # 3. Fall back to default CloudFront URL (may require authentication)
  # Note: If package file exists locally, package-upload will upload it to S3 automatically
  # We use the S3 URL directly since package-upload dependency may not have outputs yet
  dq_package_url = get_env("COLLIBRA_DQ_PACKAGE_URL", "") != "" ? get_env("COLLIBRA_DQ_PACKAGE_URL", "") : (
    "s3://${local.package_bucket_name}/${local.package_s3_key}"
  )
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
  config_path = "../../network/vpc"
  mock_outputs = {
    vpc_id            = "vpc-123456"
    private_subnets   = ["subnet-123456", "subnet-789012"]
    public_subnets    = ["subnet-345678", "subnet-901234"]
    vpc_cidr_block    = "10.10.0.0/16"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependency "rds" {
  config_path = "../../database/rds-collibra-dq/rds"
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
  # Note: For apply, sg-collibra-dq must be applied first
}

dependencies {
  paths = [
    "../../network/vpc",
    "../../database/rds-collibra-dq/rds",
    "./sg-collibra-dq"
    # Note: package-upload is handled separately by deployment script
    # It's listed as a dependency but skip_outputs=true to avoid errors if not applied yet
  ]
}

# Note: ALB and target group attachment are deployed separately
# Deploy order: 
#   1) sg-collibra-dq
#   2) package-upload (uploads package from project folder to S3)
#   3) collibra-dq-standalone (EC2 instance downloads from S3)
#   4) alb/sg-alb
#   5) alb
#   6) alb/target-group-attachment

dependency "package_upload" {
  config_path = "./package-upload"
  skip_outputs = true  # Skip outputs since package-upload may not be applied yet
  mock_outputs = {
    s3_url = "s3://mock-bucket/collibra-dq/mock-package.tar.gz"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "validate"]
}

terraform {
  source = "${local.modules_root}/application/collibra-dq-standalone"
}

inputs = {
  name = "${local.org}-${local.env}-collibra-dq-standalone"
  region = local.aws_region

  # Instance configuration
  # Note: Collibra DQ documentation recommends CentOS or RHEL 7
  # Amazon Linux 2023 (AL2023) is compatible and should work, but if you encounter issues,
  # consider using Amazon Linux 2 (closer to RHEL 7) or a CentOS/RHEL AMI
  instance_type     = local.instance_config.instance_type
  ami_ssm_parameter = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  # Alternative for RHEL 7 compatibility: use Amazon Linux 2
  # ami_ssm_parameter = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
  
  # Network configuration
  # Using private subnet - access via ALB only (more secure)
  subnet_id                   = dependency.vpc.outputs.private_subnets[0]
  associate_public_ip_address = false  # No public IP needed - access via ALB
  vpc_security_group_ids      = [dependency.sg_collibra_dq.outputs.security_group_id]
  
  # Storage configuration
  root_block_device = {
    volume_size           = local.instance_config.volume_size
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true
  }
  
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
  ebs_optimized   = true  # Enable for m5.xlarge (supported)
  monitoring      = true
  
  # Collibra DQ configuration
  owl_base               = local.owl_base
  # Use RDS credentials directly from dependency outputs
  # This automatically uses the same username and password as the RDS instance
  # No need to set COLLIBRA_DQ_METASTORE_USER or COLLIBRA_DQ_METASTORE_PASS environment variables
  owl_metastore_user     = dependency.rds.outputs.db_instance_username
  owl_metastore_pass     = dependency.rds.outputs.db_instance_password
  postgresql_host        = dependency.rds.outputs.db_instance_address
  postgresql_port        = dependency.rds.outputs.db_instance_port
  postgresql_database    = dependency.rds.outputs.db_instance_name
  spark_package          = local.spark_package
  dq_admin_user_password = local.dq_admin_user_password
  dq_package_url         = local.dq_package_url
  dq_package_filename    = local.dq_package_filename
  license_key            = local.license_key
  license_name           = local.license_name
  
  tags = merge(local.common_tags, {
    Name = "${local.org}-${local.env}-collibra-dq-standalone"
  })
}
