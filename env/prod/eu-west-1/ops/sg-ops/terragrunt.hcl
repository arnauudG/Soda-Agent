# env/<env>/<region>/ops/sg-ops/terragrunt.hcl
# Security Group Ops configuration - includes env-level root.hcl (1 level, avoids nested includes)

include "env" {
  path = "../../../root.hcl"
}

locals {
  parent = read_terragrunt_config("../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  # Extract region from path: env/prod/eu-west-1/ops/sg-ops
  path_parts = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 3  # region is 3 levels up from sg-ops
  aws_region   = local.path_parts[local.region_index]
  
  # Common tags from parent, with Region added
  common_tags = merge(local.parent.locals.common_tags, {
    Region = local.aws_region
  })
  
  # State bucket and lock table names
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "ops/sg-ops/terraform.tfstate"
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

dependency "vpc" {
  config_path = "../../network/vpc"
  mock_outputs = {
    vpc_id         = "vpc-123456"
    vpc_cidr_block = "10.10.0.0/16"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

terraform {
  source = "${local.parent.locals.modules_root}/security/security-group/ops"
}

inputs = {
  name        = "${local.org}-${local.env}-ops-sg"
  description = "Security group for ops EC2 instance - allows SSM, ECR, EKS access via VPC endpoints"
  vpc_id      = dependency.vpc.outputs.vpc_id

  # No inbound rules - access via SSM Session Manager only
  ingress_rules = []

  # Egress rules - restricted to VPC CIDR for VPC endpoints, specific AWS services
  egress_with_cidr_blocks = [
    # HTTPS to VPC endpoints (SSM, ECR, STS, CloudWatch Logs) - restricted to VPC CIDR
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS to VPC endpoints (SSM, ECR, STS, CloudWatch Logs)"
      cidr_blocks = dependency.vpc.outputs.vpc_cidr_block
    },
    # DNS resolution via VPC DNS resolver
    {
      from_port   = 53
      to_port     = 53
      protocol    = "udp"
      description = "DNS UDP to VPC resolver"
      cidr_blocks = dependency.vpc.outputs.vpc_cidr_block
    },
    {
      from_port   = 53
      to_port     = 53
      protocol    = "tcp"
      description = "DNS TCP to VPC resolver"
      cidr_blocks = dependency.vpc.outputs.vpc_cidr_block
    },
    # NTP for time synchronization (AWS Time Sync service)
    {
      from_port   = 123
      to_port     = 123
      protocol    = "udp"
      description = "NTP to AWS Time Sync service"
      cidr_blocks = "169.254.169.123/32"
    },
    # HTTP for package updates (yum/dnf repositories) - only to AWS endpoints
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "HTTP for package updates to AWS repositories"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  tags = merge(local.common_tags, {
    Component = "ops-sg"
    Name      = "${local.org}-${local.env}-ops-sg"
  })
}
