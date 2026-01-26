# env/dev/eu-west-1/root.hcl
# Region-specific configuration for dev/eu-west-1
# Includes environment-level config from ../root.hcl

include "env" {
  path = "../root.hcl"
}

locals {
  # This file is at env/dev/eu-west-1/root.hcl, parent is at env/dev/root.hcl
  # The include block uses "../root.hcl" which is relative to this file's location
  # For read_terragrunt_config, paths are relative to the calling terragrunt.hcl
  # get_parent_terragrunt_dir() returns the parent of the calling terragrunt.hcl
  # We need to go up one more level from there to get to env level
  # Construct path: from calling dir, find "eu-west-1", go up one level
  calling_dir = get_terragrunt_dir()
  path_parts = split("/", local.calling_dir)
  region_idx = index(local.path_parts, "eu-west-1")
  # If region found, slice to env level; otherwise try going up from parent
  env_dir = local.region_idx >= 0 ? join("/", slice(local.path_parts, 0, local.region_idx)) : "${get_parent_terragrunt_dir()}/.."
  parent = read_terragrunt_config("${local.env_dir}/root.hcl")
  org           = local.parent.locals.org
  env           = local.parent.locals.env
  aws_region    = "eu-west-1"  # Region is defined at the region level
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