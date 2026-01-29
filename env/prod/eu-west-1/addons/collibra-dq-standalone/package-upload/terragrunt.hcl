# env/<env>/<region>/addons/collibra-dq-standalone/package-upload/terragrunt.hcl
# Automatically uploads Collibra DQ package from project folder to S3

# Note: We don't use include here to avoid nested includes
locals {
  parent = read_terragrunt_config("../../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  path_parts = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 4
  aws_region   = local.path_parts[local.region_index]
  
  modules_root = local.parent.locals.modules_root
  
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
  
  common_tags = merge(local.parent.locals.common_tags, {
    Region    = local.aws_region
    Component = "package-storage"
  })
  
  dq_package_filename = get_env("COLLIBRA_DQ_PACKAGE_FILENAME", "dq-2025.11-SPARK356-JDK17-package-full.tar")
  
  # Package file path (relative to project root)
  # From: env/prod/eu-west-1/addons/collibra-dq-standalone/package-upload
  # To: packages/collibra-dq/ (at project root)
  # Path: package-upload -> collibra-dq-standalone -> addons -> eu-west-1 -> prod -> env -> project root
  # Count: 1->2->3->4->5->6->7 (7 levels: package-upload is 7 levels deep)
  # So: ../../../../../../packages/collibra-dq/
  package_local_path = "${get_terragrunt_dir()}/../../../../../../packages/collibra-dq/${local.dq_package_filename}"
  
  # S3 bucket for package storage
  package_bucket_name = "${get_aws_account_id()}-${local.org}-${local.env}-packages-${local.aws_region}"
  package_s3_key      = "collibra-dq/${local.dq_package_filename}"
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "addons/collibra-dq-standalone/package-upload/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = local.lock_table
    encrypt        = true
  }
}

terraform {
  source = "${local.modules_root}/storage/s3-package"
}

inputs = {
  bucket_name                  = local.package_bucket_name
  create_bucket                = true
  s3_key                       = local.package_s3_key
  local_file_path              = local.package_local_path
  package_name                 = "collibra-dq-package"
  enable_transfer_acceleration = get_env("COLLIBRA_DQ_ENABLE_S3_ACCELERATION", "false") == "true"
  # Set to true to skip package upload if it already exists in S3 (saves time on redeployments)
  skip_upload_if_exists        = get_env("COLLIBRA_DQ_SKIP_PACKAGE_UPLOAD", "false") == "true"
  
  tags = local.common_tags
}
