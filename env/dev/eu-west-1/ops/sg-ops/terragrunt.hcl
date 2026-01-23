include "root" { path = find_in_parent_folders("root.hcl") }

locals {
  parent     = read_terragrunt_config(find_in_parent_folders("root.hcl"))
  org        = local.parent.locals.org
  env        = local.parent.locals.env
  aws_region = local.parent.locals.aws_region
  common_tags = local.parent.locals.common_tags
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
  source = "tfr://registry.terraform.io/terraform-aws-modules/security-group/aws?version=5.1.0"
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
