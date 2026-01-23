# env/<env>/eu-west-1/root.hcl

locals {
  org        = "datashift"
  env        = "dev"          # or "prod"
  aws_region = "eu-west-1"

  # From this file's dir (env/<env>/eu-west-1/) go up 3 levels to repo root, then into /module
  # => env/<env>/eu-west-1/../../../module  ==  <repo>/module
  modules_root = "${get_terragrunt_dir()}/../../../module"

  state_bucket = "${local.org}-${local.env}-tfstate-${get_aws_account_id()}-${local.aws_region}"
  lock_table   = "${local.org}-${local.env}-tf-locks"
  tg_download_dir = pathexpand("~/.terragrunt-cache")
}

download_dir = local.tg_download_dir

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

inputs = {
  org          = local.org
  env          = local.env
  aws_region   = local.aws_region
  modules_root = local.modules_root
}