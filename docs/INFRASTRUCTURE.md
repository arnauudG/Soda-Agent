# Infrastructure Overview

This document provides a high-level overview of the infrastructure architecture, networking, and common patterns used across all environments.

## Architecture Principles

### Network Design

The infrastructure follows AWS best practices for secure, scalable networking:

- **VPC Architecture**: Multi-AZ VPC with public and private subnets
- **Network Isolation**: Private subnets for workloads, public subnets for load balancers
- **Internet Access**: NAT Gateway for private subnet outbound connectivity
- **AWS Service Access**: VPC Endpoints for private access to AWS services (S3, ECR, SSM, etc.)

### Security Model

- **Defense in Depth**: Multiple layers of security (Security Groups, NACLs, IAM)
- **Least Privilege**: IAM roles with minimal required permissions
- **Network Segmentation**: Private subnets isolate workloads from direct internet access
- **Encryption**: Encryption at rest and in transit where applicable

### High Availability

- **Multi-AZ Deployment**: Resources distributed across 3 availability zones
- **Load Balancing**: Application Load Balancers for traffic distribution
- **Auto Scaling**: EKS node groups and EC2 Auto Scaling Groups where applicable

## Core Infrastructure Components

### VPC Network

**Purpose**: Provides isolated network environment for all resources

**Key Features**:
- CIDR: `10.10.0.0/16` (configurable per environment)
- Public subnets: `/22` per AZ (1024 IPs each)
- Private subnets: `/22` per AZ (1024 IPs each)
- DNS hostnames and resolution enabled
- VPC Flow Logs (enabled in prod, disabled in dev for cost optimization)

**Deployment**:
```bash
cd env/<env>/<region>/network/vpc
terragrunt apply
```

### VPC Endpoints

**Purpose**: Private connectivity to AWS services without internet gateway

**Endpoints Configured**:
- **S3 Gateway Endpoint**: For S3 access (attached to private route tables)
- **SSM Interface Endpoints**: For Systems Manager access
- **ECR Interface Endpoints**: For container registry access
- **STS Interface Endpoint**: For security token service
- **CloudWatch Logs Interface Endpoint**: For log streaming

**Benefits**:
- Reduced data transfer costs
- Improved security (traffic stays within AWS network)
- Lower latency for AWS service access

**Deployment**:
```bash
cd env/<env>/<region>/network/vpc-endpoints
terragrunt apply
```

### NAT Gateway

**Purpose**: Provides outbound internet access for private subnet resources

**Configuration**:
- **Dev**: Single NAT Gateway (cost optimization)
- **Prod**: Multiple NAT Gateways (one per AZ for HA)

**Use Cases**:
- Package downloads (yum/dnf repositories)
- External API calls
- Software updates

**Note**: S3 traffic routes through Gateway Endpoint (not NAT) when endpoint is configured.

## Network Connectivity Patterns

### Private Subnet Resources

Resources in private subnets can:
- ✅ Access AWS services via VPC Endpoints (S3, ECR, SSM, etc.)
- ✅ Access internet via NAT Gateway
- ✅ Access other VPC resources via VPC CIDR
- ❌ Receive direct inbound traffic from internet (use ALB/NLB instead)

### Public Subnet Resources

Resources in public subnets can:
- ✅ Receive direct inbound traffic from internet
- ✅ Access internet via Internet Gateway
- ✅ Access AWS services via VPC Endpoints or internet

**Typical Use**: Load balancers, NAT Gateways, Bastion hosts

## Common Networking Issues

### IPv6/Dualstack Considerations

**Issue**: Amazon Linux 2023 defaults to dualstack (IPv4/IPv6) for repository access, but VPC may be IPv4-only.

**Symptoms**: 
- `dnf`/`yum` timeouts when accessing repositories
- Some requests succeed, others hang

**Solution**: Configure applications to use IPv4-only:
- For `dnf`: Set `ip_resolve=4` in `/etc/dnf/dnf.conf`
- System-wide: Disable IPv6 via sysctl

**Note**: This is handled automatically in user-data scripts for EC2 instances.

### DNS Resolution

**VPC DNS Resolver**: `10.10.0.X` (where X is typically 2 for VPC CIDR base)

