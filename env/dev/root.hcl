# env/dev/root.hcl
# Environment-level configuration for dev

locals {
  # Hardcode org value (matches previous root.hcl: org = "datashift")
  org        = "datashift"
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

inputs = {
  org          = local.org
  env          = local.env
  modules_root = local.modules_root
  common_tags  = local.common_tags
}
