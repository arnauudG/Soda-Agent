# env/stack/bootstrap/terragrunt.hcl
# Bootstrap configuration - creates S3 state bucket and DynamoDB lock table
# No remote_state include since bootstrap creates the state bucket

locals {
  root       = read_terragrunt_config(find_in_parent_folders("root.hcl"))
  org        = local.root.locals.org
  env        = local.root.locals.env
  aws_region = local.root.locals.aws_region
  common_tags = local.root.locals.common_tags

  # State bucket and lock table names (same as in root.hcl)
  state_bucket = local.root.locals.state_bucket
  lock_table   = local.root.locals.lock_table
}

# Pass org/env, bucket names, and common_tags into the generated main.tf
inputs = {
  org          = local.org
  env          = local.env
  state_bucket = local.state_bucket
  lock_table   = local.lock_table
  common_tags  = local.common_tags
}

terraform {
  source = "./."
}

skip = false

# Local provider (DO NOT include remote_state here, since it doesn't exist yet)
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    terraform {
      required_version = ">= 1.6"
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = ">= 5.61.0, < 6.0.0"
        }
      }
    }

    provider "aws" {
      region = "${local.aws_region}"
    }
  HCL
}

# Minimal bootstrap to create S3 state bucket + DynamoDB lock table
generate "bootstrap" {
  path      = "main.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    variable "org" { type = string }
    variable "env" { type = string }
    variable "state_bucket" { type = string }
    variable "lock_table" { type = string }
    variable "common_tags" {
      type = map(string)
      default = {}
    }

    resource "aws_s3_bucket" "tfstate" {
      bucket        = var.state_bucket
      force_destroy = false

      tags = merge(var.common_tags, {
        Component = "bootstrap"
        Name      = var.state_bucket
      })
    }

    # Enforce bucket-owner ownership (modern default / best practice)
    resource "aws_s3_bucket_ownership_controls" "tfstate" {
      bucket = aws_s3_bucket.tfstate.id
      rule {
        object_ownership = "BucketOwnerEnforced"
      }
    }

    resource "aws_s3_bucket_versioning" "tfstate" {
      bucket = aws_s3_bucket.tfstate.id
      versioning_configuration {
        status = "Enabled"
      }
    }

    # Lifecycle policy to manage old state file versions
    resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
      bucket = aws_s3_bucket.tfstate.id

      rule {
        id     = "delete-old-versions"
        status = "Enabled"

        filter {}  # Apply to all objects

        noncurrent_version_expiration {
          noncurrent_days = 90  # Delete non-current versions after 90 days
        }
      }

      rule {
        id     = "transition-to-glacier"
        status = "Enabled"

        filter {}  # Apply to all objects

        noncurrent_version_transition {
          noncurrent_days = 30
          storage_class   = "GLACIER"
        }
      }
    }

    resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
      bucket = aws_s3_bucket.tfstate.id
      rule {
        apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
      }
    }

    resource "aws_s3_bucket_public_access_block" "tfstate" {
      bucket                  = aws_s3_bucket.tfstate.id
      block_public_acls       = true
      block_public_policy     = true
      ignore_public_acls      = true
      restrict_public_buckets = true
    }

    resource "aws_s3_bucket_policy" "tfstate_tls_only" {
      bucket = aws_s3_bucket.tfstate.id
      policy = jsonencode({
        Version = "2012-10-17",
        Statement = [{
          Sid       = "DenyInsecureTransport",
          Effect    = "Deny",
          Principal = "*",
          Action    = "s3:*",
          Resource  = [aws_s3_bucket.tfstate.arn, "$${aws_s3_bucket.tfstate.arn}/*"],
          Condition = { Bool = { "aws:SecureTransport" = "false" } }
        }]
      })
    }

    resource "aws_dynamodb_table" "locks" {
      name         = var.lock_table
      billing_mode = "PAY_PER_REQUEST"
      hash_key     = "LockID"

      attribute {
        name = "LockID"
        type = "S"
      }

      # Point-in-time recovery for disaster recovery
      point_in_time_recovery {
        enabled = true
      }

      # Server-side encryption
      server_side_encryption {
        enabled = true
      }

      tags = merge(var.common_tags, {
        Component = "bootstrap"
        Name      = var.lock_table
      })
    }

    output "state_bucket" { value = aws_s3_bucket.tfstate.bucket }
    output "lock_table"   { value = aws_dynamodb_table.locks.name }
  HCL
}
