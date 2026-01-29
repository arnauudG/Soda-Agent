# env/<env>/<region>/network/vpc/terragrunt.hcl
# VPC configuration - includes env-level root.hcl (1 level, avoids nested includes)

include "env" {
  path = "../../../root.hcl"
}

locals {
  parent = read_terragrunt_config("../../../root.hcl")
  org    = local.parent.locals.org
  env    = local.parent.locals.env
  
  # Extract region from path: env/dev/eu-west-1/network/vpc
  path_parts = split("/", get_terragrunt_dir())
  region_index = length(local.path_parts) - 3  # region is 3 levels up from vpc
  aws_region   = local.path_parts[local.region_index]
  
  # Common tags from parent, with Region added
  common_tags = merge(local.parent.locals.common_tags, {
    Region = local.aws_region
  })

  prefix = "${local.org}-${local.env}-${local.aws_region}"
  
  # State bucket and lock table names
  state_bucket = "${get_aws_account_id()}-${local.org}-${local.env}-tfstate-${local.aws_region}"
  lock_table   = "${get_aws_account_id()}-${local.org}-${local.env}-tf-locks"
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "network/vpc/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = local.lock_table
    encrypt        = true
  }
}

terraform {
  source = "${local.parent.locals.modules_root}/network/vpc"
}

dependencies {
  paths = ["../../bootstrap"]
}

inputs = {
  name = "${local.prefix}-vpc"
  cidr = "10.10.0.0/16"

  azs             = ["${local.aws_region}a", "${local.aws_region}b", "${local.aws_region}c"]
  # Optimized subnet sizing: /22 = 1024 IPs per subnet (sufficient for EKS and workloads)
  public_subnets  = ["10.10.0.0/22", "10.10.4.0/22", "10.10.8.0/22"]
  private_subnets = ["10.10.12.0/22", "10.10.16.0/22", "10.10.20.0/22"]

  enable_nat_gateway   = true
  single_nat_gateway   = true  # Dev: Single NAT gateway for cost optimization
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  # VPC Flow Logs - disabled for dev to save costs (enable if needed for troubleshooting)
  enable_flow_log = false

  # ---- Nice, unique names for key resources ----
  # VPC itself
  vpc_tags = {
    Name = "${local.prefix}-vpc"
  }

  # Internet Gateway
  igw_tags = {
    Name = "${local.prefix}-igw"
  }

  # NAT Gateway(s) - single NAT for dev (cost optimization)
  nat_gateway_tags = merge(local.common_tags, {
    Name      = "${local.prefix}-natgw"
    Component = "network"
  })

  # EIP(s) for NAT Gateway(s)
  nat_eip_tags = merge(local.common_tags, {
    Name      = "${local.prefix}-eip-nat"
    Component = "network"
  })

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

  # Default Security Group - restrict to deny all by default
  manage_default_security_group = true
  default_security_group_ingress = []  # No ingress by default
  default_security_group_egress  = []  # No egress by default
  default_security_group_name    = "${local.prefix}-default-sg"
  default_security_group_tags    = {
    Name        = "${local.prefix}-default-sg"
    Description = "Default security group for ${local.prefix}-vpc - all traffic denied by default"
  }
  
  # Base tags on everything - merge common tags with component-specific tags
  tags = merge(local.common_tags, {
    Component = "network"
    Name      = "${local.prefix}-vpc"
  })
}