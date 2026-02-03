# env/stack/addons/soda-agent/terragrunt.hcl
# Soda Agent Helm chart deployment

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "common" {
  path = find_in_parent_folders("common.hcl")
}

locals {
  org        = include.root.locals.org
  env        = include.root.locals.env
  aws_region = include.root.locals.aws_region

  namespace  = "soda-agent"
  agent_name = "${local.org}-${local.env}-${local.aws_region}-agent"

  cloud_region   = get_env("SODA_CLOUD_REGION", "eu")
  cloud_endpoint = local.cloud_region == "us" ? "https://cloud.us.soda.io" : "https://cloud.soda.io"

  # API keys for Soda Cloud
  api_key_id     = get_env("SODA_API_KEY_ID", "")
  api_key_secret = get_env("SODA_API_KEY_SECRET", "")

  # Image registry credentials
  image_credentials_id     = get_env("SODA_IMAGE_APIKEY_ID", local.api_key_id)
  image_credentials_secret = get_env("SODA_IMAGE_APIKEY_SECRET", local.api_key_secret)
}

dependency "eks" {
  config_path = "../../eks"
  mock_outputs = {
    cluster_name = "mock-cluster"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependencies {
  paths = ["../../eks"]
}

terraform {
  source = "${include.root.locals.modules_root}/application/helm/soda-agent"
}

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

inputs = {
  cluster_name = dependency.eks.outputs.cluster_name
  region       = local.aws_region
  namespace    = local.namespace
  agent_name   = local.agent_name

  chart_repo    = "soda-agent"
  chart_version = "1.3.13"
  chart_name    = "soda-agent"

  cloud_endpoint = local.cloud_endpoint

  api_key_id     = local.api_key_id
  api_key_secret = local.api_key_secret

  image_credentials_id       = local.image_credentials_id
  image_credentials_secret   = local.image_credentials_secret
  existing_image_pull_secret = ""

  log_format = get_env("SODA_LOG_FORMAT", "raw")
  log_level  = get_env("SODA_LOG_LEVEL", "INFO")

  create_namespace = true
}
