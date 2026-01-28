# Collibra DQ Standalone Deployment

This addon deploys Collibra DQ (Data Quality) as a standalone EC2-based installation with Spark Standalone.

## Overview

Collibra DQ Standalone provides:
- **Data Quality Engine**: Spark-based data quality processing
- **Web Interface**: Accessible via Application Load Balancer (HTTPS)
- **PostgreSQL Metastore**: RDS PostgreSQL database for metadata storage
- **Standalone Deployment**: Single EC2 instance (no Kubernetes required)

## Architecture

```
Internet
   │
   ▼
Application Load Balancer (HTTPS)
   │
   ▼
EC2 Instance (Private Subnet)
   ├── Collibra DQ Web (Port 9000)
   ├── Spark Master (Port 8080)
   └── Spark Worker (Port 8081)
   │
   ├──► RDS PostgreSQL (Metastore)
   └──► S3 (Package Storage)
```

## Prerequisites

### Infrastructure Dependencies

Deploy in this order:

1. **VPC** (`../../network/vpc`)
2. **VPC Endpoints** (`../../network/vpc-endpoints`) - Required for S3 access
3. **RDS Database** (`../../database/rds-collibra-dq/rds`) - PostgreSQL metastore
4. **Security Groups** (`./sg-collibra-dq`) - Instance security group
5. **Package Upload** (`./package-upload`) - Uploads Collibra DQ package to S3
6. **EC2 Instance** (`./`) - Collibra DQ installation
7. **ALB** (`./alb`) - Load balancer for web access
8. **Target Group Attachment** (`./alb/target-group-attachment`) - Attach instance to ALB

### Environment Variables

Set these before deployment:

```bash
# Required
export COLLIBRA_DQ_ADMIN_PASSWORD="<secure-password>"  # Must meet password policy
export COLLIBRA_DQ_LICENSE_KEY="<license-key>"
export COLLIBRA_DQ_LICENSE_NAME="collibra-partners"     # Optional, defaults to this

# Optional (defaults provided)
export COLLIBRA_DQ_OWL_BASE="/opt/collibra-dq"
export COLLIBRA_DQ_SPARK_PACKAGE="spark-3.5.6-bin-hadoop3.tgz"
export COLLIBRA_DQ_PACKAGE_FILENAME="dq-2025.11-SPARK356-JDK17-package-full.tar"
```

### Package File

Place the Collibra DQ installation package in:
```
packages/collibra-dq/<package-filename>
```

The deployment script will automatically upload it to S3 if found locally.

## Deployment

### Automated Deployment

Use the deployment script:

```bash
cd env/dev/eu-west-1/addons/collibra-dq-standalone
../../../../../scripts/deploy/deploy-collibra-dq.sh dev
```

This script:
1. Uploads package to S3 (if found locally)
2. Deploys security groups
3. Deploys EC2 instance
4. Deploys ALB
5. Attaches instance to target group

### Manual Deployment

Deploy components in order:

```bash
# 1. Security Group
cd sg-collibra-dq
terragrunt apply

# 2. Package Upload (if package exists locally)
cd ../package-upload
terragrunt apply

# 3. EC2 Instance
cd ..
terragrunt apply

# 4. ALB Security Group
cd alb/sg-alb
terragrunt apply

# 5. ALB
cd ..
terragrunt apply

# 6. Target Group Attachment
cd target-group-attachment
terragrunt apply
```

## Configuration

### Instance Configuration

**Dev Environment**:
- Instance Type: `m5.large` (2 vCPU, 8GB RAM)
- Volume Size: 100 GB
- Single NAT Gateway (cost optimization)

**Prod Environment**:
- Instance Type: `m5.xlarge` (4 vCPU, 16GB RAM) - configurable
- Volume Size: 200 GB - configurable
- Multiple NAT Gateways (HA)

### Network Configuration

- **Subnet**: Private subnet (no public IP)
- **Access**: Via ALB only (more secure)
- **Outbound**: NAT Gateway for internet, S3 Gateway Endpoint for S3

### Security Groups

**Instance Security Group** (`sg-collibra-dq`):
- Ingress:
  - Port 9000 (DQ Web) from ALB security group
  - Port 9101 (Health check) from VPC CIDR
  - Port 8080/8081 (Spark UIs) from VPC CIDR
- Egress:
  - Port 443 (HTTPS) to `0.0.0.0/0`
  - Port 80 (HTTP) to `0.0.0.0/0`
  - Port 53 (DNS) to VPC CIDR
  - Port 5432 (PostgreSQL) to VPC CIDR

**ALB Security Group** (`sg-alb`):
- Ingress:
  - Port 443 (HTTPS) from `0.0.0.0/0`
  - Port 80 (HTTP) from `0.0.0.0/0` (redirects to HTTPS)
- Egress:
  - Port 9000 (DQ Web) to instance security group

## Installation Process

The EC2 instance user-data script automatically:

1. **Network Configuration**:
   - Waits for DNS to be ready
   - Configures VPC DNS resolver
   - Disables IPv6 (VPC is IPv4-only)
   - Forces IPv4 for `dnf` (AL2023 dualstack workaround)

2. **System Updates**:
   - Updates system packages
   - Installs required tools (curl, wget, tar, unzip, etc.)

3. **Java Installation**:
   - Installs Java 17 (Amazon Corretto)
   - Configures JAVA_HOME
   - Falls back to direct RPM download if repository access fails

4. **Collibra DQ Installation**:
   - Downloads package from S3
   - Extracts package (supports .tar, .tar.gz, .zip)
   - Runs `setup.sh` with PostgreSQL configuration
   - Configures license key
   - Starts Collibra DQ services

