# env/common.hcl
# Common Terragrunt configuration shared by all environments and regions
# This file contains generate blocks for provider and backend that are identical across all modules
#
# Usage: Include this file in region-specific root.hcl files
#   include "common" {
#     path   = find_in_parent_folders("common.hcl")
#     expose = true
#   }

# Generate provider configuration
# Note: aws_region must be set in the including file's locals
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    provider "aws" {
      region = "${local.aws_region}"
    }
  HCL
}

# Generate backend configuration
# The actual backend config (bucket, key, etc.) comes from remote_state block
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    terraform {
      backend "s3" {}
    }
  HCL
}
