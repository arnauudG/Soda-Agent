# env/<env>/<region>/network/network/vpc-endpoints/terragrunt.hcl
# VPC Endpoints configuration - includes env-level root.hcl (1 level, avoids nested includes)

include "env" {
  path = "../../../root.hcl"
}

locals {
  parent = read_terragrunt_config("../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  # Extract region from path: env/dev/eu-west-1/network/network/vpc-endpoints
  path_parts = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 3  # region is 3 levels up from network/vpc-endpoints
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
    key            = "network/network/vpc-endpoints/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = local.lock_table
    encrypt        = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    provider "aws" {
      region = "${local.aws_region}"
    }
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
  config_path = "../vpc"
  mock_outputs = {
    vpc_id                  = "vpc-123456"
    vpc_cidr_block          = "10.10.0.0/16"
    private_subnets         = ["subnet-a", "subnet-b", "subnet-c"]
    private_route_table_ids = ["rtb-a", "rtb-b", "rtb-c"] # needed for S3 gateway endpoint
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "destroy"]
}

# Ensure proper ordering
dependencies { paths = ["../vpc"] }

terraform {
  source = "${local.modules_root}/network/vpc-endpoints"
}

inputs = {
  # Get VPC ID from dependency output (not hardcoded)
  vpc_id = dependency.vpc.outputs.vpc_id

  # Shared SG for Interface endpoints
  create_security_group      = true
  security_group_name        = "${local.org}-${local.env}-vpce-sg"
  security_group_description = "Allow HTTPS from VPC to VPC Endpoints"
  security_group_rules = [
    {
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Allow HTTPS from inside VPC"
      # Get VPC CIDR block from dependency output (not hardcoded)
      cidr_blocks = [dependency.vpc.outputs.vpc_cidr_block]
    },
    {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
  
  # Security group tags
  security_group_tags = merge(local.common_tags, {
    Component = "network"
    Name      = "${local.org}-${local.env}-vpce-sg"
  })

  # ---- Interface endpoints ----
  endpoints = {
    # SSM trio (Session Manager)
    ssm = {
      service             = "ssm"
      service_type        = "Interface"
      private_dns_enabled = true
      # Get subnet IDs from dependency output (not hardcoded)
      subnet_ids = dependency.vpc.outputs.private_subnets
      tags                = merge(local.common_tags, {
        Component = "network"
        Name      = "${local.org}-${local.env}-vpce-ssm"
      })
    }
    ssmmessages = {
      service             = "ssmmessages"
      service_type        = "Interface"
      private_dns_enabled = true
      # Get subnet IDs from dependency output (not hardcoded)
      subnet_ids = dependency.vpc.outputs.private_subnets
      tags                = merge(local.common_tags, {
        Component = "network"
        Name      = "${local.org}-${local.env}-vpce-ssmmessages"
      })
    }
    ec2messages = {
      service             = "ec2messages"
      service_type        = "Interface"
      private_dns_enabled = true
      # Get subnet IDs from dependency output (not hardcoded)
      subnet_ids = dependency.vpc.outputs.private_subnets
      tags                = merge(local.common_tags, {
        Component = "network"
        Name      = "${local.org}-${local.env}-vpce-ec2messages"
      })
    }

    # ECR / STS / CloudWatch Logs — common EKS needs
    ecr_api = {
      service             = "ecr.api"
      service_type        = "Interface"
      private_dns_enabled = true
      # Get subnet IDs from dependency output (not hardcoded)
      subnet_ids = dependency.vpc.outputs.private_subnets
      tags                = merge(local.common_tags, {
        Component = "network"
        Name      = "${local.org}-${local.env}-vpce-ecr-api"
      })
    }
    ecr_dkr = {
      service             = "ecr.dkr"
      service_type        = "Interface"
      private_dns_enabled = true
      # Get subnet IDs from dependency output (not hardcoded)
      subnet_ids = dependency.vpc.outputs.private_subnets
      tags                = merge(local.common_tags, {
        Component = "network"
        Name      = "${local.org}-${local.env}-vpce-ecr-dkr"
      })
    }
    sts = {
      service             = "sts"
      service_type        = "Interface"
      private_dns_enabled = true
      # Get subnet IDs from dependency output (not hardcoded)
      subnet_ids = dependency.vpc.outputs.private_subnets
      tags                = merge(local.common_tags, {
        Component = "network"
        Name      = "${local.org}-${local.env}-vpce-sts"
      })
    }
    logs = {
      service             = "logs"
      service_type        = "Interface"
      private_dns_enabled = true
      # Get subnet IDs from dependency output (not hardcoded)
      subnet_ids = dependency.vpc.outputs.private_subnets
      tags                = merge(local.common_tags, {
        Component = "network"
        Name      = "${local.org}-${local.env}-vpce-logs"
      })
    }

    # ---- Gateway endpoint for S3 (attach to private route tables) ----
    s3 = {
      service             = "s3"
      service_type        = "Gateway"
      # Get route table IDs from dependency output (not hardcoded)
      route_table_ids = dependency.vpc.outputs.private_route_table_ids
      tags                = merge(local.common_tags, {
        Component = "network"
        Name      = "${local.org}-${local.env}-vpce-s3"
      })
    }
  }

  tags = merge(local.common_tags, {
    Component = "network"
    Name      = "${local.org}-${local.env}-vpce"
  })
}