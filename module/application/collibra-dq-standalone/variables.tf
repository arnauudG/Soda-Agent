variable "name" {
  description = "Name of the EC2 instance"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "ami" {
  description = "AMI ID"
  type        = string
  default     = null
}

variable "ami_ssm_parameter" {
  description = "SSM parameter for AMI"
  type        = string
  default     = null
}

variable "vpc_security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

variable "root_block_device" {
  description = "Root block device configuration"
  type        = list(any)
  default     = []
}

variable "create_iam_instance_profile" {
  description = "Create IAM instance profile"
  type        = bool
  default     = true
}

variable "iam_role_name" {
  description = "IAM role name for the instance"
  type        = string
}

variable "iam_role_use_name_prefix" {
  description = "Use name prefix for IAM role"
  type        = bool
  default     = true
}

variable "iam_role_policies" {
  description = "IAM role policies"
  type        = map(string)
  default     = {}
}

variable "metadata_options" {
  description = "Instance metadata options"
  type = object({
    http_endpoint               = string
    http_tokens                 = string
    http_put_response_hop_limit = number
    instance_metadata_tags      = string
  })
  default = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
}

variable "placement_group" {
  description = "Placement group"
  type        = string
  default     = null
}

variable "tenancy" {
  description = "Instance tenancy"
  type        = string
  default     = "default"
}

variable "ebs_optimized" {
  description = "Enable EBS optimization"
  type        = bool
  default     = false
}

variable "associate_public_ip_address" {
  description = "Associate public IP address"
  type        = bool
  default     = false
}

variable "monitoring" {
  description = "Enable detailed monitoring"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Collibra DQ specific variables
variable "owl_base" {
  description = "Base directory for Collibra DQ installation (e.g., /opt/collibra-dq)"
  type        = string
  default     = "/opt/collibra-dq"
}

variable "owl_metastore_user" {
  description = "PostgreSQL username for DQ metastore"
  type        = string
  sensitive   = true
}

variable "owl_metastore_pass" {
  description = "PostgreSQL password for DQ metastore (must meet password policy requirements)"
  type        = string
  sensitive   = true
}

variable "postgresql_host" {
  description = "PostgreSQL host (RDS endpoint)"
  type        = string
}

variable "postgresql_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "postgresql_database" {
  description = "PostgreSQL database name"
  type        = string
  default     = "dqMetastore"
}

variable "spark_package" {
  description = "Spark package filename (e.g., spark-3.5.6-bin-hadoop3.tgz)"
  type        = string
  default     = "spark-3.5.6-bin-hadoop3.tgz"
}

variable "dq_admin_user_password" {
  description = "Password for DQ Web admin user (must meet password policy requirements)"
  type        = string
  sensitive   = true
}

variable "dq_package_url" {
  description = "URL to download Collibra DQ package (from Collibra Product Resource Center)"
  type        = string
  default     = ""
}

variable "dq_package_filename" {
  description = "Filename of the DQ package (e.g., dq-full-package.tar.gz)"
  type        = string
  default     = "dq-full-package.tar.gz"
}
