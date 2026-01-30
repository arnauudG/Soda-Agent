# env/stack/database/rds-collibra-dq/rds/terragrunt.hcl
# RDS PostgreSQL for Collibra DQ

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "common" {
  path = find_in_parent_folders("common.hcl")
}

locals {
  org         = include.root.locals.org
  env         = include.root.locals.env
  aws_region  = include.root.locals.aws_region
  common_tags = include.root.locals.common_tags
  rds_config  = include.root.locals.rds_config
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
  source = "${include.root.locals.modules_root}/database/rds/postgresql"
}

inputs = {
  name = "${local.org}-${local.env}-dqMetastore-collibra-dq"

  vpc_id             = dependency.vpc.outputs.vpc_id
  subnet_ids         = dependency.vpc.outputs.private_subnets
  security_group_ids = [dependency.sg_rds.outputs.security_group_id]

  # PostgreSQL configuration
  engine_version = "15.13"
  instance_class = local.rds_config.instance_class

  # Storage configuration
  allocated_storage     = local.rds_config.allocated_storage
  max_allocated_storage = local.rds_config.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database configuration
  database_name          = "dqMetastore"
  master_username        = "collibra_dq_admin"
  master_password        = get_env("COLLIBRA_DQ_RDS_PASSWORD", "")
  create_random_password = get_env("COLLIBRA_DQ_RDS_PASSWORD", "") == ""

  # Backup configuration
  backup_retention_period = local.rds_config.backup_retention
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # High availability
  multi_az = local.rds_config.multi_az

  # Protection
  deletion_protection       = local.rds_config.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.org}-${local.env}-collibra-dq-final-snapshot"

  # Monitoring
  enabled_cloudwatch_logs_exports  = ["postgresql"]
  performance_insights_enabled     = local.env == "prod"
  monitoring_interval              = local.env == "prod" ? 60 : 0

  tags = merge(local.common_tags, {
    Component = "database-rds"
    Name      = "${local.org}-${local.env}-collibra-dq"
  })
}
