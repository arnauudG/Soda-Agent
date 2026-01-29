# env/<env>/<region>/addons/collibra-dq-standalone/alb/terragrunt.hcl
# Application Load Balancer for Collibra DQ Web Interface (DEV / HTTP-only)

# Note: We don't use include here to avoid nested includes
# Instead, we read the env-level root.hcl directly
locals {
  parent = read_terragrunt_config("../../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env

  path_parts   = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 4
  aws_region   = local.path_parts[local.region_index]

  common_tags = merge(local.parent.locals.common_tags, {
    Region = local.aws_region
  })

  modules_root = local.parent.locals.modules_root

  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"

  # DEV setup: HTTP only
  # HTTPS / ACM will be introduced later when domain & certificate exist
  listeners_map = {
    http = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "collibra-dq"
      }
    }
  }
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "addons/collibra-dq-standalone/alb/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = local.lock_table
    encrypt        = true
  }
}

dependency "vpc" {
  config_path = "../../../network/vpc"
  mock_outputs = {
    vpc_id         = "vpc-123456"
    public_subnets = ["subnet-123456", "subnet-789012", "subnet-345678"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "apply"]
}

dependency "sg_alb" {
  config_path = "./sg-alb"
  mock_outputs = {
    security_group_id = "sg-mock-alb"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "apply"]
}

dependencies {
  paths = [
    "../../../network/vpc",
    "./sg-alb"
  ]
}

# Note: Target group attachment is handled separately in ./target-group-attachment/
terraform {
  source = "${local.modules_root}/network/alb/application"
}

inputs = {
  name     = "${local.org}-${local.env}-collibra-dq-alb"
  vpc_id  = dependency.vpc.outputs.vpc_id
  subnets = dependency.vpc.outputs.public_subnets

  internal = false  # Internet-facing ALB (dev)

  enable_deletion_protection        = false
  enable_http2                     = true
  enable_cross_zone_load_balancing  = true

  security_groups = [dependency.sg_alb.outputs.security_group_id]

  enable_logging = false  # Dev: disabled to reduce cost/noise

  # HTTP-only listener (dev)
  listeners = local.listeners_map

  target_groups = {
    collibra-dq = {
      name                 = "${local.org}-${local.env}-collibra-dq-tg"
      backend_protocol     = "HTTP"
      backend_port         = 9000
      target_type          = "instance"
      deregistration_delay = 30
      create_attachment    = false

      health_check = {
        enabled             = true
        healthy_threshold   = 2
        interval            = 30
        matcher             = "200,302"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 3
      }
    }
  }

  tags = merge(local.common_tags, {
    Component = "alb"
    Name      = "${local.org}-${local.env}-collibra-dq-alb"
  })
}