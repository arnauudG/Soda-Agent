# env/env.hcl
# Environment catalog for Terragrunt.
#
# Stack-first note:
# - Live configs are under env/stack/
# - This file only defines the environment keys and their settings.
#
# Account ID safety:
# - Do NOT commit your AWS account IDs here if you don't want them in git history.
# - Use the environment variable TG_EXPECTED_ACCOUNT_ID at runtime to enable the safety check.

locals {
  valid_regions      = ["eu-west-1", "us-east-1", "eu-central-1"]

  # ==========================================================================
  # ENVIRONMENT CONFIGURATIONS
  # ==========================================================================
  environments = {
    dev = {
      # AWS Account (optional)
      #
      # Leave empty to avoid committing account IDs. To enable account safety checks:
      #   export TG_EXPECTED_ACCOUNT_ID=123456789012
      aws_account_id = ""

      # VPC Settings
      vpc = {
        cidr               = "10.10.0.0/16"
        single_nat_gateway = true   # Dev: Single NAT gateway for cost optimization
        enable_flow_log    = false  # Dev: Disabled for cost savings
      }

      # EKS Settings
      eks = {
        desired_size                   = 1
        min_size                       = 1
        max_size                       = 2
        instance_types                 = ["t3.small"]
        disk_size                      = 20
        capacity_type                  = "SPOT"
        cluster_endpoint_public_access = true
        cloudwatch_log_retention       = 7
      }

      # EC2 Ops
      ec2_ops = {
        instance_type = "t3.micro"
        volume_size   = 16
      }

      # RDS
      rds = {
        instance_class        = "db.t3.medium"
        allocated_storage     = 100
        max_allocated_storage = 200
        deletion_protection   = false
        multi_az              = false
        backup_retention      = 7
      }

      # Collibra DQ
      collibra_dq = {
        instance_type = "m5.large"
        volume_size   = 100
      }

      # ALB
      alb = {
        deletion_protection = false
      }
    }

    prod = {
      # AWS Account (optional)
      aws_account_id = ""

      # VPC Settings
      vpc = {
        cidr               = "10.20.0.0/16"  # Different CIDR for prod
        single_nat_gateway = false           # HA: NAT per AZ
        enable_flow_log    = true            # Prod: Enable for security/compliance
      }

      # EKS Settings
      eks = {
        desired_size                   = 3
        min_size                       = 2
        max_size                       = 5
        instance_types                 = ["t3.small"]
        disk_size                      = 50
        capacity_type                  = "SPOT"
        cluster_endpoint_public_access = false  # Private only in prod
        cloudwatch_log_retention       = 30
      }

      # EC2 Ops
      ec2_ops = {
        instance_type = "t3.small"
        volume_size   = 20
      }

      # RDS
      rds = {
        instance_class        = "db.t3.small"
        allocated_storage     = 100
        max_allocated_storage = 500
        deletion_protection   = true
        multi_az              = true
        backup_retention      = 14
      }

      # Collibra DQ
      collibra_dq = {
        instance_type = "m5.xlarge"
        volume_size   = 200
      }

      # ALB
      alb = {
        deletion_protection = true
      }
    }
  }

  valid_environments = sort(keys(local.environments))

  # ==========================================================================
  # DEFAULTS (shared across all environments)
  # ==========================================================================
  defaults = {
    org         = "datashift"
    project     = "DQ-Infrastructures"
    cost_center = "Engineering"
  }
}
