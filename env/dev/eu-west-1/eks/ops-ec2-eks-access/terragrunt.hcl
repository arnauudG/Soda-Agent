# env/<env>/<region>/eks/ops-ec2-eks-access/terragrunt.hcl
# EKS Access configuration - includes env-level root.hcl (1 level, avoids nested includes)

include "env" {
  path = "../../../root.hcl"
}

locals {
  parent = read_terragrunt_config("../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  # Extract region from path: env/dev/eu-west-1/eks/ops-ec2-eks-access
  # Path structure: [env, dev, eu-west-1, eks, ops-ec2-eks-access]
  # Region is at index 2 (length - 3)
  path_parts = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 3  # region is 3 levels up from ops-ec2-eks-access
  aws_region   = local.path_parts[local.region_index]
  
  modules_root = local.parent.locals.modules_root
  
  # State bucket and lock table names
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "eks/ops-ec2-eks-access/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = local.lock_table
    encrypt        = true
  }
}

# Dependencies - get outputs from EKS and EC2 modules
dependency "eks" {
  config_path = ".."
  mock_outputs = {
    cluster_name = "mock-cluster"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependency "ec2_ops" {
  config_path = "../../ops/ec2-ops"
  mock_outputs = {
    iam_role_name = "mock-role"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependencies {
  paths = [
    "..",               # EKS cluster
    "../../ops/ec2-ops" # EC2 ops instance
  ]
}

terraform { source = "${local.modules_root}/security/iam/ops-eks-access" }

inputs = {
  region       = local.aws_region
  # Get cluster_name from EKS module output instead of hardcoding
  cluster_name = dependency.eks.outputs.cluster_name
  # Get role_name from EC2 module output instead of hardcoding
  role_name    = dependency.ec2_ops.outputs.iam_role_name
  policy_name  = "ops-eks-describe"
}
