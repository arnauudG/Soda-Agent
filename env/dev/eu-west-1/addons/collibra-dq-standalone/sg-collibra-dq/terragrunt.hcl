# env/<env>/<region>/addons/collibra-dq-standalone/sg-collibra-dq/terragrunt.hcl
# Security Group for Collibra DQ Standalone instance

include "env" {
  path = "../../../../root.hcl"
}

locals {
  parent = read_terragrunt_config("../../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  path_parts = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 4
  aws_region   = local.path_parts[local.region_index]
  
  common_tags = merge(local.parent.locals.common_tags, {
    Region = local.aws_region
  })
  
  modules_root = local.parent.locals.modules_root
  
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
  
  # Allow access from specific IPs, VPC CIDR, or internet
  # Options:
  # - Not set or empty: Allow from internet (0.0.0.0/0) - WARNING: Less secure
  # - Set to VPC CIDR: Allow only from within VPC (more secure)
  # - Set to specific IP: Allow only from that IP (most secure, e.g., "1.2.3.4/32")
  # For dev: defaulting to internet access. Set COLLIBRA_DQ_ALLOWED_CIDR to restrict.
  allowed_cidr_blocks = try(get_env("COLLIBRA_DQ_ALLOWED_CIDR", "0.0.0.0/0"), "0.0.0.0/0")
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "addons/collibra-dq-standalone/sg-collibra-dq/terraform.tfstate"
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
  config_path = "../../../../network/vpc"
  mock_outputs = {
    vpc_id         = "vpc-123456"
    vpc_cidr_block = "10.10.0.0/16"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependency "sg_alb" {
  config_path = "../alb/sg-alb"
  mock_outputs = {
    security_group_id = "sg-mock-alb"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependencies {
  paths = [
    "../../../../network/vpc",
    "../alb/sg-alb"
  ]
}

terraform {
  source = "${local.modules_root}/security/security-group/ops"
}

inputs = {
  name        = "${local.org}-${local.env}-collibra-dq-standalone-sg"
  description = "Security group for Collibra DQ Standalone instance - allows access to DQ Web (port 9000) and health check (port 9101)"
  vpc_id      = dependency.vpc.outputs.vpc_id

  # Ingress rules - allow access from ALB only (more secure)
  # DQ Web (port 9000) - only accessible from ALB security group
  ingress_with_source_security_group_id = [
    {
      from_port                = 9000
      to_port                  = 9000
      protocol                 = "tcp"
      description              = "Allow access to Collibra DQ Web interface from ALB"
      source_security_group_id = dependency.sg_alb.outputs.security_group_id
    }
  ]
  
  # Ingress rules - allow access to health check and Spark UIs from VPC (for monitoring)
  ingress_with_cidr_blocks = [
    # DQ Agent Health Check (port 9101) - from VPC for monitoring
    {
      from_port   = 9101
      to_port     = 9101
      protocol    = "tcp"
      description = "Allow access to Collibra DQ Agent health check API from VPC"
      cidr_blocks = dependency.vpc.outputs.vpc_cidr_block
    },
    # Spark Master Web UI (port 8080) - from VPC for monitoring
    {
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      description = "Allow access to Spark Master Web UI from VPC"
      cidr_blocks = dependency.vpc.outputs.vpc_cidr_block
    },
    # Spark Worker Web UI (port 8081) - from VPC for monitoring
    {
      from_port   = 8081
      to_port     = 8081
      protocol    = "tcp"
      description = "Allow access to Spark Worker Web UI from VPC"
      cidr_blocks = dependency.vpc.outputs.vpc_cidr_block
    },
    # SSM access (port 443) - for Session Manager
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Allow SSM Session Manager access"
      cidr_blocks = dependency.vpc.outputs.vpc_cidr_block
    }
  ]

  # Egress rules - same as ops security group
  egress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS to VPC endpoints (SSM, ECR, STS, CloudWatch Logs)"
      cidr_blocks = dependency.vpc.outputs.vpc_cidr_block
    },
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
    {
      from_port   = 123
      to_port     = 123
      protocol    = "udp"
      description = "NTP to AWS Time Sync service"
      cidr_blocks = "169.254.169.123/32"
    },
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "HTTP for package updates to AWS repositories"
      cidr_blocks = "0.0.0.0/0"
    },
    # Allow outbound to RDS PostgreSQL (port 5432)
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "Allow outbound to RDS PostgreSQL"
      cidr_blocks = dependency.vpc.outputs.vpc_cidr_block
    }
  ]

  tags = merge(local.common_tags, {
    Component = "collibra-dq-standalone-sg"
    Name      = "${local.org}-${local.env}-collibra-dq-standalone-sg"
  })
}
