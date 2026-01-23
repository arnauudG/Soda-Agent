# /root.hcl  (repo root)
# Organization-level configuration - shared across all environments and regions

locals {
  # Organization name - defined once at the top level
  org = "datashift"
}

inputs = {
  org = local.org
}