# env/<env>/<region>/network/vpc/terragrunt.hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  parent     = read_terragrunt_config(find_in_parent_folders("root.hcl"))
  org        = local.parent.locals.org
  env        = local.parent.locals.env
  aws_region = local.parent.locals.aws_region

  prefix = "${local.org}-${local.env}-${local.aws_region}"
}

terraform {
  source = "tfr://registry.terraform.io/terraform-aws-modules/vpc/aws?version=5.8.1"
}

dependencies {
  paths = ["../../bootstrap"]
}

inputs = {
  name = "${local.prefix}-vpc"
  cidr = "10.10.0.0/16"

  azs             = ["${local.aws_region}a", "${local.aws_region}b", "${local.aws_region}c"]
  public_subnets  = ["10.10.0.0/20", "10.10.16.0/20", "10.10.32.0/20"]
  private_subnets = ["10.10.48.0/20", "10.10.64.0/20", "10.10.80.0/20"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # ---- Nice, unique names for key resources ----
  # VPC itself
  vpc_tags = {
    Name = "${local.prefix}-vpc"
  }

  # Internet Gateway
  igw_tags = {
    Name = "${local.prefix}-igw"
  }

  # NAT Gateway(s)
  nat_gateway_tags = {
    Name = "${local.prefix}-natgw"
  }

  # EIP(s) for NAT Gateway(s)
  nat_eip_tags = {
    Name = "${local.prefix}-eip-nat"
  }

  # Public subnets + their route tables
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  public_subnet_names = [
    "${local.prefix}-public-a",
    "${local.prefix}-public-b",
    "${local.prefix}-public-c",
  ]
  public_route_table_tags = {
    Name = "${local.prefix}-rt-public"
  }

  # Private subnets + their route tables
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
  private_subnet_names = [
    "${local.prefix}-private-a",
    "${local.prefix}-private-b",
    "${local.prefix}-private-c",
  ]
  private_route_table_tags = {
    Name = "${local.prefix}-rt-private"
  }

  # Base tags on everything
  tags = {
    Terraform = "true"
    Component = "network"
    Org       = local.org
    Env       = local.env
  }
}