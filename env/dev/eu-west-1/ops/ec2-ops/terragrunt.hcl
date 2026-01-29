# env/<env>/<region>/ops/ec2-ops/terragrunt.hcl
# EC2 Ops configuration - includes env-level root.hcl (1 level, avoids nested includes)

include "env" {
  path = "../../../root.hcl"
}

locals {
  parent = read_terragrunt_config("../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  # Extract region from path: env/dev/eu-west-1/ops/ec2-ops
  path_parts = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 3  # region is 3 levels up from ec2-ops
  aws_region   = local.path_parts[local.region_index]
  
  # Common tags from parent, with Region added
  common_tags = merge(local.parent.locals.common_tags, {
    Region = local.aws_region
  })
  
  modules_root = local.parent.locals.modules_root

  # Environment-specific instance configuration
  instance_config = {
    instance_type = "t3.micro"  # Dev: smaller instance
    volume_size   = 16
  }
  
  # State bucket and lock table names
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "ops/ec2-ops/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = local.lock_table
    encrypt        = true
  }
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
  source = "${local.parent.locals.modules_root}/compute/ec2/ops"
}

inputs = {
  name = "${local.org}-${local.env}-ops"
  # Get VPC ID from dependency output (not hardcoded)
  vpc_id = dependency.vpc.outputs.vpc_id
  # Note: AMI SSM parameter is intentionally "hardcoded" - it's a standard AWS parameter for latest AL2023 AMI
  ami_ssm_parameter = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  instance_type     = local.instance_config.instance_type

  # Get subnet ID from dependency output (not hardcoded) - use first public subnet
  subnet_id                   = dependency.vpc.outputs.public_subnets[0]
  associate_public_ip_address = true

  # Instance placement configuration
  placement_group = null  # No placement group needed for single instance
  tenancy         = "default"  # Shared tenancy for cost optimization

  create_iam_instance_profile = true
  iam_role_use_name_prefix    = false
  iam_role_name               = "${local.org}-${local.env}-ops-role"

  # IAM policies for ops instance
  # Note: These are AWS managed policy ARNs - intentionally "hardcoded" as they are standard AWS policies
  iam_role_policies = {
    ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    eks = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    # ECR read access for pulling container images
    ecr = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    # CloudWatch Logs for better observability
    cloudwatch_logs = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  }

  create_security_group = false
  # Get security group ID from dependency output (not hardcoded)
  vpc_security_group_ids = [dependency.sg_ops.outputs.security_group_id]

  monitoring = true

  # Additional instance configuration
  ebs_optimized = false  # Not needed for t3.micro (not supported anyway)
  
  # Hibernation (optional - enables stop/start with state preservation)
  # hibernation = false  # Disabled by default, enable if you need state preservation on stop

  root_block_device = [{
    volume_size           = local.instance_config.volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
    # Dev: Reduced IOPS/throughput for cost savings (GP3 minimums)
    iops                  = 3000  # GP3 baseline IOPS (minimum)
    throughput            = 125   # GP3 baseline throughput (minimum, MB/s)
  }]

  # Note: Credit specification is not directly supported by the module
  # For t3 instances, CPU credits are managed automatically by AWS
  # To set unlimited credits, use AWS Console or CLI after instance creation

  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  user_data_replace_on_change = true
  user_data = templatefile(
    "${get_terragrunt_dir()}/user-data/install_ops_box.sh.tmpl",
    { region = local.aws_region }
  )

  tags = merge(local.common_tags, {
    Component = "ops-ec2"
    Name      = "${local.org}-${local.env}-ops"
  })
}