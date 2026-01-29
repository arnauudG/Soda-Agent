# env/dev/eu-west-1/root.hcl
# Region-specific configuration for dev/eu-west-1
# This file is included by module-level terragrunt.hcl files
#
# Hierarchy:
#   env/common.hcl          - Provider and backend generate blocks
#   env/dev/root.hcl        - Environment-level settings (org, env, modules_root)
#   env/dev/eu-west-1/root.hcl  - This file (region-level, remote_state)

include "env" {
  path = "../root.hcl"
}

# Include common generate blocks (provider, backend)
include "common" {
  path   = find_in_parent_folders("common.hcl")
  expose = true
}

locals {
  # Read parent config for org, env, and other settings
  parent = read_terragrunt_config("../root.hcl")

  org        = local.parent.locals.org
  env        = local.parent.locals.env
  aws_region = "eu-west-1"

  # Common tags from parent, with Region added
  common_tags = merge(local.parent.locals.common_tags, {
    Region = local.aws_region
  })

  # Modules root path
  modules_root = local.parent.locals.modules_root

  # State bucket and lock table names
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
}

# Remote state configuration - inherited by all modules that include this file
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

inputs = merge(
  local.parent.inputs,
  {
    aws_region   = local.aws_region
    common_tags  = local.common_tags
    modules_root = local.modules_root
  }
)
