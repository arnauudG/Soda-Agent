# env/stack/collibra-dq/addons/collibra-dq-standalone/package-upload/terragrunt.hcl
# Uploads Collibra DQ package from project folder to S3

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "common" {
  path = find_in_parent_folders("common.hcl")
}

locals {
  org         = include.root.locals.org
  env         = include.root.locals.env
  aws_region  = include.root.locals.aws_region
  common_tags = include.root.locals.common_tags

  dq_package_filename = get_env("COLLIBRA_DQ_PACKAGE_FILENAME", "dq-2025.11-SPARK356-JDK17-package-full.tar")

  # Package file path (absolute path to ensure Terraform can find it from .terragrunt-cache)
  # Calculate absolute path from project root
  package_local_path = "${get_repo_root()}/packages/collibra-dq/${local.dq_package_filename}"

  # S3 bucket for package storage
  package_bucket_name = "${get_aws_account_id()}-${local.org}-${local.env}-packages-${local.aws_region}"
  package_s3_key      = "collibra-dq/${local.dq_package_filename}"

  # If the bucket already exists (e.g., legacy/residual infrastructure), don't try to create/manage it.
  # This avoids accidental deletes on destroy and prevents CreateBucket 409 errors.
  # In CI (or without AWS creds), this check can fail; default to "false" in that case.
  package_bucket_exists = try(
    run_cmd(
      "bash",
      "-lc",
      "aws s3api head-bucket --bucket '${local.package_bucket_name}' >/dev/null 2>&1 && echo true || echo false"
    ),
    "false"
  ) == "true"
}

terraform {
  source = "${include.root.locals.modules_root}/storage/s3-package"
}

inputs = {
  bucket_name                  = local.package_bucket_name
  create_bucket                = local.package_bucket_exists ? false : true
  s3_key                       = local.package_s3_key
  local_file_path              = local.package_local_path
  package_name                 = "collibra-dq-package"
  enable_transfer_acceleration = get_env("COLLIBRA_DQ_ENABLE_S3_ACCELERATION", "false") == "true"
  skip_upload_if_exists        = get_env("COLLIBRA_DQ_SKIP_PACKAGE_UPLOAD", "false") == "true"

  tags = local.common_tags
}
