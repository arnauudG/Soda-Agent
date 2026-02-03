# env/stack/addons/collibra-dq-standalone/alb/target-group-attachment/terragrunt.hcl
# Attach Collibra DQ instance to ALB target group

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
  source = "${include.root.locals.modules_root}/network/alb/target-group-attachment"
}

inputs = {
  target_group_arn = dependency.alb.outputs.target_group_arns["collibra-dq"]
  target_id        = dependency.collibra_dq.outputs.instance_id
  port             = 9000
}
