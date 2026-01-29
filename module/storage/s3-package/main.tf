# S3 Package Storage Module
# Automatically uploads a local package file to S3 for use by EC2 instances

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# S3 bucket for storing packages (create if it doesn't exist)
resource "aws_s3_bucket" "package_storage" {
  count  = var.create_bucket ? 1 : 0
  bucket = var.bucket_name

  tags = merge(var.tags, {
    Name      = var.bucket_name
    Component = "package-storage"
  })
}

# Use existing bucket if provided, otherwise use the created one
locals {
  bucket_id = var.create_bucket ? aws_s3_bucket.package_storage[0].id : var.bucket_name
}

# Bucket versioning
resource "aws_s3_bucket_versioning" "package_storage" {
  count  = var.create_bucket ? 1 : 0
  bucket = local.bucket_id

  versioning_configuration {
    status = "Enabled"
  }
}

# Bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "package_storage" {
  count  = var.create_bucket ? 1 : 0
  bucket = local.bucket_id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "package_storage" {
  count  = var.create_bucket ? 1 : 0
  bucket = local.bucket_id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable S3 Transfer Acceleration for faster uploads (optional)
resource "aws_s3_bucket_accelerate_configuration" "package_storage" {
  count  = var.create_bucket && var.enable_transfer_acceleration ? 1 : 0
  bucket = local.bucket_id

  status = "Enabled"
}

# Upload the package file if local file exists
# Note: When skip_upload_if_exists is true, the resource is still created but source/etag changes are ignored
# This prevents Terraform from destroying the resource when skip_upload_if_exists is enabled
resource "aws_s3_object" "package" {
  count = var.local_file_path != "" && fileexists(var.local_file_path) ? 1 : 0

  bucket = local.bucket_id
  key    = var.s3_key
  source = var.local_file_path
  etag   = fileexists(var.local_file_path) ? filemd5(var.local_file_path) : null
  # Auto-detect content type based on file extension
  content_type = try(
    endswith(var.local_file_path, ".tar.gz") || endswith(var.local_file_path, ".tgz") ? "application/gzip" : (
      endswith(var.local_file_path, ".tar") ? "application/x-tar" : (
        endswith(var.local_file_path, ".zip") ? "application/zip" : "application/octet-stream"
      )
    ),
    "application/octet-stream"
  )

  tags = merge(var.tags, {
    Name      = var.package_name
    Component = "package-storage"
  })

  # Lifecycle: Ignore changes to prevent unnecessary re-uploads
  # Note: Terraform requires lifecycle.ignore_changes to be a static list (no conditionals allowed)
  # When skip_upload_if_exists is true, we always ignore source/etag to prevent re-uploads
  # To force a re-upload: temporarily set skip_upload_if_exists=false or use terraform taint
  lifecycle {
    ignore_changes = [
      tags,
      content_type,
      source,
      etag
    ]
  }

  depends_on = [
    aws_s3_bucket.package_storage,
    aws_s3_bucket_versioning.package_storage,
    aws_s3_bucket_server_side_encryption_configuration.package_storage,
    aws_s3_bucket_public_access_block.package_storage,
    aws_s3_bucket_accelerate_configuration.package_storage
  ]
}
