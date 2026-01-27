# env/<env>/<region>/addons/collibra-dq/terragrunt.hcl
# Collibra DQ configuration - includes env-level root.hcl (1 level, avoids nested includes)

include "env" {
  path = "../../../root.hcl"
}

locals {
  parent = read_terragrunt_config("../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  # Extract region from path: env/dev/eu-west-1/addons/collibra-dq
  # Path structure: [env, dev, eu-west-1, addons, collibra-dq]
  # Region is at index 2 (length - 3)
  path_parts = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 3  # region is 3 levels up from collibra-dq
  aws_region   = local.path_parts[local.region_index]
  
  modules_root = local.parent.locals.modules_root

  namespace   = "collibra-dq"
  release_name = "collibra-dq"
  
  # State bucket and lock table names
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
  
  # License key from environment variable
  license_key = get_env("COLLIBRA_DQ_LICENSE_KEY", "")
  
  # Image registry credentials from environment variables
  image_registry_url      = get_env("COLLIBRA_DQ_IMAGE_REGISTRY_URL", "")
  image_registry_username = get_env("COLLIBRA_DQ_IMAGE_REGISTRY_USERNAME", "")
  image_registry_password = get_env("COLLIBRA_DQ_IMAGE_REGISTRY_PASSWORD", "")
  
  # Helm chart configuration
  chart_repo    = get_env("COLLIBRA_DQ_CHART_REPO", "")
  chart_version = get_env("COLLIBRA_DQ_CHART_VERSION", "")
  chart_name    = get_env("COLLIBRA_DQ_CHART_NAME", "collibra-dq")
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "addons/collibra-dq/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = local.lock_table
    encrypt        = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    provider "aws" { region = "${local.aws_region}" }
  HCL
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    terraform {
      backend "s3" {}
    }
  HCL
}

# Dependency on EKS - get cluster_name from output
dependency "eks" {
  config_path = "../../eks"
  mock_outputs = {
    cluster_name = "mock-cluster"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

# Dependency on RDS - get PostgreSQL connection details from output
dependency "rds" {
  config_path = "../../database/rds-collibra-dq/rds"
  mock_outputs = {
    db_instance_address = "mock-rds-endpoint.rds.amazonaws.com"
    db_instance_port    = 5432
    db_instance_name    = "collibra_dq"
    db_instance_username = "collibra_dq_admin"
    db_instance_password = "mock-password"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

terraform { source = "${local.modules_root}/application/helm/collibra-dq" }

generate "versions_override" {
  path      = "versions_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    terraform {
      required_providers {
        aws        = { source = "hashicorp/aws",        version = ">= 5.0, < 6.0" }
        kubernetes = { source = "hashicorp/kubernetes", version = ">= 2.23, < 3.0" }
        helm       = { source = "hashicorp/helm",       version = ">= 2.12, < 3.0" }
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

dependencies { 
  paths = [
    "../../eks",
    "../../database/rds-collibra-dq/rds"
  ]
}

inputs = {
  # Get cluster_name from EKS module output instead of hardcoding
  cluster_name = dependency.eks.outputs.cluster_name
  region       = local.aws_region
  namespace    = local.namespace
  release_name = local.release_name

  # Helm chart configuration
  chart_repo    = local.chart_repo
  chart_version = local.chart_version
  chart_name    = local.chart_name

  # License key (required)
  license_key = local.license_key

  # PostgreSQL connection (required - get from RDS dependency output, not hardcoded)
  postgresql_host     = dependency.rds.outputs.db_instance_address
  postgresql_port     = dependency.rds.outputs.db_instance_port
  postgresql_database = dependency.rds.outputs.db_instance_name
  postgresql_username = dependency.rds.outputs.db_instance_username
  postgresql_password = dependency.rds.outputs.db_instance_password

  # Image registry credentials (required for private registry)
  image_registry_url      = local.image_registry_url
  image_registry_username = local.image_registry_username
  image_registry_password = local.image_registry_password
  existing_image_pull_secret = ""

  # Service type - LoadBalancer for external access (dev)
  service_type = "LoadBalancer"

  # Resource configuration (minimum requirements per Collibra DQ documentation)
  resource_requests = {
    dq_web = {
      cpu    = "1"
      memory = "2Gi"
    }
    dq_agent = {
      cpu    = "1"
      memory = "1Gi"
    }
    dq_metastore = {
      cpu    = "1"
      memory = "2Gi"
    }
    spark = {
      cpu    = "2"
      memory = "2Gi"
    }
  }

  resource_limits = {
    dq_web = {
      cpu    = "1"
      memory = "2Gi"
    }
    dq_agent = {
      cpu    = "1"
      memory = "1Gi"
    }
    dq_metastore = {
      cpu    = "1"
      memory = "2Gi"
    }
    spark = {
      cpu    = "2"
      memory = "2Gi"
    }
  }

  # Create namespace
  create_namespace = true

  # Additional values can be added here if needed
  additional_values = {}
}
