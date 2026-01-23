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

  # Pod Identity (newer alternative to IRSA for some use cases)
  enable_pod_identity = false  # Keep false for now, IRSA is sufficient

  # Access entries for better RBAC management (optional)
  # access_entries = {}

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

  # Encryption at rest - encrypt all resources for better security
  cluster_encryption_config = {
    provider_key_arn = null  # Use AWS managed keys
    resources        = ["secrets", "configmaps"]  # Encrypt secrets and configmaps
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

      # Disk configuration
      disk_size = 20
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

      # Update configuration for zero-downtime updates
      update_config = {
        max_unavailable_percentage = 50
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
      source_security_group_id = dependency.sg_ops.outputs.security_group_id
    }
  }

  # Node security group additional rules - allow outbound to external data sources
  # Note: EKS module allows all outbound by default, but we're being explicit here
  # for common data source ports that Soda Agent might need to connect to.
  # Traffic flows: Pods -> Node SG -> NAT Gateway -> Internet
  # To restrict access, modify cidr_blocks to specific IPs/CIDRs instead of "0.0.0.0/0"
  node_security_group_additional_rules = {
    # Allow HTTPS to external APIs and services
    egress_https_external = {
      description = "Allow HTTPS to external APIs and services"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    # Allow HTTP (for some APIs that don't use HTTPS)
    egress_http_external = {
      description = "Allow HTTP to external services"
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    # Common database ports (adjust based on your data sources)
    # PostgreSQL
    egress_postgres = {
      description = "Allow PostgreSQL connections to external databases"
      protocol    = "tcp"
      from_port   = 5432
      to_port     = 5432
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    # MySQL/MariaDB
    egress_mysql = {
      description = "Allow MySQL/MariaDB connections to external databases"
      protocol    = "tcp"
      from_port   = 3306
      to_port     = 3306
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    # SQL Server
    egress_sqlserver = {
      description = "Allow SQL Server connections to external databases"
      protocol    = "tcp"
      from_port   = 1433
      to_port     = 1433
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    # MongoDB
    egress_mongodb = {
      description = "Allow MongoDB connections to external databases"
      protocol    = "tcp"
      from_port   = 27017
      to_port     = 27017
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    # Snowflake
    egress_snowflake = {
      description = "Allow Snowflake connections"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    # DNS for external resolution
    egress_dns_udp = {
      description = "Allow DNS UDP for external resolution"
      protocol    = "udp"
      from_port   = 53
      to_port     = 53
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    egress_dns_tcp = {
      description = "Allow DNS TCP for external resolution"
      protocol    = "tcp"
      from_port   = 53
      to_port     = 53
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  cluster_addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        compute = {
          resources = {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }
      })
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
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    # EBS CSI driver for persistent volumes
    aws-ebs-csi-driver = {
      most_recent = true
      service_account_role_arn = null  # Will use IRSA automatically
    }
  }

  # Cluster maintenance window (optional - uncomment if you want scheduled maintenance)
  # cluster_maintenance_window = {
  #   day_of_week = "sunday"
  #   start_time  = "03:00"
  #   duration    = 4  # hours
  # }

  # Merge common tags with component-specific tags
  tags = merge(local.common_tags, {
    Component = "eks"
    Name      = local.cluster_name
  })
}