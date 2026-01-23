include "root" { path = find_in_parent_folders("root.hcl") }

locals {
  parent     = read_terragrunt_config(find_in_parent_folders("root.hcl"))
  org        = local.parent.locals.org
  env        = local.parent.locals.env
  aws_region = local.parent.locals.aws_region
}

dependency "vpc" {
  config_path = "../../network/vpc"
  mock_outputs = {
    vpc_id         = "vpc-123456"
    vpc_cidr_block = "10.10.0.0/16"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

terraform {
  source = "tfr://registry.terraform.io/terraform-aws-modules/security-group/aws?version=5.1.0"
}

inputs = {
  name        = "${local.org}-${local.env}-ops-sg"
  description = "Ops instance - SSM only (no inbound)"
  vpc_id      = dependency.vpc.outputs.vpc_id

  ingress_rules = []

  egress_with_cidr_blocks = [
    { from_port = 443, to_port = 443, protocol = "tcp", description = "HTTPS to SSM endpoints", cidr_blocks = "0.0.0.0/0" },
    { from_port = 53, to_port = 53, protocol = "udp", description = "DNS UDP", cidr_blocks = dependency.vpc.outputs.vpc_cidr_block },
    { from_port = 53, to_port = 53, protocol = "tcp", description = "DNS TCP", cidr_blocks = dependency.vpc.outputs.vpc_cidr_block },
    { from_port = 123, to_port = 123, protocol = "udp", description = "NTP AWS Time Sync", cidr_blocks = "169.254.169.123/32" }
  ]

  tags = { Project = "Soda-Agent", Env = local.env, Managed = "terragrunt" }
}
