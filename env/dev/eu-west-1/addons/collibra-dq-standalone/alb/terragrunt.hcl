# env/<env>/<region>/addons/collibra-dq-standalone/alb/terragrunt.hcl
# Application Load Balancer for Collibra DQ Web Interface

include "env" {
  path = "../../../../root.hcl"
}

locals {
  parent = read_terragrunt_config("../../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  path_parts = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 4
  aws_region   = local.path_parts[local.region_index]
  
  common_tags = merge(local.parent.locals.common_tags, {
    Region = local.aws_region
  })
  
  modules_root = local.parent.locals.modules_root
  
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
  
  # ACM certificate ARN (can be set via environment variable or created separately)
  # For dev: can use self-signed or request a certificate via ACM
  acm_certificate_arn = get_env("COLLIBRA_DQ_ACM_CERTIFICATE_ARN", "")
  
  # Domain name for the certificate (optional)
  domain_name = get_env("COLLIBRA_DQ_DOMAIN_NAME", "")
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

dependency "vpc" {
  config_path = "../../../../network/vpc"
  mock_outputs = {
    vpc_id         = "vpc-123456"
    public_subnets = ["subnet-123456", "subnet-789012", "subnet-345678"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependency "sg_alb" {
  config_path = "./sg-alb"
  mock_outputs = {
    security_group_id = "sg-mock-alb"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}


dependencies {
  paths = [
    "../../../../network/vpc",
    "./sg-alb"
  ]
}

# Note: Target group attachment is handled separately in ./target-group-attachment/

terraform {
  source = "${local.modules_root}/network/alb/application"
}

# Generate outputs file
generate "outputs" {
  path      = "outputs.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    output "load_balancer_dns_name" {
      description = "DNS name of the ALB - use this to access Collibra DQ Web Interface via HTTPS"
      value       = module.alb.load_balancer_dns_name
    }

    output "load_balancer_zone_id" {
      description = "Zone ID of the ALB (for Route53 alias records)"
      value       = module.alb.load_balancer_zone_id
    }

    output "load_balancer_arn" {
      description = "ARN of the ALB"
      value       = module.alb.load_balancer_arn
    }

    output "target_group_arn" {
      description = "ARN of the target group"
      value       = module.alb.target_group_arns["collibra-dq"]
    }

    output "dq_web_url" {
      description = "Full URL to access Collibra DQ Web Interface (HTTPS if certificate provided, HTTP otherwise)"
      value       = "${local.acm_certificate_arn != "" ? "https" : "http"}://\${module.alb.load_balancer_dns_name}"
    }
  HCL
}

inputs = {
  name = "${local.org}-${local.env}-collibra-dq-alb"
  vpc_id = dependency.vpc.outputs.vpc_id
  subnets = dependency.vpc.outputs.public_subnets
  internal = false  # Internet-facing ALB
  
  enable_deletion_protection = false  # Dev: allow deletion
  enable_http2 = true
  enable_cross_zone_load_balancing = true
  
  security_groups = [dependency.sg_alb.outputs.security_group_id]
  
  enable_logging = false  # Dev: disable to save costs
  
  # Listeners configuration
  # If ACM certificate is provided, enable HTTPS listener and redirect HTTP to HTTPS
  # If no certificate, only HTTP listener (for dev/testing)
  listeners = local.acm_certificate_arn != "" ? {
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = local.acm_certificate_arn
      ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      default_action = {
        type             = "forward"
        target_group_key = "collibra-dq"
      }
    }
    http = {
      port     = 80
      protocol = "HTTP"
      default_action = {
        type = "redirect"
        redirect = {
          port        = "443"
          protocol    = "HTTPS"
          status_code = "HTTP_301"
        }
      }
    }
  } : {
    http = {
      port     = 80
      protocol = "HTTP"
      default_action = {
        type             = "forward"
        target_group_key = "collibra-dq"
      }
    }
  }
  
  # Target group for Collibra DQ instance
  target_groups = {
    collibra-dq = {
      name                 = "${local.org}-${local.env}-collibra-dq-tg"
      backend_protocol     = "HTTP"
      backend_port         = 9000
      target_type          = "instance"
      deregistration_delay = 30
      health_check = {
        enabled             = true
        healthy_threshold   = 2
        interval            = 30
        matcher             = "200"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 3
      }
      # Targets will be attached via target-group-attachment module
      targets = []
    }
  }
  
  tags = merge(local.common_tags, {
    Component = "alb"
    Name      = "${local.org}-${local.env}-collibra-dq-alb"
  })
}
