# env/<env>/<region>/database/rds-collibra-dq/sg-rds/terragrunt.hcl
# RDS Security Group configuration - includes env-level root.hcl (1 level, avoids nested includes)

include "env" {
  path = "../../../../root.hcl"
}

locals {
  parent = read_terragrunt_config("../../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  # Extract region from path: env/dev/eu-west-1/database/rds-collibra-dq/sg-rds
  path_parts = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 4  # region is 4 levels up from sg-rds
  aws_region   = local.path_parts[local.region_index]
  
  # Common tags from parent, with Region added
  common_tags = merge(local.parent.locals.common_tags, {
    Region = local.aws_region
  })
  
  modules_root = local.parent.locals.modules_root
  
  # State bucket and lock table names
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "database/rds-collibra-dq/sg-rds/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = local.lock_table
    encrypt        = true
  }
}

dependency "vpc" {
  config_path = "../../../network/vpc"
  mock_outputs = {
    vpc_id         = "vpc-123456"
    vpc_cidr_block = "10.10.0.0/16"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependency "eks" {
  config_path = "../../../eks"
  mock_outputs = {
    node_security_group_id = "sg-mock-123456"
    cluster_name           = "mock-cluster"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependency "sg_ops" {
  config_path = "../../../ops/sg-ops"
  mock_outputs = {
    security_group_id = "sg-mock-ops"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependency "sg_collibra_dq" {
  config_path = "../../../addons/collibra-dq-standalone/sg-collibra-dq"
  mock_outputs = {
    security_group_id = "sg-mock-collibra-dq"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependencies {
  paths = [
    "../../../network/vpc",
    "../../../eks",
    "../../../ops/sg-ops",
    "../../../addons/collibra-dq-standalone/sg-collibra-dq"
  ]
}

terraform {
  source = "${local.modules_root}/security/security-group/rds"
}

inputs = {
  name        = "${local.org}-${local.env}-rds-collibra-dq-sg"
  description = "Security group for Collibra DQ RDS PostgreSQL - allows access from EKS nodes, Collibra DQ standalone instance, and ops instance"
  # Get VPC ID from dependency output (not hardcoded)
  vpc_id = dependency.vpc.outputs.vpc_id

  # Allow access from EKS node security group, Collibra DQ standalone instance, and ops security group
  # Get security group IDs from dependency outputs (not hardcoded)
  # This allows access from:
  # - EKS nodes (for Collibra DQ pods)
  # - Collibra DQ standalone EC2 instance (for standalone deployment)
  # - Ops instance (for database management and troubleshooting)
  allowed_security_group_ids = [
    dependency.eks.outputs.node_security_group_id,
    dependency.sg_collibra_dq.outputs.security_group_id,
    dependency.sg_ops.outputs.security_group_id
  ]
  
  # Alternative: Use VPC CIDR block if you need broader access from within the VPC
  # This is less secure but simpler - uncomment if preferred
  # allowed_cidr_blocks = [dependency.vpc.outputs.vpc_cidr_block]

  port = 5432

  tags = merge(local.common_tags, {
    Component = "database-sg"
    Name      = "${local.org}-${local.env}-rds-collibra-dq-sg"
  })
}
