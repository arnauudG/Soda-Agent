# env/dev/root.hcl
# Environment-level configuration for dev

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  root       = read_terragrunt_config(find_in_parent_folders("root.hcl"))
  org        = local.root.locals.org  # Inherit from repo root
  env        = "dev"
  # Region is defined at the region level, not here

  # From this file's dir (env/dev/) go up 2 levels to repo root, then into /module
  # => env/dev/../../module  ==  <repo>/module
  modules_root = "${get_terragrunt_dir()}/../../module"

  tg_download_dir = pathexpand("~/.terragrunt-cache")

  # Common tags applied to all resources (Region will be added at region level)
  common_tags = {
    Terraform   = "true"
    ManagedBy   = "Terragrunt"
    Org         = local.org
    Env         = local.env
    Project     = "Soda-Agent"
    CostCenter  = "Engineering"
  }
}

download_dir = local.tg_download_dir
retry_max_attempts = 3
retry_sleep_interval_sec = 3

inputs = merge(
  local.root.inputs,
  {
    org          = local.org
    env          = local.env
    modules_root = local.modules_root
    common_tags  = local.common_tags
  }
)
