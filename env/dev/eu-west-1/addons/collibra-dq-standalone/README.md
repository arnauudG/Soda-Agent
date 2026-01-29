# Collibra DQ Standalone Deployment

This addon deploys Collibra DQ (Data Quality) as a standalone EC2-based installation with Spark Standalone.

## Overview

Collibra DQ Standalone provides:
- **Data Quality Engine**: Spark-based data quality processing
- **Web Interface**: Accessible via Application Load Balancer (HTTP by default, HTTPS when certificate provided)
- **PostgreSQL Metastore**: RDS PostgreSQL database for metadata storage
- **Standalone Deployment**: Single EC2 instance (no Kubernetes required)
- **PostgreSQL Client**: Automatically installed for RDS connectivity testing
- **Health Monitoring**: Comprehensive health checks and testing scripts

## Architecture

```
Internet
   │
   ▼
Application Load Balancer (HTTP/HTTPS)
   │  - HTTP (port 80) - default for dev
   │  - HTTPS (port 443) - when ACM certificate provided
   │
   ▼
EC2 Instance (Private Subnet)
   ├── Collibra DQ Web (Port 9000)
   ├── Spark Master (Port 8080)
   ├── Spark Worker (Port 8081)
   ├── PostgreSQL Client (psql) - for RDS testing
   └── Helper Scripts (/usr/local/bin/test-rds-connection.sh)
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

# Package Upload Optimization (optional - uploads are automatically optimized)
# The variable is kept for workflow compatibility but uploads are always optimized
export COLLIBRA_DQ_SKIP_PACKAGE_UPLOAD="true"
```

### Package File

Place the Collibra DQ installation package in:
```
packages/collibra-dq/<package-filename>
```

The deployment script will automatically upload it to S3 if found locally. Uploads are automatically optimized to prevent re-uploads of unchanged files.

**Package Upload Optimization:**
Package uploads are automatically optimized - Terraform ignores file content changes (`source` and `etag`) to prevent unnecessary re-uploads. This saves 20+ minutes on redeployments.

**To force a re-upload** (e.g., when updating the package file):
- Temporarily set `COLLIBRA_DQ_SKIP_PACKAGE_UPLOAD=false` and run apply, or
- Use `terraform taint` on the S3 object resource in the `package-upload` module

## Deployment

### Automated Deployment (Recommended)

Use the unified deployment script from the project root:

```bash
# From project root
./deploy-stack.sh collibra-dq dev
```

This script:
1. Checks/creates bootstrap if needed
2. Deploys VPC and VPC Endpoints (if not exists)
3. Deploys RDS Security Group
4. Deploys RDS PostgreSQL Database
5. Deploys Collibra DQ Security Group
6. Uploads package to S3 (if found locally, optimized to skip if unchanged)
7. Deploys EC2 Instance
8. Deploys ALB Security Group
9. Deploys Application Load Balancer
10. Attaches instance to target group

**Package Upload Optimization:**
Package uploads are automatically optimized to prevent unnecessary re-uploads (saves 20+ minutes). To force a re-upload when updating the package file, temporarily set `COLLIBRA_DQ_SKIP_PACKAGE_UPLOAD=false` or use `terraform taint`.

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
  - Port 443 (HTTPS) from `0.0.0.0/0` (when HTTPS enabled)
  - Port 80 (HTTP) from `0.0.0.0/0` (redirects to HTTPS when certificate provided)
- Egress:
  - Port 9000 (DQ Web) to instance security group

**Health Check Configuration**:
- Path: `/`
- Protocol: HTTP
- Port: 9000 (traffic-port)
- Matcher: `200,302` (accepts both OK and redirect responses)
- Interval: 30 seconds
- Timeout: 5 seconds
- Healthy threshold: 2 consecutive successes
- Unhealthy threshold: 3 consecutive failures

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

4. **PostgreSQL Client Installation**:
   - Installs PostgreSQL client (`psql`) for RDS connectivity testing
   - Creates helper script `/usr/local/bin/test-rds-connection.sh`
   - Tests RDS connectivity after installation

5. **Collibra DQ Installation**:
   - Downloads package from S3
   - Extracts package (supports .tar, .tar.gz, .zip)
   - Detects package structure (handles `owl/` subdirectory automatically)
   - Runs `setup.sh` with PostgreSQL configuration
   - Configures license key (with proper escaping for special characters)
   - Creates required directories (`config`, `bin`, `pids`, `log`)
   - Starts Collibra DQ services

