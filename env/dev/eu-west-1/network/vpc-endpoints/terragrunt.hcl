# env/<env>/<region>/network/vpc-endpoints/terragrunt.hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  parent     = read_terragrunt_config(find_in_parent_folders("root.hcl"))
  org        = local.parent.locals.org
  env        = local.parent.locals.env
  aws_region = local.parent.locals.aws_region
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    vpc_id                  = "vpc-123456"
    vpc_cidr_block          = "10.10.0.0/16"
    private_subnets         = ["subnet-a", "subnet-b", "subnet-c"]
    private_route_table_ids = ["rtb-a", "rtb-b", "rtb-c"] # needed for S3 gateway endpoint
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

# Ensure proper ordering
dependencies { paths = ["../vpc"] }

terraform {
  source = "tfr://registry.terraform.io/terraform-aws-modules/vpc/aws//modules/vpc-endpoints?version=5.8.1"
}

# (Optional) explicit provider pin/region — harmless but nice for clarity
generate "versions_override" {
  path      = "versions_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    terraform {
      required_providers {
        aws = { source = "hashicorp/aws", version = ">= 5.61.0, < 6.0.0" }
      }
    }
  HCL
}

generate "provider_region" {
  path      = "provider_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    provider "aws" { region = "${local.aws_region}" }
  HCL
}

inputs = {
  vpc_id = dependency.vpc.outputs.vpc_id

  # Shared SG for Interface endpoints
  create_security_group      = true
  security_group_name        = "${local.org}-${local.env}-vpce-sg"
  security_group_description = "Allow HTTPS from VPC to VPC Endpoints"
  security_group_vpc_id      = dependency.vpc.outputs.vpc_id
  security_group_rules = [
    {
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Allow HTTPS from inside VPC"
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

  # ---- Interface endpoints ----
  endpoints = {
    # SSM trio (Session Manager)
    ssm = {
      service             = "ssm"
      service_type        = "Interface"
      private_dns_enabled = true
      subnet_ids          = dependency.vpc.outputs.private_subnets
      tags                = { Name = "${local.org}-${local.env}-vpce-ssm" }
    }
    ssmmessages = {
      service             = "ssmmessages"
      service_type        = "Interface"
      private_dns_enabled = true
      subnet_ids          = dependency.vpc.outputs.private_subnets
      tags                = { Name = "${local.org}-${local.env}-vpce-ssmmessages" }
    }
    ec2messages = {
      service             = "ec2messages"
      service_type        = "Interface"
      private_dns_enabled = true
      subnet_ids          = dependency.vpc.outputs.private_subnets
      tags                = { Name = "${local.org}-${local.env}-vpce-ec2messages" }
    }

    # ECR / STS / CloudWatch Logs — common EKS needs
    ecr_api = {
      service             = "ecr.api"
      service_type        = "Interface"
      private_dns_enabled = true
      subnet_ids          = dependency.vpc.outputs.private_subnets
      tags                = { Name = "${local.org}-${local.env}-vpce-ecr-api" }
    }
    ecr_dkr = {
      service             = "ecr.dkr"
      service_type        = "Interface"
      private_dns_enabled = true
      subnet_ids          = dependency.vpc.outputs.private_subnets
      tags                = { Name = "${local.org}-${local.env}-vpce-ecr-dkr" }
    }
    sts = {
      service             = "sts"
      service_type        = "Interface"
      private_dns_enabled = true
      subnet_ids          = dependency.vpc.outputs.private_subnets
      tags                = { Name = "${local.org}-${local.env}-vpce-sts" }
    }
    logs = {
      service             = "logs"
      service_type        = "Interface"
      private_dns_enabled = true
      subnet_ids          = dependency.vpc.outputs.private_subnets
      tags                = { Name = "${local.org}-${local.env}-vpce-logs" }
    }
  }

  # ---- Gateway endpoint for S3 (attach to private route tables) ----
  gateway_endpoints = {
    s3 = {
      service         = "s3"
      route_table_ids = dependency.vpc.outputs.private_route_table_ids
      tags            = { Name = "${local.org}-${local.env}-vpce-s3" }
    }
  }

  tags = {
    Terraform = "true"
    Component = "network"
    Org       = local.org
    Env       = local.env
  }
}