# env/<env>/<region>/ops/ec2-ops/terragrunt.hcl
include "root" { path = find_in_parent_folders("root.hcl") }

locals {
  parent       = read_terragrunt_config(find_in_parent_folders("root.hcl"))
  org          = local.parent.locals.org
  env          = local.parent.locals.env
  aws_region   = local.parent.locals.aws_region
  modules_root = local.parent.locals.modules_root
}

generate "versions_override" {
  path      = "versions_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-HCL
    terraform {
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = ">= 5.0, < 6.0"
        }
      }
    }
  HCL
}

dependency "vpc" {
  config_path = "../../network/vpc"
  mock_outputs = {
    vpc_id         = "vpc-123456"
    public_subnets = ["subnet-x", "subnet-y", "subnet-z"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependency "sg_ops" {
  config_path                             = "../sg-ops"
  mock_outputs                            = { security_group_id = "sg-123456" }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

dependencies {
  paths = [
    "../../network/vpc",
    "../sg-ops"
  ]
}

terraform {
  source = "tfr://registry.terraform.io/terraform-aws-modules/ec2-instance/aws?version=5.7.0"
}

inputs = {
  name              = "${local.org}-${local.env}-ops"
  vpc_id            = dependency.vpc.outputs.vpc_id
  ami_ssm_parameter = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  instance_type     = "t3.micro"

  subnet_id                   = dependency.vpc.outputs.public_subnets[0]
  associate_public_ip_address = true

  create_iam_instance_profile          = true
  iam_role_use_name_prefix             = false
  iam_instance_profile_use_name_prefix = false
  iam_role_name                        = "${local.org}-${local.env}-ops-role"
  iam_instance_profile_name            = "${local.org}-${local.env}-ops-instance-profile"

  # <-- Added EKS Cluster policy back in here
  iam_role_policies = {
    ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    eks = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  }

  create_security_group  = false
  vpc_security_group_ids = [dependency.sg_ops.outputs.security_group_id]

  enable_monitoring = true

  root_block_device = [{
    volume_size = 16
    volume_type = "gp3"
    encrypted   = true
  }]

  metadata_options = {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data_replace_on_change = true
  user_data = templatefile(
    "${get_terragrunt_dir()}/user-data/install_ops_box.sh.tmpl",
    { region = local.aws_region }
  )

  tags = {
    Terraform = "true"
    Component = "ops-ec2"
    Org       = local.org
    Env       = local.env
    Project   = "Soda-Agent"
    Name      = "${local.org}-${local.env}-ops"
  }
}