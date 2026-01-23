# /root.hcl  (repo root)
locals {
  org        = "datashift"
  env        = "dev"           # default; env shims override
  aws_region = "eu-west-1"
  tg_download_dir = pathexpand("~/.terragrunt-cache")
  state_bucket = "${local.org}-${local.env}-tfstate-${get_aws_account_id()}-${local.aws_region}"
  lock_table   = "${local.org}-${local.env}-tf-locks"
}

download_dir = local.tg_download_dir
retry_max_attempts = 3
retry_sleep_interval_sec = 3

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "${path_relative_to_include()}/terraform.tfstate"
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

inputs = { org = local.org, env = local.env, aws_region = local.aws_region }