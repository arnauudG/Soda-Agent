# env/<env>/<region>/database/rds-collibra-dq/rds/terragrunt.hcl
# RDS PostgreSQL configuration for Collibra DQ - includes env-level root.hcl (1 level, avoids nested includes)

include "env" {
  path = "../../../../root.hcl"
}

locals {
  parent = read_terragrunt_config("../../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  # Extract region from path: env/prod/eu-west-1/database/rds-collibra-dq/rds
  path_parts = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 4  # region is 4 levels up from rds
  aws_region   = local.path_parts[local.region_index]
  
  # Common tags from parent, with Region added
  common_tags = merge(local.parent.locals.common_tags, {
    Region = local.aws_region
  })
  
  modules_root = local.parent.locals.modules_root
  
  # State bucket and lock table names
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
  
  # Environment-specific RDS configuration (prod: larger, more reliable)
  rds_config = {
    instance_class      = "db.t3.large"  # Prod: larger instance
    allocated_storage   = 100
    max_allocated_storage = 500  # Prod: higher max for scaling
    multi_az            = true   # Prod: Multi-AZ for high availability
    deletion_protection = true   # Prod: protect from accidental deletion
    backup_retention    = 30    # Prod: longer backup retention
  }
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "database/rds-collibra-dq/rds/terraform.tfstate"
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

generate "versions_override" {
  path      = "versions_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    terraform {
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = ">= 5.0, < 6.0"
        }
        random = {
          source  = "hashicorp/random"
          version = ">= 3.0"
        }
      }
    }
  HCL
}

dependency "vpc" {
  config_path = "../../../network/vpc"
  mock_outputs = {
    vpc_id          = "vpc-123456"
    private_subnets = ["subnet-a", "subnet-b", "subnet-c"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependency "sg_rds" {
  config_path = "../sg-rds"
  mock_outputs = {
    security_group_id = "sg-123456"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependencies {
  paths = [
    "../../../network/vpc",
    "../sg-rds"
  ]
}

terraform {
  source = "${local.modules_root}/database/rds/postgresql"
}

inputs = {
  name = "${local.org}-${local.env}-collibra-dq"
  
  # Get VPC and subnet IDs from dependency outputs (not hardcoded)
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets
  
  # Get security group ID from dependency output (not hardcoded)
  security_group_ids = [dependency.sg_rds.outputs.security_group_id]

  # PostgreSQL configuration
  engine_version = "15.4"
  instance_class = local.rds_config.instance_class
  
  # Storage configuration
  allocated_storage     = local.rds_config.allocated_storage
  max_allocated_storage = local.rds_config.max_allocated_storage
  storage_type         = "gp3"
  storage_encrypted     = true

  # Database configuration
  database_name  = "collibra_dq"
  master_username = "collibra_dq_admin"
  # Password will be auto-generated if COLLIBRA_DQ_RDS_PASSWORD is not set
  master_password = get_env("COLLIBRA_DQ_RDS_PASSWORD", "")
  create_random_password = get_env("COLLIBRA_DQ_RDS_PASSWORD", "") == ""

  # Backup configuration
  backup_retention_period = local.rds_config.backup_retention
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # High availability
  multi_az = local.rds_config.multi_az

  # Protection
  deletion_protection = local.rds_config.deletion_protection
  skip_final_snapshot = false
  final_snapshot_identifier = "${local.org}-${local.env}-collibra-dq-final-snapshot"

  # Monitoring (prod: enable for better observability)
  enabled_cloudwatch_logs_exports = ["postgresql"]
  performance_insights_enabled     = true   # Prod: enable Performance Insights
  performance_insights_retention_period = 7
  monitoring_interval             = 60     # Prod: enable enhanced monitoring

  tags = merge(local.common_tags, {
    Component = "database-rds"
    Name      = "${local.org}-${local.env}-collibra-dq"
  })
}
