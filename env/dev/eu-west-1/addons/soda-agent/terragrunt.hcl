include "root" { path = find_in_parent_folders("root.hcl") }

locals {
  parent       = read_terragrunt_config(find_in_parent_folders("root.hcl"))
  org          = local.parent.locals.org
  env          = local.parent.locals.env
  aws_region   = local.parent.locals.aws_region
  modules_root = local.parent.locals.modules_root

  cluster_name = "${local.org}-${local.env}-eks"
  namespace    = "soda-agent"
  agent_name   = "${local.org}-${local.env}-agent"  

  cloud_region   = get_env("SODA_CLOUD_REGION", "eu")
  cloud_endpoint = local.cloud_region == "us" ? "https://cloud.us.soda.io" : "https://cloud.soda.io"
}

terraform { source = "${local.modules_root}/helm-soda-agent" }

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

# Order only; no outputs read
dependencies { paths = ["../../eks"] }

inputs = {
  cluster_name = local.cluster_name
  region       = local.aws_region
  namespace    = local.namespace
  agent_name   = local.agent_name

  # Use the Soda Helm chart repository
  chart_repo    = "soda-agent"
  chart_version = ""
  chart_name    = "soda-agent"

  cloud_endpoint = local.cloud_endpoint

  # Soda Cloud API keys for agent authentication to Soda Cloud
  api_key_id     = get_env("SODA_API_KEY_ID", "")
  api_key_secret = get_env("SODA_API_KEY_SECRET", "")

  # Soda Image Registry credentials for pulling images from private registry
  image_credentials_id       = get_env("SODA_IMAGE_APIKEY_ID", "")
  image_credentials_secret   = get_env("SODA_IMAGE_APIKEY_SECRET", "")
  existing_image_pull_secret = ""

  log_format = get_env("SODA_LOG_FORMAT", "raw")
  log_level  = get_env("SODA_LOG_LEVEL", "INFO")

  create_namespace = true
}