# env/<env>/<region>/addons/collibra-dq-standalone/alb/target-group-attachment/terragrunt.hcl
# Attach Collibra DQ instance to ALB target group

# Note: We don't use include here to avoid nested includes
# Instead, we read the env-level root.hcl directly
locals {
  parent = read_terragrunt_config("../../../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  path_parts = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 5
  aws_region   = local.path_parts[local.region_index]
  
  modules_root = local.parent.locals.modules_root
  
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "addons/collibra-dq-standalone/alb/target-group-attachment/terraform.tfstate"
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

dependency "alb" {
  config_path = ".."
  mock_outputs = {
    target_group_arns = {
      collibra-dq = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/mock-tg/1234567890123456"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependency "collibra_dq" {
  config_path = "../.."
  mock_outputs = {
    instance_id = "i-mock-123456"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependencies {
  paths = [
    "..",
    "../.."
  ]
}

terraform {
  source = "${local.modules_root}/network/alb/target-group-attachment"
}

inputs = {
  target_group_arn = dependency.alb.outputs.target_group_arns["collibra-dq"]
  target_id       = dependency.collibra_dq.outputs.instance_id
  port            = 9000
}
