# Application Load Balancer Module
# Wraps terraform-aws-modules/alb/aws and provides standardized outputs

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "9.0.0"

  name = var.name

  load_balancer_type = "application"
  internal           = var.internal
  vpc_id             = var.vpc_id
  subnets            = var.subnets

  enable_deletion_protection = var.enable_deletion_protection
  enable_http2               = var.enable_http2
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  # Security groups
  security_groups = var.security_groups

  # Access logs
  enable_logging = var.enable_logging
  log_bucket_name = var.log_bucket_name

  # Listeners
  listeners = var.listeners

  # Target groups
  target_groups = var.target_groups

  tags = var.tags
}
