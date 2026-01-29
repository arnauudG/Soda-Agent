# env/<env>/<region>/addons/collibra-dq-standalone/alb/terragrunt.hcl
# Application Load Balancer for Collibra DQ Web Interface

# Note: We don't use include here to avoid nested includes
# Instead, we read the env-level root.hcl directly
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
  # For prod: HTTPS is strongly recommended - set COLLIBRA_DQ_ACM_CERTIFICATE_ARN
  acm_certificate_arn = get_env("COLLIBRA_DQ_ACM_CERTIFICATE_ARN", "")
  
  # Domain name for the certificate (optional)
  domain_name = get_env("COLLIBRA_DQ_DOMAIN_NAME", "")
  
  # Build listeners map
  # For prod: HTTPS is recommended. If certificate is provided, enable HTTPS and redirect HTTP.
  # If no certificate, only HTTP listener (not recommended for production)
listeners_map = local.acm_certificate_arn != "" ? {
  https = {
    port            = 443
    protocol        = "HTTPS"
    certificate_arn = local.acm_certificate_arn
    ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
    forward = {
      target_group_key = "collibra-dq"
    }
  }
  http = {
    port     = 80
    protocol = "HTTP"
    redirect = {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
    forward = null
  }
} : {
  http = {
    port     = 80
    protocol = "HTTP"
    redirect = null
    forward = {
      target_group_key = "collibra-dq"
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
  name = "${local.org}-${local.env}-collibra-dq-alb"
  vpc_id = dependency.vpc.outputs.vpc_id
  subnets = dependency.vpc.outputs.public_subnets
  internal = false  # Internet-facing ALB
  
  enable_deletion_protection = true  # Prod: enable deletion protection
  enable_http2 = true
  enable_cross_zone_load_balancing = true
  
  security_groups = [dependency.sg_alb.outputs.security_group_id]
  
  enable_logging = true  # Prod: enable access logs for security and monitoring
  
  # Listeners configuration
  # If ACM certificate is provided, enable HTTPS listener and redirect HTTP to HTTPS
  # If no certificate, only HTTP listener (not recommended for production)
  listeners = local.listeners_map
  
  # Target group for Collibra DQ instance
  target_groups = {
    collibra-dq = {
      name                 = "${local.org}-${local.env}-collibra-dq-tg"
      backend_protocol     = "HTTP"
      backend_port         = 9000
      target_type          = "instance"
      deregistration_delay = 30
      create_attachment    = false  # Disable module-managed attachments (attach separately)
      health_check = {
        enabled             = true
        healthy_threshold   = 2
        interval            = 30
        matcher             = "200,302"  # Accept both 200 (OK) and 302 (redirect) as healthy
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 3
      }
      # Targets attached via target-group-attachment module (separate terragrunt config)
    }
  }
  
  tags = merge(local.common_tags, {
    Component = "alb"
    Name      = "${local.org}-${local.env}-collibra-dq-alb"
  })
}
