# Collibra DQ Standalone Module

Creates an EC2 instance running Collibra Data Quality as a standalone installation.

## Description

This module deploys Collibra DQ (Data Quality) on a single EC2 instance with:

- Amazon Linux 2023 EC2 instance
- Automatic Collibra DQ installation via user data script
- Apache Spark for data processing
- PostgreSQL connectivity to RDS metastore
- IAM role with SSM and S3 access
- IMDSv2 enforced for security

## Usage

```hcl
module "collibra_dq" {
  source = "../../../module/application/collibra-dq-standalone"

  name          = "datashift-dev-collibra-dq"
  region        = "eu-west-1"
  instance_type = "m5.xlarge"

  vpc_security_group_ids = [dependency.sg_collibra_dq.outputs.security_group_id]
  subnet_id              = dependency.vpc.outputs.private_subnets[0]

  iam_role_name = "datashift-dev-collibra-dq-role"

  # PostgreSQL (RDS) connection
  postgresql_host     = dependency.rds.outputs.db_instance_address
  postgresql_port     = 5432
  postgresql_database = "collibra_dq"
  owl_metastore_user  = dependency.rds.outputs.db_instance_username
  owl_metastore_pass  = dependency.rds.outputs.db_instance_password

  # Collibra DQ configuration
  dq_admin_user_password = var.COLLIBRA_DQ_ADMIN_PASSWORD
  license_key           = var.COLLIBRA_DQ_LICENSE_KEY

  root_block_device = {
    volume_size = 100
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Environment = "dev"
    Project     = "Collibra-DQ"
  }
}
```

## Required Inputs

| Name | Description | Type |
|------|-------------|------|
| `name` | Name of the EC2 instance | `string` |
| `region` | AWS region | `string` |
| `instance_type` | EC2 instance type | `string` |
| `vpc_security_group_ids` | List of security group IDs | `list(string)` |
| `subnet_id` | Subnet ID for the instance | `string` |
| `iam_role_name` | IAM role name for the instance | `string` |
| `postgresql_host` | PostgreSQL host (RDS endpoint) | `string` |
| `owl_metastore_user` | PostgreSQL username for DQ metastore | `string` |
| `owl_metastore_pass` | PostgreSQL password for DQ metastore | `string` |
| `dq_admin_user_password` | Password for DQ Web admin user | `string` |
| `license_key` | Collibra DQ license key | `string` |

## Optional Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `ami` | AMI ID (uses SSM parameter if not set) | `string` | `null` |
| `ami_ssm_parameter` | SSM parameter for AMI | `string` | `null` |
| `owl_base` | Base directory for Collibra DQ installation | `string` | `"/opt/collibra-dq"` |
| `postgresql_port` | PostgreSQL port | `number` | `5432` |
| `postgresql_database` | PostgreSQL database name | `string` | `"dqMetastore"` |
| `spark_package` | Spark package filename | `string` | `"spark-3.5.6-bin-hadoop3.tgz"` |
| `dq_package_url` | URL to download Collibra DQ package | `string` | `""` |
| `dq_package_filename` | Filename of the DQ package | `string` | `"dq-full-package.tar.gz"` |
| `license_name` | Collibra DQ license name | `string` | `""` |
| `root_block_device` | Root block device configuration | `object` | `null` |
| `ebs_optimized` | Enable EBS optimization | `bool` | `false` |
| `monitoring` | Enable detailed monitoring | `bool` | `true` |
| `associate_public_ip_address` | Associate public IP address | `bool` | `false` |
| `metadata_options` | Instance metadata options | `object` | IMDSv2 enforced |
| `tags` | Tags to apply to resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `instance_id` | EC2 instance ID |
| `instance_arn` | EC2 instance ARN |
| `instance_public_ip` | Public IP address (if applicable) |
| `instance_private_ip` | Private IP address |
| `iam_role_name` | IAM role name |
| `iam_role_arn` | IAM role ARN |
| `owl_base` | Collibra DQ installation directory |
| `dq_web_url` | URL to access DQ Web |

## Security Considerations

- Instance is deployed in a private subnet (no public IP)
- Access via Application Load Balancer (HTTPS recommended)
- IMDSv2 is enforced (http_tokens = "required")
- Storage is encrypted at rest
- SSM Session Manager for administrative access (no SSH)
- Secrets (passwords, license key) are marked sensitive

## Cost Implications

| Resource | Dev (m5.xlarge) | Prod (m5.2xlarge) |
|----------|-----------------|-------------------|
| EC2 Instance (On-Demand) | ~$140/month | ~$280/month |
| EBS Volume (100GB gp3) | ~$8/month | ~$8/month |
| Data Transfer | Variable | Variable |

**Instance Type Recommendations:**
- **Minimum**: m5.xlarge (4 vCPU, 16GB RAM)
- **Recommended**: m5.2xlarge (8 vCPU, 32GB RAM) for production workloads
- **High Performance**: m5.4xlarge or r5.2xlarge for large datasets

## Dependencies

- `network/vpc` - VPC and private subnets
- `security/security-group/collibra-dq` - Security group for the instance
- `database/rds/postgresql` - PostgreSQL database for metastore
- `storage/s3-package` - S3 bucket for DQ package upload

## Dependent Modules

- `network/alb/application` - Application Load Balancer for HTTPS access
- `network/alb/target-group-attachment` - Registers instance with ALB

## Installation Process

The module uses a user data script that:

1. Updates system packages
2. Installs Java 11 and required dependencies
3. Downloads and installs Apache Spark
4. Downloads Collibra DQ package from S3
5. Configures PostgreSQL connection
6. Activates Collibra DQ license
7. Starts DQ Web and Agent services

**Installation logs**: `/var/log/cloud-init-output.log`

## Accessing Collibra DQ

After deployment:

1. **Via ALB (Recommended)**: Access through the Application Load Balancer URL
2. **Via SSM**: Use AWS Systems Manager Session Manager
   ```bash
   aws ssm start-session --target <instance-id>
   ```

3. **Service URLs** (on instance):
   - DQ Web: http://localhost:9000
   - DQ Agent Health: http://localhost:9101
   - Spark Master UI: http://localhost:8080