6. **Service Management**:
   - Creates systemd service for Collibra DQ
   - Enables firewall rules for required ports
   - Configures SSM agent
   - Tests RDS connectivity automatically

## Accessing Collibra DQ

### Web Interface

After deployment, get the ALB URL:

```bash
cd env/dev/eu-west-1/addons/collibra-dq-standalone/alb
ALB_DNS=$(terragrunt output -raw load_balancer_dns_name)
echo "Access Collibra DQ at: http://$ALB_DNS"
```

**Note**: By default, the ALB uses HTTP (port 80) for dev/testing. To enable HTTPS:
1. Request an ACM certificate for your domain
2. Set `COLLIBRA_DQ_ACM_CERTIFICATE_ARN` environment variable
3. Redeploy the ALB

When HTTPS is enabled, HTTP automatically redirects to HTTPS.

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

## Destruction

### Automated Destruction

Use the unified destruction script from the project root:

```bash
# From project root
./destroy-stack.sh collibra-dq dev
```

This script:
1. Destroys Target Group Attachment
2. Destroys Application Load Balancer
3. Destroys ALB Security Group
4. Destroys EC2 Instance
5. Destroys Package Upload (S3 object)
6. Destroys Collibra DQ Security Group
7. Destroys RDS Database
8. Destroys RDS Security Group
9. Preserves VPC and VPC Endpoints (if Soda Agent stack exists)
10. Preserves Bootstrap (shared resource)

**Note**: To destroy bootstrap, use `./destroy-stack.sh collibra-dq dev --destroy-bootstrap` (only after both stacks are destroyed).

### Manual Destruction

Destroy components in reverse order:

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

# 6. Collibra DQ Security Group
cd ../sg-collibra-dq
terragrunt destroy

# 7. RDS Database (WARNING: This deletes all data!)
cd ../../database/rds-collibra-dq/rds
terragrunt destroy

# 8. RDS Security Group
cd ../sg-rds
terragrunt destroy
```

**Warning**: Destroying the RDS database will delete all Collibra DQ data!

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
# From instance - use the helper script
/usr/local/bin/test-rds-connection.sh

# Or manually
source /etc/profile.d/collibra-dq.sh
export PGPASSWORD="$OWL_METASTORE_PASS"
psql -h "$POSTGRESQL_HOST" -p 5432 -U "$OWL_METASTORE_USER" -d dqMetastore -c "SELECT version();"
unset PGPASSWORD
```

### Health Check Failures

**Symptom**: ALB target shows unhealthy

**Check**:
- Instance security group allows port 9000 from ALB security group
- Collibra DQ Web service is running on port 9000
- Health check path is correct (`/`)
- Health check accepts HTTP 200 and 302 (redirect) responses

**Health Check Configuration**:
- Path: `/`
- Protocol: HTTP
- Port: 9000 (traffic-port)
- Matcher: `200,302` (accepts both OK and redirect responses)
- Interval: 30 seconds
- Timeout: 5 seconds
- Healthy threshold: 2 consecutive successes
- Unhealthy threshold: 3 consecutive failures

**Verify**:
```bash
# From instance
curl -I http://localhost:9000/
# Should return HTTP 200 or 302

# Health endpoint (if configured)
curl http://localhost:9101/health
```

## Destruction

### Automated Destruction

```bash
# From project root
./destroy-stack.sh collibra-dq dev
```

This script:
1. Destroys Target Group Attachment
2. Destroys Application Load Balancer
3. Destroys ALB Security Group
4. Destroys EC2 Instance
5. Destroys Package Upload (S3 object)
6. Destroys Collibra DQ Security Group
7. Destroys RDS Database
8. Destroys RDS Security Group
9. Preserves VPC and VPC Endpoints (if Soda Agent stack exists)
10. Preserves Bootstrap (shared resource)

**Note**: To destroy bootstrap, use `./destroy-stack.sh collibra-dq dev --destroy-bootstrap` (only after both stacks are destroyed).

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

**Note**: The unified destroy script (`./destroy-stack.sh collibra-dq dev`) will destroy the RDS database. Use manual destruction if you want to preserve the database.

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

