# env/<env>/<region>/bootstrap/terragrunt.hcl
# Standalone bootstrap (no remote_state include!)
# Reads org/env/region and bucket names from the parent root.hcl

locals {
  parent     = read_terragrunt_config(find_in_parent_folders("root.hcl"))
  org        = local.parent.locals.org
  env        = local.parent.locals.env
  aws_region = local.parent.locals.aws_region
  
  # Use the same bucket and table names as defined in the parent root.hcl
  state_bucket = local.parent.locals.state_bucket
  lock_table   = local.parent.locals.lock_table
}

# Pass org/env and bucket names into the generated main.tf
inputs = {
  org          = local.org
  env          = local.env
  state_bucket = local.state_bucket
  lock_table   = local.lock_table
}

terraform {
  source = "./."
}

skip = true

# Local provider (DO NOT include repo root here, since remote_state doesn't exist yet)
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    terraform {
      required_version = ">= 1.6"
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 5.60"
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

    resource "aws_s3_bucket" "tfstate" {
      bucket        = var.state_bucket
      force_destroy = false
      tags = {
        Terraform = "true"
        Component = "bootstrap"
        Org       = var.org
        Env       = var.env
      }
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
      versioning_configuration { status = "Enabled" }
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

      tags = {
        Terraform = "true"
        Component = "bootstrap"
        Org       = var.org
        Env       = var.env
      }
    }

    output "state_bucket" { value = aws_s3_bucket.tfstate.bucket }
    output "lock_table"   { value = aws_dynamodb_table.locks.name }
  HCL
}