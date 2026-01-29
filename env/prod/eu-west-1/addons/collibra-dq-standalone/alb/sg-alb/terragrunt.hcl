# env/<env>/<region>/addons/collibra-dq-standalone/alb/sg-alb/terragrunt.hcl
# Security Group for ALB

# Note: We don't use include here to avoid nested includes
# Instead, we read the env-level root.hcl directly
locals {
  parent = read_terragrunt_config("../../../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  path_parts = split("/", get_terragrunt_dir())
  # From: env/prod/eu-west-1/addons/collibra-dq-standalone/alb/sg-alb
  # region is 5 levels up from sg-alb
  region_index = length(local.path_parts) - 5
  aws_region   = local.path_parts[local.region_index]
  
  common_tags = merge(local.parent.locals.common_tags, {
    Region = local.aws_region
  })
  
  modules_root = local.parent.locals.modules_root
  
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "addons/collibra-dq-standalone/alb/sg-alb/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = local.lock_table
    encrypt        = true
  }
}

dependency "vpc" {
  config_path = "../../../../network/vpc"
  mock_outputs = {
    vpc_id         = "vpc-123456"
    vpc_cidr_block = "10.10.0.0/16"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependencies {
  paths = [
    "../../../../network/vpc"
  ]
}

terraform {
  source = "${local.modules_root}/security/security-group/ops"
}

inputs = {
  name        = "${local.org}-${local.env}-collibra-dq-alb-sg"
  description = "Security group for Collibra DQ ALB - allows HTTPS (443) and HTTP (80) from internet"
  vpc_id      = dependency.vpc.outputs.vpc_id

  # Ingress rules - allow HTTPS and HTTP from internet
  ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Allow HTTPS from internet"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "Allow HTTP from internet (will redirect to HTTPS if certificate configured)"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  # Egress rules - allow traffic to Collibra DQ instance (port 9000)
  # This will be restricted to the Collibra DQ instance security group
  egress_with_cidr_blocks = [
    {
      from_port   = 9000
      to_port     = 9000
      protocol    = "tcp"
      description = "Allow traffic to Collibra DQ instance"
      cidr_blocks = dependency.vpc.outputs.vpc_cidr_block
    }
  ]

  tags = merge(local.common_tags, {
    Component = "alb-sg"
    Name      = "${local.org}-${local.env}-collibra-dq-alb-sg"
  })
}