**Requirements**:
- `enableDnsHostnames` must be `true`
- `enableDnsSupport` must be `true`

**Verification**:
```bash
cat /etc/resolv.conf
# Should show: nameserver 10.10.0.2
```

### S3 Access from Private Subnets

**Two Paths Available**:
1. **S3 Gateway Endpoint** (preferred): Routes S3 traffic via VPC endpoint (no NAT charges)
2. **NAT Gateway**: Routes all internet traffic including S3 (incurs NAT charges)

**Configuration**: Gateway endpoint automatically routes S3 traffic when attached to route tables.

## Security Groups

### Default Behavior

- **Default Security Group**: Denies all traffic by default (managed by VPC module)
- **Custom Security Groups**: Explicit allow rules required for ingress/egress

### Common Patterns

**Web Application**:
- Ingress: Port 443 (HTTPS) from ALB security group
- Egress: Port 443 (HTTPS) to `0.0.0.0/0`, Port 53 (DNS) to VPC CIDR

**Database Access**:
- Ingress: Port 5432 (PostgreSQL) from application security groups
- Egress: Minimal (typically none)

**Bastion/Ops Instance**:
- Ingress: Port 22 (SSH) or Port 443 (SSM) from specific IPs
- Egress: Port 443 (HTTPS) to `0.0.0.0/0` for package downloads

## State Management

### Terraform State

- **Storage**: S3 bucket per environment/region
- **Locking**: DynamoDB table per environment
- **Versioning**: Enabled on state bucket
- **Encryption**: AES256 encryption at rest

### State Bucket Naming

Format: `<account-id>-<org>-<env>-tfstate-<region>`

Example: `215941404211-datashift-dev-tfstate-eu-west-1`

### State Lock Table

Format: `<account-id>-<org>-<env>-tf-locks`

Example: `215941404211-datashift-dev-tf-locks`

## Environment Differences

### Development (dev)

**Characteristics**:
- Cost-optimized (single NAT Gateway)
- VPC Flow Logs disabled
- Less restrictive for testing
- Faster iteration

**Use Cases**: Development, testing, proof-of-concept

### Production (prod)

**Characteristics**:
- High availability (multiple NAT Gateways)
- VPC Flow Logs enabled
- More restrictive security
- Enhanced monitoring

**Use Cases**: Production workloads, customer-facing services

## Troubleshooting

### Common Issues

1. **Instance can't reach internet**
   - Check NAT Gateway route in route table
   - Verify NAT Gateway is in `available` state
   - Check security group egress rules

2. **S3 access fails**
   - Verify S3 Gateway endpoint is attached to route table
   - Check endpoint policy allows access
   - Ensure DNS resolution works

3. **DNS resolution fails**
   - Verify VPC DNS settings (`enableDnsHostnames`, `enableDnsSupport`)
   - Check `/etc/resolv.conf` points to VPC resolver
   - Ensure security group allows DNS (port 53) to VPC CIDR

4. **Package manager timeouts**
   - Check IPv6/IPv4 configuration (see IPv6/Dualstack section)
   - Verify NAT Gateway or S3 endpoint routing
   - Check security group egress rules

### Diagnostic Commands

**Check route table**:
```bash
aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=<subnet-id>"
```

**Check NAT Gateway**:
```bash
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=<vpc-id>"
```

**Check VPC Endpoints**:
```bash
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=<vpc-id>"
```

**Check DNS configuration**:
```bash
aws ec2 describe-vpc-attribute --vpc-id <vpc-id> --attribute enableDnsHostnames
aws ec2 describe-vpc-attribute --vpc-id <vpc-id> --attribute enableDnsSupport
```

## Best Practices

1. **Always use private subnets** for workloads when possible
2. **Use VPC Endpoints** for AWS service access to reduce costs and improve security
3. **Configure security groups** with least privilege (specific ports, specific sources)
4. **Enable VPC Flow Logs** in production for security auditing
5. **Use multiple NAT Gateways** in production for high availability
6. **Document network requirements** for each addon/application
7. **Test connectivity** after network changes
8. **Monitor NAT Gateway costs** and optimize if needed

## Additional Resources

- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/)
- [VPC Endpoints Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [Security Groups Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/security-groups.html)
- [NAT Gateway Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)