## Testing and Verification

### Comprehensive Testing

Run the comprehensive test script to verify all components:

```bash
# From project root
./scripts/test-collibra-dq-deployment.sh dev
```

This script tests:
- EC2 instance status
- Collibra DQ service status
- Health endpoint (port 9101)
- Web port (port 9000)
- ALB and target group health
- RDS connectivity

### Quick Status Check

```bash
# Check deployment status
./scripts/utils/check-deployment-status.sh dev
```

### RDS Connection Testing

Test PostgreSQL connectivity using the helper script:

```bash
# Connect to instance via SSM
cd env/dev/eu-west-1/addons/collibra-dq-standalone
INSTANCE_ID=$(terragrunt output -raw instance_id)
aws ssm start-session --target $INSTANCE_ID --region eu-west-1

# Run connection test
/usr/local/bin/test-rds-connection.sh
```

## HTTPS Configuration

### Enabling HTTPS

By default, the ALB uses HTTP for dev/testing. To enable HTTPS:

1. **Request ACM Certificate**:
   ```bash
   aws acm request-certificate \
       --domain-name collibra-dq-dev.yourdomain.com \
       --validation-method DNS \
       --region eu-west-1
   ```

2. **Set Certificate ARN**:
   ```bash
   export COLLIBRA_DQ_ACM_CERTIFICATE_ARN="arn:aws:acm:eu-west-1:YOUR_ACCOUNT:certificate/YOUR_CERT_ID"
   ```

3. **Redeploy ALB**:
   ```bash
   cd env/dev/eu-west-1/addons/collibra-dq-standalone/alb
   terragrunt apply
   ```

When HTTPS is enabled:
- HTTPS listener on port 443 with TLS termination
- HTTP automatically redirects to HTTPS (301 redirect)
- TLS 1.3 security policy

## Scaling Options

### Vertical Scaling (Scale Up)

Easiest approach - increase instance size:

1. **Update instance type** in `terragrunt.hcl`:
   ```hcl
   locals {
     instance_config = {
       instance_type = "m5.xlarge"  # Upgrade from m5.large
       volume_size   = 200           # Increase if needed
     }
   }
   ```

2. **Redeploy**:
   ```bash
   cd env/dev/eu-west-1/addons/collibra-dq-standalone
   terragrunt apply
   ```

**Instance Type Recommendations**:
- **Dev**: `m5.large` (2 vCPU, 8GB RAM)
- **Small Prod**: `m5.xlarge` (4 vCPU, 16GB RAM)
- **Medium Prod**: `m5.2xlarge` (8 vCPU, 32GB RAM)
- **Large Prod**: `m5.4xlarge` (16 vCPU, 64GB RAM)

### Horizontal Scaling (Scale Out)

For high availability and load distribution, you can:
- Replace single EC2 instance with Auto Scaling Group
- Configure Spark Standalone cluster (one master, multiple workers)
- ALB automatically distributes traffic across instances

**Note**: Horizontal scaling requires architecture changes. See infrastructure documentation for details.

## Recent Improvements

### Installation Enhancements
- ✅ **PostgreSQL Client**: Automatically installed for RDS testing
- ✅ **Package Structure Detection**: Handles `owl/` subdirectory automatically
- ✅ **License Key Escaping**: Properly handles special characters in license keys
- ✅ **Directory Creation**: Automatically creates required directories (`config`, `bin`, `pids`, `log`)
- ✅ **RDS Connectivity Test**: Automatic connection test after installation
- ✅ **Helper Scripts**: `/usr/local/bin/test-rds-connection.sh` for persistent testing

### Health Check Improvements
- ✅ **HTTP 200 and 302 Support**: Health check accepts both OK and redirect responses
- ✅ **Improved Error Detection**: Better error handling in deployment scripts

### HTTPS Support
- ✅ **Conditional HTTPS**: Automatically enables HTTPS when ACM certificate is provided
- ✅ **HTTP Redirect**: Automatically redirects HTTP to HTTPS when certificate is set

## Additional Resources

- [Collibra DQ Documentation](https://docs.collibra.com/)
- [Infrastructure Documentation](../../../../../docs/INFRASTRUCTURE.md)
- [Troubleshooting Guide](#troubleshooting)
