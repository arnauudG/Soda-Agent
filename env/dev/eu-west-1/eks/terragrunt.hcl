include "root" { path = find_in_parent_folders("root.hcl") }

locals {
  parent       = read_terragrunt_config(find_in_parent_folders("root.hcl"))
  org          = local.parent.locals.org
  env          = local.parent.locals.env
  aws_region   = local.parent.locals.aws_region
  modules_root = local.parent.locals.modules_root
  common_tags  = local.parent.locals.common_tags

  cluster_name = "${local.org}-${local.env}-eks"

  # Environment-specific node group configuration
  node_group_config = {
    desired_size = 1
    min_size     = 1
    max_size     = 2
    instance_types = ["t3.small"]
    capacity_type  = "SPOT"
  }

  # CloudWatch log retention (days)
  cloudwatch_log_retention = 7
}

# ---- Terragrunt dependencies whose outputs we read ----
dependency "vpc" {
  # from env/dev/eu-west-1/eks -> env/dev/eu-west-1/network/vpc
  config_path = "../network/vpc"

  # allow init/plan before first apply
  mock_outputs = {
    vpc_id          = "vpc-mock"
    private_subnets = ["subnet-a", "subnet-b", "subnet-c"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependency "sg_ops" {
  # from env/dev/eu-west-1/eks -> env/dev/eu-west-1/ops/sg-ops
  config_path = "../ops/sg-ops"
  mock_outputs = {
    security_group_id = "sg-mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

# optional: only for ordering, no outputs read
dependencies {
  paths = [
    "../network/vpc",
    "../ops/sg-ops",
  ]
}

terraform {
  source = "tfr://registry.terraform.io/terraform-aws-modules/eks/aws?version=20.24.0"
}

# Provider pin & region
generate "versions_override" {
  path      = "versions_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    terraform {
      required_providers {
        aws = { source = "hashicorp/aws", version = ">= 5.61.0, < 6.0.0" }
      }
    }
  HCL
}

generate "provider_region" {
  path      = "provider_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    provider "aws" { region = "${local.aws_region}" }
  HCL
}

inputs = {
  cluster_name    = local.cluster_name
  cluster_version = "1.31"

  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets

  enable_irsa = true

  authentication_mode                      = "API_AND_CONFIG_MAP"
  create_aws_auth_configmap                = true
  manage_aws_auth_configmap                = true
  enable_cluster_creator_admin_permissions = true

  # Dev: Allow public access (can be restricted to specific CIDRs if needed)
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
  # Optional: Restrict public access to specific CIDRs
  # cluster_endpoint_public_access_cidrs = ["1.2.3.4/32"]

  # CloudWatch logging configuration
  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
  cloudwatch_log_group_retention_in_days = local.cloudwatch_log_retention

  # Encryption at rest
  cluster_encryption_config = {
    provider_key_arn = null  # Use AWS managed keys
    resources        = ["secrets"]
  }

  # Environment-specific node group configuration
  eks_managed_node_groups = {
    ops = {
      name            = "${local.org}-${local.env}-ops-ng"
      use_name_prefix = false
      desired_size    = local.node_group_config.desired_size
      min_size        = local.node_group_config.min_size
      max_size        = local.node_group_config.max_size
      instance_types  = local.node_group_config.instance_types
      capacity_type   = local.node_group_config.capacity_type
      ami_type        = "AL2023_x86_64_STANDARD"
    }
  }

  # Allow ops SG to reach the API
  cluster_security_group_additional_rules = {
    allow_ops_to_api = {
      type                     = "ingress"
      description              = "Allow ops EC2 to reach EKS API"
      protocol                 = "tcp"
      from_port                = 443
      to_port                  = 443
      source_security_group_id = dependency.sg_ops.outputs.security_group_id
    }
  }

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
  }

  # Merge common tags with component-specific tags
  tags = merge(local.common_tags, {
    Component = "eks"
    Name      = local.cluster_name
  })
}