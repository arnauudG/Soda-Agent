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

# Use the EC2 module
module "ec2" {
  source = "../../compute/ec2/ops"

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

  user_data_base64            = base64encode(templatefile("${path.module}/user-data/install_collibra_dq.sh.tmpl", {
    region                    = var.region
    owl_base                  = var.owl_base
    owl_metastore_user        = var.owl_metastore_user
    owl_metastore_pass        = var.owl_metastore_pass
    postgresql_host           = var.postgresql_host
    postgresql_port           = var.postgresql_port
    postgresql_database       = var.postgresql_database
    spark_package              = var.spark_package
    dq_admin_user_password    = var.dq_admin_user_password
    dq_package_url            = var.dq_package_url
    dq_package_filename        = var.dq_package_filename
  }))
  user_data_replace_on_change = true

  associate_public_ip_address = var.associate_public_ip_address
  monitoring                  = var.monitoring

  tags = var.tags
}
