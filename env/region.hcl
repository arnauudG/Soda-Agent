# env/region.hcl
# Region-level shared configuration template
# Provides remote_state configuration with dynamic key based on module path
#
# Usage: Include this file in module-level terragrunt.hcl files
#   include "region" {
#     path   = find_in_parent_folders("region.hcl")
#     expose = true
#   }
#
# Note: This file expects the including file to have these locals defined:
#   - org (organization name)
#   - env (environment name)
#   - aws_region (AWS region)
# These are typically read from the parent root.hcl

# Include common generate blocks (provider, backend)
include "common" {
  path   = "${get_terragrunt_dir()}/../../common.hcl"
  expose = true
}

locals {
  # Extract environment and region from path
  # Assumes path structure: env/<env>/<region>/...
  path_parts = split("/", get_terragrunt_dir())
  env_idx    = [for i, v in local.path_parts : i if v == "env"][0]
  env        = local.path_parts[local.env_idx + 1]
  aws_region = local.path_parts[local.env_idx + 2]

  # Organization name (can be overridden by including file)
  org = "datashift"

  # Common tags
  common_tags = {
    Terraform  = "true"
    ManagedBy  = "Terragrunt"
    Org        = local.org
    Env        = local.env
    Region     = local.aws_region
    Project    = "DQ-Infrastructures"
    CostCenter = "Engineering"
  }

  # State bucket and lock table names
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
}

# Remote state configuration with dynamic key
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

# Default inputs
inputs = {
  aws_region  = local.aws_region
  common_tags = local.common_tags
}