5. **Service Management**:
   - Creates systemd service for Collibra DQ
   - Enables firewall rules for required ports
   - Configures SSM agent

## Accessing Collibra DQ

### Web Interface

After deployment, get the ALB URL:

```bash
cd env/dev/eu-west-1/addons/collibra-dq-standalone/alb
ALB_DNS=$(terragrunt output -raw alb_dns_name)
echo "Access Collibra DQ at: https://$ALB_DNS"
```

### Direct Instance Access (via SSM)

```bash
cd env/dev/eu-west-1/addons/collibra-dq-standalone
INSTANCE_ID=$(terragrunt output -raw instance_id)
aws ssm start-session --target $INSTANCE_ID --region eu-west-1
```

### Monitoring Installation

```bash
# Connect via SSM
aws ssm start-session --target $INSTANCE_ID --region eu-west-1

# View installation log
sudo tail -f /var/log/collibra-dq-install.log

# Check service status
sudo systemctl status collibra-dq.service

# Check Collibra DQ services
cd /opt/collibra-dq
./owlmanage.sh status
```

## Troubleshooting

### Installation Timeouts

**Symptom**: `dnf` commands timeout when installing packages

**Cause**: Amazon Linux 2023 dualstack default + IPv4-only VPC

**Solution**: Already handled in user-data script:
- IPv4-only configuration (`ip_resolve=4`)
- IPv6 disabled system-wide
- Kernel-livepatch repository disabled (optional, not required)

**Note**: The kernel-livepatch repository may timeout in private subnet setups. This is expected and harmless - the repository is optional and disabled automatically.

### DNS Resolution Issues

**Symptom**: Can't resolve hostnames

**Check**:
```bash
cat /etc/resolv.conf
# Should show: nameserver 10.10.0.2
```

**Fix**: User-data script configures DNS automatically

### S3 Access Issues

**Symptom**: Can't download package from S3

**Check**:
- S3 Gateway Endpoint is attached to route table
- Instance IAM role has S3 read permissions
- Package exists in S3 bucket

### Service Startup Issues

**Check logs**:
```bash
sudo journalctl -u collibra-dq.service -f
sudo tail -f /opt/collibra-dq/logs/*.log
```

**Check PostgreSQL connectivity**:
```bash
# From instance
psql -h <rds-endpoint> -U <username> -d dqMetastore
```

### Health Check Failures

**Symptom**: ALB target shows unhealthy

**Check**:
- Instance security group allows port 9000 from ALB security group
- Collibra DQ Web service is running on port 9000
- Health check path is correct (`/`)

**Verify**:
```bash
curl http://localhost:9000/
curl http://localhost:9101/health
```

## Destruction

### Automated Destruction

```bash
cd env/dev/eu-west-1/addons/collibra-dq-standalone
../../../../../scripts/destroy/destroy-collibra-dq.sh dev
```

### Manual Destruction

Destroy in reverse order:

```bash
# 1. Target Group Attachment
cd alb/target-group-attachment
terragrunt destroy

# 2. ALB
cd ..
terragrunt destroy

# 3. ALB Security Group
cd sg-alb
terragrunt destroy

# 4. EC2 Instance
cd ../..
terragrunt destroy

# 5. Package Upload (optional - keeps S3 package)
cd package-upload
terragrunt destroy

# 6. Security Group
cd ../sg-collibra-dq
terragrunt destroy
```

**Note**: RDS database is NOT destroyed by this addon (deploy separately).

## Network Requirements

### Inbound Traffic

- **Port 443 (HTTPS)**: From internet to ALB
- **Port 80 (HTTP)**: From internet to ALB (redirects to HTTPS)
- **Port 9000**: From ALB to EC2 instance
- **Port 9101**: From VPC CIDR to EC2 instance (health checks)
- **Port 8080/8081**: From VPC CIDR to EC2 instance (Spark UIs)

### Outbound Traffic

- **Port 443 (HTTPS)**: To internet (via NAT Gateway) for package downloads
- **Port 80 (HTTP)**: To internet (via NAT Gateway) for repository access
- **Port 53 (DNS)**: To VPC DNS resolver
- **Port 5432 (PostgreSQL)**: To RDS endpoint

### VPC Endpoints Required

- **S3 Gateway Endpoint**: For package storage access
- **SSM Interface Endpoints**: For Session Manager access (optional but recommended)

## Cost Considerations

### Dev Environment

- Single NAT Gateway: ~$32/month
- EC2 m5.large: ~$70/month (on-demand)
- RDS db.t3.medium: ~$60/month
- ALB: ~$16/month
- **Total**: ~$178/month

### Prod Environment

- Multiple NAT Gateways: ~$96/month (3 AZs)
- EC2 m5.xlarge: ~$140/month (on-demand)
- RDS db.r5.large: ~$200/month
- ALB: ~$16/month
- **Total**: ~$452/month

**Note**: Consider Reserved Instances for production to reduce costs.

## Security Considerations

1. **Private Subnet**: Instance has no public IP, accessible only via ALB
2. **Security Groups**: Restrictive ingress rules (ALB only)
3. **IAM Roles**: Instance role has minimal permissions (SSM, S3 read, CloudWatch)
4. **Encryption**: EBS volumes encrypted, RDS encrypted
5. **HTTPS**: ALB terminates TLS (certificate required)
6. **Password Policy**: Admin password must meet Collibra requirements

## Additional Resources

- [Collibra DQ Documentation](https://docs.collibra.com/)
- [Infrastructure Documentation](../../../../../docs/INFRASTRUCTURE.md)
- [Troubleshooting Guide](#troubleshooting)
