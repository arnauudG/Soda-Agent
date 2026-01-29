# env/<env>/<region>/eks/terragrunt.hcl
# EKS configuration - includes env-level root.hcl (1 level, avoids nested includes)

include "env" {
  path = "../../root.hcl"
}

locals {
  parent = read_terragrunt_config("../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  # Extract region from path: env/prod/eu-west-1/eks
  path_parts = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 2  # region is 2 levels up from eks
  aws_region   = local.path_parts[local.region_index]
  
  # Common tags from parent, with Region added
  common_tags = merge(local.parent.locals.common_tags, {
    Region = local.aws_region
  })
  
  modules_root = local.parent.locals.modules_root

  cluster_name = "${local.org}-${local.env}-eks"

  # Environment-specific node group configuration (prod: cost-optimized while maintaining performance)
  node_group_config = {
    desired_size = 3
    min_size     = 2
    max_size     = 5
    instance_types = ["t3.small"]  # Reduced from t3.medium/t3.large for cost savings
    capacity_type  = "SPOT"
  }

  # CloudWatch log retention (days) - longer for prod
  cloudwatch_log_retention = 30
  
  # State bucket and lock table names
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
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

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "eks/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = local.lock_table
    encrypt        = true
  }
}

terraform {
  source = "${local.modules_root}/compute/eks/cluster"
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

inputs = {
  cluster_name    = local.cluster_name
  cluster_version = "1.31"

  # Get VPC and subnet IDs from dependency outputs (not hardcoded)
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets
  # Get security group ID from dependency output (not hardcoded)
  ops_security_group_id = dependency.sg_ops.outputs.security_group_id

  enable_irsa = true

  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  # Pod Identity (newer alternative to IRSA for some use cases)
  enable_pod_identity = false  # Keep false for now, IRSA is sufficient

  # Access entries for better RBAC management (optional)
  # access_entries = {}

  # Prod: Restrict public access (private endpoint only recommended)
  # Set to false and use only private endpoint for maximum security
  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true
  # If public access is needed, restrict to specific CIDRs:
  # cluster_endpoint_public_access = true
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

  # Encryption at rest - encrypt secrets for better security
  # Note: AWS EKS only supports encrypting "secrets", not "configmaps"
  cluster_encryption_config = {
    provider_key_arn = null  # Use AWS managed keys
    resources        = ["secrets"]  # Only secrets can be encrypted in EKS
  }

  # Environment-specific node group configuration (prod: larger, more reliable)
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

      # Disk configuration (prod: larger disk)
      disk_size = 50
      disk_type = "gp3"

      # Instance metadata options for security
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
        instance_metadata_tags      = "enabled"
      }

      # Node labels for better pod scheduling
      labels = {
        Environment = local.env
        NodeGroup   = "ops"
        ManagedBy    = "terraform"
      }

      # Update configuration for zero-downtime updates (prod: more conservative)
      update_config = {
        max_unavailable_percentage = 33  # More conservative for prod
      }

      # Taints (optional - uncomment if you want to prevent non-tolerated pods)
      # taints = [{
      #   key    = "ops"
      #   value  = "true"
      #   effect = "NO_SCHEDULE"
      # }]
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
      # Get security group ID from dependency output (not hardcoded)
      source_security_group_id = dependency.sg_ops.outputs.security_group_id
    }
  }

  # Node security group additional rules
  # Note: EKS module already allows all outbound traffic by default (0.0.0.0/0)
  # This means pods can reach external data sources via: Pods -> Node SG -> NAT Gateway -> Internet
  # No additional egress rules needed unless you want to restrict access to specific IPs/CIDRs
  # node_security_group_additional_rules = {}

  cluster_addons = {
    coredns = {
      most_recent = true
      # Note: Resource requests/limits for CoreDNS should be managed via Kubernetes manifests
      # The EKS addon configuration_values doesn't support compute.resources format
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
      # VPC CNI configuration for better networking performance
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "2"  # Prod: more warm IPs
        }
      })
    }
    # EBS CSI driver for persistent volumes
    # Note: Temporarily disabled due to long installation times
    # Can be enabled later when persistent volumes are needed
    # aws-ebs-csi-driver = {
    #   most_recent = true
    #   service_account_role_arn = null  # Will use IRSA automatically
    # }
  }

  # Cluster maintenance window (optional - uncomment if you want scheduled maintenance)
  # cluster_maintenance_window = {
  #   day_of_week = "sunday"
  #   start_time  = "03:00"
  #   duration    = 4  # hours
  # }

  # Cost Optimization Notes:
  # - Instance types reduced to t3.small for cost savings (from t3.medium/t3.large)
  # - SPOT instances provide ~70% cost savings
  # - For additional savings, consider:
  #   1. Cluster Autoscaler for dynamic scaling based on workload
  #   2. Scheduled scaling during off-hours (if applicable)
  #   3. Right-sizing based on actual resource usage metrics

  # Merge common tags with component-specific tags
  tags = merge(local.common_tags, {
    Component = "eks"
    Name      = local.cluster_name
  })
}