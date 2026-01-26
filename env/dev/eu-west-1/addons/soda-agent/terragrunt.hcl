# env/<env>/<region>/addons/soda-agent/terragrunt.hcl
# Soda Agent configuration - includes env-level root.hcl (1 level, avoids nested includes)

include "env" {
  path = "../../../root.hcl"
}

locals {
  parent = read_terragrunt_config("../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  # Extract region from path: env/dev/eu-west-1/addons/soda-agent
  # Path structure: [env, dev, eu-west-1, addons, soda-agent]
  # Region is at index 2 (length - 3)
  path_parts = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 3  # region is 3 levels up from soda-agent
  aws_region   = local.path_parts[local.region_index]
  
  modules_root = local.parent.locals.modules_root

  namespace    = "soda-agent"
  # Include region in agent name to ensure uniqueness across regions
  # If you need to reuse an existing agent name, delete the old registration in Soda Cloud first
  agent_name   = "${local.org}-${local.env}-${local.aws_region}-agent"  

  cloud_region   = get_env("SODA_CLOUD_REGION", "eu")
  cloud_endpoint = local.cloud_region == "us" ? "https://cloud.us.soda.io" : "https://cloud.soda.io"
  
  # State bucket and lock table names
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
  
  # API keys for Soda Cloud
  api_key_id     = get_env("SODA_API_KEY_ID", "")
  api_key_secret = get_env("SODA_API_KEY_SECRET", "")
  
  # Image registry credentials - use separate if provided, otherwise use same as Soda Cloud (1.2.0+ default)
  image_credentials_id     = get_env("SODA_IMAGE_APIKEY_ID", local.api_key_id)
  image_credentials_secret = get_env("SODA_IMAGE_APIKEY_SECRET", local.api_key_secret)
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "addons/soda-agent/terraform.tfstate"
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

terraform { source = "${local.modules_root}/application/helm/soda-agent" }

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

dependencies { paths = ["../../eks"] }

inputs = {
  # Get cluster_name from EKS module output instead of hardcoding
  cluster_name = dependency.eks.outputs.cluster_name
  region       = local.aws_region
  namespace    = local.namespace
  agent_name   = local.agent_name

  # Use the Soda Helm chart repository
  chart_repo    = "soda-agent"
  chart_version = "1.3.13"  # Use latest available version for fresh install
  chart_name    = "soda-agent"

  cloud_endpoint = local.cloud_endpoint

  # Soda Cloud API keys for agent authentication to Soda Cloud
  api_key_id     = local.api_key_id
  api_key_secret = local.api_key_secret

  # Soda Image Registry credentials for pulling images from private registry
  # If SODA_IMAGE_APIKEY_ID is not set, use the same API keys as Soda Cloud (default behavior for 1.2.0+)
  # This is the recommended approach per Soda documentation
  image_credentials_id       = local.image_credentials_id
  image_credentials_secret   = local.image_credentials_secret
  existing_image_pull_secret = ""

  log_format = get_env("SODA_LOG_FORMAT", "raw")
  log_level  = get_env("SODA_LOG_LEVEL", "INFO")

  # Fresh install - create namespace
  create_namespace = true
}