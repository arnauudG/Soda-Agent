# Collibra DQ Spark Standalone Module
# Deploys Collibra DQ on EC2 instance with Spark Standalone

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Full install script in S3 (avoids EC2 user data 16KB limit); instance fetches and runs it at boot
locals {
  install_script_vars = {
    region                 = var.region
    owl_base               = var.owl_base
    owl_metastore_user     = var.owl_metastore_user
    owl_metastore_pass     = var.owl_metastore_pass
    postgresql_host        = var.postgresql_host
    postgresql_port        = var.postgresql_port
    postgresql_database    = var.postgresql_database
    spark_package          = var.spark_package
    dq_admin_user_password = var.dq_admin_user_password
    dq_package_url         = var.dq_package_url
    dq_package_filename    = var.dq_package_filename
    license_key            = var.license_key
    license_name           = var.license_name
  }
}

resource "aws_s3_object" "install_script" {
  bucket  = var.install_script_bucket_name
  key     = var.install_script_s3_key
  content = templatefile("${path.module}/user-data/install_collibra_dq.sh.tmpl", local.install_script_vars)
  etag    = md5(templatefile("${path.module}/user-data/install_collibra_dq.sh.tmpl", local.install_script_vars))
}

# Bootstrap user data (under 16KB): download script from S3 and run
module "ec2" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 6.0"

  name = var.name

  instance_type          = var.instance_type
  ami                    = var.ami
  ami_ssm_parameter      = var.ami_ssm_parameter
  vpc_security_group_ids = var.vpc_security_group_ids
  subnet_id              = var.subnet_id

  root_block_device = var.root_block_device

  create_iam_instance_profile = var.create_iam_instance_profile
  iam_role_name               = var.iam_role_name
  iam_role_use_name_prefix    = var.iam_role_use_name_prefix
  iam_role_policies           = var.iam_role_policies

  metadata_options = var.metadata_options

  placement_group = var.placement_group
  tenancy         = var.tenancy
  ebs_optimized   = var.ebs_optimized

  user_data_base64 = base64encode(templatefile("${path.module}/user-data/bootstrap_install.sh.tmpl", {
    region = var.region
    bucket = var.install_script_bucket_name
    key    = var.install_script_s3_key
  }))
  user_data_replace_on_change = true

  depends_on = [aws_s3_object.install_script]

  associate_public_ip_address = var.associate_public_ip_address
  monitoring                  = var.monitoring

  tags = var.tags
}
