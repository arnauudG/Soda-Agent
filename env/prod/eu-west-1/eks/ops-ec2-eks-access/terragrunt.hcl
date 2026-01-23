include "root" { path = find_in_parent_folders("root.hcl") }

locals {
  parent       = read_terragrunt_config(find_in_parent_folders("root.hcl"))
  org          = local.parent.locals.org
  env          = local.parent.locals.env
  aws_region   = local.parent.locals.aws_region
  modules_root = local.parent.locals.modules_root

  cluster_name = "${local.org}-${local.env}-eks"
  role_name    = "${local.org}-${local.env}-ops-role"
}

# Order: EKS and EC2 role first (no outputs read)
dependencies {
  paths = [
    "..",               # EKS cluster
    "../../ops/ec2-ops" # EC2 ops instance
  ]
}

terraform { source = "${local.modules_root}/ops-ec2-eks-access" }

inputs = {
  region       = local.aws_region
  cluster_name = local.cluster_name
  role_name    = local.role_name
  policy_name  = "ops-eks-describe"
}
