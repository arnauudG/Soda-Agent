# env/prod/eu-west-1/root.hcl
# Region-specific configuration for prod/eu-west-1
# Includes environment-level config from ../root.hcl

include "env" {
  path = "../root.hcl"
}

locals {
  parent     = read_terragrunt_config("../root.hcl")
  org        = local.parent.locals.org
  env        = local.parent.locals.env
  aws_region = "eu-west-1"  # Region is defined at the region level
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
    key            = "${path_relative_to_include()}/terraform.tfstate"
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

inputs = merge(
  local.parent.inputs,
  {
    aws_region  = local.aws_region
    common_tags = local.common_tags
  }
)