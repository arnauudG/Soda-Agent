# Soda Infrastructure - Terraform/Terragrunt

This repository contains the infrastructure as code for deploying Soda Agent on AWS using Terraform and Terragrunt.

## **Infrastructure Overview**

The infrastructure consists of:
- **VPC with private/public subnets** across 3 AZs
- **VPC Endpoints** for SSM, ECR, STS, CloudWatch Logs, and S3
- **EKS Cluster** with managed node groups
- **Ops Infrastructure** (EC2 instance, security groups, IAM roles)
- **Soda Agent** deployed via Helm on EKS
- **Collibra DQ Standalone** (optional) - EC2-based deployment with RDS PostgreSQL and ALB

## **Directory Structure**

```
Soda-Agent/
├── module/                         # Shared Terraform modules
│   ├── application/               # Application modules
│   │   ├── helm/soda-agent/      # Soda Agent Helm deployment
│   │   └── collibra-dq-standalone/ # Collibra DQ EC2 deployment
│   ├── compute/                   # Compute modules
│   │   ├── ec2/ops/              # EC2 ops instance
│   │   └── eks/cluster/          # EKS cluster
│   ├── database/                  # Database modules
│   │   └── rds/postgresql/       # RDS PostgreSQL
│   ├── network/                   # Network modules
│   │   ├── vpc/                  # VPC with subnets
│   │   ├── vpc-endpoints/        # VPC endpoints
│   │   └── alb/                  # Application Load Balancer
│   ├── security/                  # Security modules
│   │   ├── iam/ops-eks-access/   # EKS access configuration
│   │   └── security-group/       # Security groups
│   └── storage/                   # Storage modules
│       └── s3-package/           # S3 package storage
├── env/                            # Environment-specific configurations
│   ├── dev/
│   │   ├── root.hcl               # Environment-level config (env = "dev")
│   │   └── eu-west-1/
│   │       ├── root.hcl           # Region-level config (aws_region)
│   │       ├── bootstrap/          # Phase 0: Bootstrap (one-time)
│   │       ├── network/
│   │       │   ├── vpc/            # Phase 1: VPC
│   │       │   └── vpc-endpoints/  # Phase 2: VPC Endpoints
│   │       ├── ops/
│   │       │   ├── sg-ops/         # Phase 3: Security Groups
│   │       │   └── ec2-ops/        # Phase 5: EC2 Instance
│   │       ├── eks/
│   │       │   ├── terragrunt.hcl  # Phase 4: EKS Cluster
│   │       │   └── ops-ec2-eks-access/  # Phase 6: EKS Access
│   │       └── addons/
│   │           ├── soda-agent/     # Phase 7: Soda Agent
│   │           └── collibra-dq-standalone/  # Collibra DQ Standalone
│   │               └── README.md   # Addon-specific documentation
│   └── prod/
│       └── eu-west-1/              # Same structure as dev
├── scripts/                        # Testing, validation, and utility scripts
│   ├── test-collibra-dq-deployment.sh  # Comprehensive Collibra DQ testing
│   ├── test-modules.sh            # Terraform module validation
│   ├── test-terragrunt.sh         # Terragrunt config validation
│   ├── utils/                     # Utility scripts
│   │   └── check-deployment-status.sh
│   └── README.md                  # Scripts documentation
├── deploy-bootstrap.sh             # One-time bootstrap script (optional, auto-created by deploy-stack.sh)
├── deploy-stack.sh                 # Unified stack deployment (soda-agent | collibra-dq)
├── destroy-stack.sh                # Unified stack destruction (soda-agent | collibra-dq)
├── destroy-bootstrap.sh           # Bootstrap destruction (use destroy-stack.sh --destroy-bootstrap instead)
├── .pre-commit-config.yaml         # Pre-commit hooks configuration
├── .gitignore                      # Git ignore rules
└── README.md                       # This file
```

### **Terragrunt Configuration Hierarchy**

The configuration follows a hierarchical structure:

```
env/dev/root.hcl
  └── org = "datashift" (hardcoded)
  └── env = "dev"
  └── common_tags (without Region)
  
env/dev/eu-west-1/root.hcl
  └── includes env/dev/root.hcl
  └── aws_region = "eu-west-1"
  └── common_tags (with Region added)
  └── state_bucket, lock_table
```

**Note**: The `org` value is hardcoded in environment-level `root.hcl` files to avoid nested include issues. This simplifies the configuration hierarchy while maintaining the same functionality.

This structure allows:
- **Simplified Configuration**: No nested includes, easier to maintain
- **Multi-Region Support**: Easy to add new regions
- **Consistent Tagging**: Tags inherited through the hierarchy

## **Bootstrap Process (One-Time Setup)**

**CRITICAL**: Bootstrap must be run ONCE per environment before any other deployment.

The bootstrap process creates:
- **S3 bucket** for Terraform state storage
  - Versioning enabled
  - Encryption at rest (AES256)
  - Lifecycle policies (Glacier transition after 30 days, deletion after 90 days)
  - Public access blocked
  - TLS-only access enforced
- **DynamoDB table** for state locking
  - Point-in-time recovery enabled
  - Server-side encryption enabled
  - Pay-per-request billing mode
- **Consistent tagging** using common_tags from parent configuration

### **When to Bootstrap:**
- **New environment** (dev, prod)
- **First time setup**
- **Existing environment** (already has state bucket)

### **Bootstrap Command:**
```bash
./deploy-bootstrap.sh <environment>

# Examples:
./deploy-bootstrap.sh prod    # Bootstrap production environment
./deploy-bootstrap.sh dev     # Bootstrap development environment
```

### **Bootstrap Safety Features:**
- **Automatic detection** of existing resources
- **Multiple confirmation prompts** to prevent accidents
- **Automatic disable** after completion
- **Resource existence checks** before proceeding

### **Destroying Bootstrap Resources:**

**WARNING**: Bootstrap destruction should ONLY be run AFTER all infrastructure has been destroyed. This will delete:
- **All Terraform state files** (stored in S3 bucket)
- **State locking table** (DynamoDB)
- **All state history** (versioned state files)

**Bootstrap Destruction Command:**
```bash
./destroy-bootstrap.sh <environment>

# Examples:
./destroy-bootstrap.sh dev     # Destroy dev bootstrap resources
./destroy-bootstrap.sh prod    # Destroy prod bootstrap resources

# Or use the unified destroy script:
./destroy-stack.sh <stack> <env> --destroy-bootstrap
```

**Safety Features:**
- Requires explicit confirmation: Type `DESTROY BOOTSTRAP` to confirm
- Shows resource count before destruction
- Checks for existing resources
- Multiple warnings about data loss

**Order of Operations:**
1. Destroy all stacks: `./destroy-stack.sh <stack> <env>` (for each stack)
2. Destroy bootstrap: `./destroy-stack.sh <stack> <env> --destroy-bootstrap` (after both stacks destroyed)

## **Quick Start**

### **Deploy a Stack**

The easiest way to deploy is using the unified deployment script:

```bash
# Deploy Soda Agent stack (EKS-based)
./deploy-stack.sh soda-agent dev

# Deploy Collibra DQ Standalone stack (EC2-based)
./deploy-stack.sh collibra-dq dev

# For production
./deploy-stack.sh soda-agent prod
./deploy-stack.sh collibra-dq prod
```

**What happens automatically:**
- Bootstrap is created if missing
- Shared resources (VPC, endpoints) are reused if already deployed
- All dependencies are deployed in the correct order
- Package upload is automatically optimized (prevents re-uploads)

### **Destroy a Stack**

```bash
# Destroy Soda Agent stack (keeps shared resources)
./destroy-stack.sh soda-agent dev

# Destroy Collibra DQ Standalone stack (keeps shared resources)
./destroy-stack.sh collibra-dq dev

# Destroy bootstrap (only after both stacks are destroyed)
./destroy-stack.sh soda-agent dev --destroy-bootstrap
```

## **Manual Deployment (Advanced)**

If you need to deploy components manually, follow this order:

### **Phase 0: Bootstrap (One-time)**
```bash
./deploy-bootstrap.sh <env>  # Optional - auto-created by deploy-stack.sh
```

### **Soda Agent Stack Phases:**
1. VPC (`network/vpc`)
2. VPC Endpoints (`network/vpc-endpoints`)
3. Security Groups (`ops/sg-ops`)
4. EKS Cluster (`eks`)
5. EC2 Ops Instance (`ops/ec2-ops`)
6. EKS Access Configuration (`eks/ops-ec2-eks-access`)
7. Soda Agent (`addons/soda-agent`)

### **Collibra DQ Stack Phases:**
1. Bootstrap (`bootstrap`) - One-time setup
2. VPC (`network/vpc`) - Reused if exists
3. VPC Endpoints (`network/vpc-endpoints`) - Reused if exists
4. Collibra DQ Security Group (`addons/collibra-dq-standalone/sg-collibra-dq`)
5. RDS Security Group (`database/rds-collibra-dq/sg-rds`) - Depends on Collibra DQ SG
6. RDS Database (`database/rds-collibra-dq/rds`) - PostgreSQL metastore
7. Package Upload (`addons/collibra-dq-standalone/package-upload`) - S3 package storage
8. EC2 Instance (`addons/collibra-dq-standalone`) - Includes PostgreSQL client
9. ALB Security Group (`addons/collibra-dq-standalone/alb/sg-alb`)
10. Application Load Balancer (`addons/collibra-dq-standalone/alb`) - HTTP/HTTPS
11. Target Group Attachment (`addons/collibra-dq-standalone/alb/target-group-attachment`)

## **Environment Variables**

### **Required for Soda Agent**
```bash
export SODA_API_KEY_ID="your-soda-cloud-api-key"
export SODA_API_KEY_SECRET="your-soda-cloud-api-secret"
export SODA_IMAGE_APIKEY_ID="your-soda-registry-api-key"
export SODA_IMAGE_APIKEY_SECRET="your-soda-registry-api-secret"
```

### **Optional**
```bash
export SODA_CLOUD_REGION="eu"  # or "us"
export SODA_LOG_FORMAT="raw"   # or "json"
export SODA_LOG_LEVEL="INFO"   # ERROR, WARN, INFO, DEBUG, TRACE
```

## **Common Issues & Troubleshooting**

### **1. Bootstrap Issues**
**Error**: `NoSuchBucket` or `NoSuchTable`

**Solution**: Run bootstrap first:
```bash
./deploy-bootstrap.sh <env>
```

### **2. Dependency Errors**
**Error**: `detected no outputs` or `Unknown variable: dependency` or `There is no variable named "dependency"`

**Causes & Solutions**:
- **During initial deployment**: This is normal when dependencies haven't been applied yet. Use the automated deployment scripts.
- **During destroy operations**: When a dependency has already been destroyed, Terragrunt can't read its outputs. Add `"destroy"` to `mock_outputs_allowed_terraform_commands`.
- **Corrupted terragrunt.hcl files**: Check for error messages accidentally pasted into configuration files.
- **Missing mock outputs**: Ensure `dependency` blocks have proper `mock_outputs` for validation.

**Fix for destroy operations**:
Update dependency blocks to allow mock outputs during destroy:
```hcl
dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    vpc_id = "vpc-123456"
    # ... other mock outputs
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "destroy"]  # Add "destroy"
}
```

**Fix corrupted files**:
```bash
# Check for error messages in terragrunt.hcl files
grep -r "ERROR\|WARN" env/*/eu-west-1/*/terragrunt.hcl

# Restore from working dev environment if needed
cp env/dev/eu-west-1/ops/sg-ops/terragrunt.hcl env/prod/eu-west-1/ops/sg-ops/terragrunt.hcl
```

### **3. EKS Cluster Not Found**
**Error**: `reading EKS Cluster: couldn't find resource`

**Solution**: Deploy the EKS cluster first before deploying addons or EKS access configurations.

### **4. IAM Role Not Found**
**Error**: `reading IAM Role: couldn't find resource`

**Solution**: Deploy the ops infrastructure (EC2, security groups) before deploying EKS access configurations.

### **5. Soda Agent Namespace Issues**
**Error**: `namespaces "soda-agent" not found`

**Solution**: The Soda Agent module now creates the namespace explicitly. This error should be resolved with the updated module.

**Manual fix if needed**:
```bash
# Connect to EKS cluster
aws eks update-kubeconfig --region eu-west-1 --name <cluster-name>

# Create namespace manually
kubectl create namespace soda-agent
```

### **6. Helm Chart Download Issues**
**Error**: `401 Unauthorized` when downloading Helm chart

**Solution**: 
```bash
# Add the Soda Helm repository
helm repo add soda-agent https://registry.cloud.soda.io/chartrepo/agent
helm repo update
```

### **7. Image Pull BackOff**
**Error**: `pull access denied, repository does not exist or may require authorization`

**Solution**: Ensure `SODA_IMAGE_APIKEY_ID` and `SODA_IMAGE_APIKEY_SECRET` are set correctly.

### **8. Agent Registration Errors**
**Error**: `agent with name already registered`

**Solution**: Use unique agent names by appending timestamps or use different API keys.

### **9. Terragrunt Configuration Corruption**
**Error**: Error messages appearing in terragrunt.hcl files

**Symptoms**:
- Files contain terminal output mixed with configuration
- `Unknown variable: dependency` errors
- Validation failures

**Solution**:
```bash
# Check for corrupted files
find env/ -name "terragrunt.hcl" -exec grep -l "ERROR\|WARN\|arnaudgueulette" {} \;

# Restore from working environment
cp env/dev/eu-west-1/ops/sg-ops/terragrunt.hcl env/prod/eu-west-1/ops/sg-ops/terragrunt.hcl
```

### **10. Deployment Order Issues**
**Error**: Resources failing due to missing dependencies

**Solution**: Always use the automated deployment scripts:
```bash
# Deploy Soda Agent stack
./deploy-stack.sh soda-agent <env>

# Deploy Collibra DQ stack
./deploy-stack.sh collibra-dq <env>
```

### **11. Bootstrap Destruction Issues**
**Error**: `skip = false` already set, or nested include errors during bootstrap destroy

**Solution**: 
- The bootstrap destruction script handles `skip = false` gracefully
- Nested include errors in sibling directories don't affect bootstrap destruction
- Bootstrap uses standalone configuration to avoid include issues
- Ensure all infrastructure is destroyed before destroying bootstrap

**Manual bootstrap destruction**:
```bash
cd env/<env>/eu-west-1/bootstrap
# Enable if needed
sed -i.bak 's/skip = true/skip = false/' terragrunt.hcl
terragrunt destroy --auto-approve
# Disable after destruction
sed -i.bak 's/skip = false/skip = true/' terragrunt.hcl
```

### **12. Stuck VPC Destruction & Orphaned Resources**
**Error**: VPC stuck in "Still destroying..." state, or `DependencyViolation` when manually deleting resources

**Symptoms**:
- Terraform destroy hangs on VPC destruction for extended periods (>2 minutes)
- Manual `aws ec2 delete-vpc` fails with `DependencyViolation`
- Resources exist in AWS but not in Terraform state (orphaned resources)

**Solution - Step 1: Unlock State Lock**
If Terraform is stuck, first unlock the state:
```bash
cd env/<env>/eu-west-1/network/vpc
# Get the lock ID from the error message, then:
terragrunt force-unlock -force <lock-id>
```

**Solution - Step 2: Identify Blocking Resources**
Check what's preventing VPC deletion:
```bash
VPC_ID="vpc-xxxxxxxxx"  # Replace with your VPC ID
REGION="eu-west-1"       # Replace with your region

# Check for VPC endpoints
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query 'VpcEndpoints[*].[VpcEndpointId,ServiceName,State]' --output table

# Check for network interfaces
aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,InterfaceType,Description]' --output table

# Check for subnets
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query 'Subnets[*].[SubnetId,State,AvailabilityZone]' --output table

# Check for security groups (non-default)
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query 'SecurityGroups[?GroupName!=`default`].[GroupId,GroupName]' --output table

# Check for Internet Gateway
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --region $REGION --query 'InternetGateways[*].[InternetGatewayId,State]' --output table

# Check for NAT Gateways
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --region $REGION --query 'NatGateways[*].[NatGatewayId,State,SubnetId]' --output table

# Check for route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --query 'RouteTables[*].[RouteTableId,Associations[0].Main]' --output table
```

**Solution - Step 3: Manual Cleanup (Delete in Order)**
Delete resources in dependency order:

1. **Delete VPC Endpoints** (if any):
```bash
aws ec2 delete-vpc-endpoint --vpc-endpoint-id <endpoint-id> --region $REGION
```

2. **Delete Subnets** (if any):
```bash
aws ec2 delete-subnet --subnet-id <subnet-id> --region $REGION
```

3. **Delete Security Groups** (non-default):
```bash
aws ec2 delete-security-group --group-id <sg-id> --region $REGION
```

4. **Delete NAT Gateways** (if any):
```bash
aws ec2 delete-nat-gateway --nat-gateway-id <nat-gateway-id> --region $REGION
# Wait for NAT Gateway to be deleted (may take a few minutes)
```

5. **Detach and Delete Internet Gateway** (if any):
```bash
# First detach
aws ec2 detach-internet-gateway --internet-gateway-id <igw-id> --vpc-id $VPC_ID --region $REGION
# Then delete
aws ec2 delete-internet-gateway --internet-gateway-id <igw-id> --region $REGION
```

6. **Delete VPC**:
```bash
aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION
```

**Solution - Step 4: Clean Up Terraform State (if needed)**
If resources were orphaned (exist in AWS but not in Terraform state), check and clean state:
```bash
cd env/<env>/eu-west-1/network/vpc
# List all resources in state
terragrunt state list

# If orphaned resources appear in state, remove them:
terragrunt state rm 'module.vpc.aws_vpc.this[0]'  # Adjust resource address as needed
```

**Prevention**:
- Always destroy infrastructure in reverse dependency order using `./destroy.sh <env>`
- Ensure VPC endpoints are destroyed before VPC (Phase 2 before Phase 1)
- Use `mock_outputs_allowed_terraform_commands = ["init", "plan", "destroy"]` in dependency blocks to allow mock outputs during destroy operations

## **Cleanup & Maintenance**

### **Remove Generated Files**
```bash
# Remove Terraform artifacts
find . -name ".terraform" -type d -exec rm -rf {} \;
find . -name ".terraform.lock.hcl" -exec rm -f {} \;
find . -name "*.tfstate*" -exec rm -f {} \;
find . -name "*.tfplan" -exec rm -f {} \;
find . -name "versions_override.tf" -exec rm -f {} \;
find . -name "provider_override.tf" -exec rm -f {} \;
```

### **Clear Terragrunt Cache**
```bash
rm -rf ~/.terragrunt-cache
```

## **Pre-deployment Checklist**

- [ ] **Bootstrap completed** (one-time setup)
- [ ] AWS credentials configured (`aws configure` or environment variables)
- [ ] Soda API keys exported as environment variables
- [ ] Helm repositories added and updated
- [ ] No existing infrastructure conflicts
- [ ] Proper AWS region selected
- [ ] S3 bucket for Terraform state exists (created by bootstrap)

## **Module Dependencies**

```
bootstrap (one-time)
├── Phase 1: network/vpc
│   ├── Phase 2: network/vpc-endpoints (depends on vpc)
│   ├── Phase 3: ops/sg-ops (depends on vpc)
│   ├── Phase 4: eks (depends on vpc)
│   │   ├── Phase 5: ops/ec2-ops (depends on vpc + ops/sg-ops)
│   │   └── Phase 6: ops-ec2-eks-access (depends on eks + ops/ec2-ops)
│   └── Phase 7: addons/soda-agent (depends on eks)
```

## **Useful Commands**

### **Bootstrap**
```bash
./deploy-bootstrap.sh <env>           # Bootstrap new environment
./destroy-bootstrap.sh <env>   # Destroy bootstrap (after all infrastructure)
```

### **Deploy Stacks**
```bash
./deploy-stack.sh <stack> <env>     # Deploy entire stack
# Examples:
./deploy-stack.sh soda-agent dev    # Deploy Soda Agent stack
./deploy-stack.sh collibra-dq prod  # Deploy Collibra DQ stack
```

### **Destroy Stacks**
```bash
./destroy-stack.sh <stack> <env>                    # Destroy stack (keeps shared resources)
./destroy-stack.sh <stack> <env> --destroy-bootstrap  # Also destroy bootstrap
# Examples:
./destroy-stack.sh soda-agent dev                    # Destroy Soda Agent stack
./destroy-stack.sh collibra-dq prod                  # Destroy Collibra DQ stack
```

### **Validate Configuration**
```bash
terragrunt validate-inputs
terragrunt hcl validate --inputs
```

### **Plan Changes**
```bash
terragrunt plan
```

### **Apply Changes**
```bash
terragrunt apply --auto-approve
```

### **Check Status**
```bash
terragrunt output
terragrunt show
```

### **Force Unlock State**
```bash
terragrunt force-unlock <lock-id>
```

## ⚡ **Quick Reference**

### **Most Common Commands**
```bash
# Bootstrap new environment (one-time, automatic if missing)
./deploy-bootstrap.sh prod

# Deploy entire stacks
./deploy-stack.sh soda-agent prod      # Deploy Soda Agent stack
./deploy-stack.sh collibra-dq dev       # Deploy Collibra DQ stack

# Destroy entire stacks
./destroy-stack.sh soda-agent prod      # Destroy Soda Agent stack
./destroy-stack.sh collibra-dq dev      # Destroy Collibra DQ stack

# Destroy bootstrap (only after both stacks destroyed)
./destroy-stack.sh soda-agent prod --destroy-bootstrap

# Check for corrupted files
find env/ -name "terragrunt.hcl" -exec grep -l "ERROR\|WARN" {} \;

# Validate configuration
terragrunt hcl validate --inputs
```

## **Soda Agent Stack Deployment**

### **Quick Start**

Deploy the entire Soda Agent stack:

```bash
# Set required environment variables
export SODA_API_KEY_ID="your-api-key"
export SODA_API_KEY_SECRET="your-api-secret"

# Deploy Soda Agent stack
./deploy-stack.sh soda-agent dev

# For production
./deploy-stack.sh soda-agent prod
```

**What gets deployed:**
1. Bootstrap (if missing)
2. VPC with public/private subnets
3. VPC Endpoints (S3, SSM, ECR, STS, CloudWatch Logs)
4. Security Groups (Ops)
5. EKS Cluster with managed node groups
6. EC2 Ops Instance
7. EKS Access Configuration
8. Soda Agent (Helm chart)

### **Environment Variables**

**Required Variables**:
```bash
export SODA_API_KEY_ID="your-api-key"
export SODA_API_KEY_SECRET="your-api-secret"
```

**Optional Variables** (for separate image registry credentials):
```bash
# Only set these if you want to use different credentials for image registry
export SODA_IMAGE_APIKEY_ID="your-image-key"
export SODA_IMAGE_APIKEY_SECRET="your-image-secret"
```

**Image Registry Credentials Behavior** (1.2.0+):
- **Default**: If `SODA_IMAGE_APIKEY_ID` is not set, the agent automatically uses `SODA_API_KEY_ID` and `SODA_API_KEY_SECRET` for both Soda Cloud and image registry authentication
- **Separate Credentials**: If `SODA_IMAGE_APIKEY_ID` is set, those credentials are used exclusively for image registry
- **Configuration**: This fallback logic is implemented in `env/*/eu-west-1/addons/soda-agent/terragrunt.hcl` using locals

**Other Optional Variables**:
```bash
export SODA_CLOUD_REGION="eu"  # or "us" (defaults to "eu")
export SODA_LOG_FORMAT="raw"   # or "json" (defaults to "raw")
export SODA_LOG_LEVEL="INFO"   # ERROR, WARN, INFO, DEBUG, or TRACE (defaults to "INFO")
```

### **Destroy Soda Agent Stack**

```bash
# Destroy Soda Agent stack (keeps shared resources)
./destroy-stack.sh soda-agent dev

# Destroy bootstrap (only after both stacks are destroyed)
./destroy-stack.sh soda-agent dev --destroy-bootstrap
```

## **Getting Help**

1. **Use unified deployment scripts** - `./deploy-stack.sh` and `./destroy-stack.sh` handle dependencies automatically
2. **Check this README** for common issues and solutions
3. **Bootstrap is automatic** - created automatically if missing during deployment
4. **Check environment variables** - ensure all required variables are set
5. **Verify AWS resources** - ensure no conflicts with existing infrastructure
6. **Check Terraform state** - ensure state is consistent
7. **Package upload optimization** - uploads are automatically optimized (prevents re-uploads)
8. **Destroy stacks safely** - use `./destroy-stack.sh` which preserves shared resources

## **Recent Improvements**

### **Configuration Structure (2024)**
- **Hierarchical Configuration**: Reorganized Terragrunt configs with repo → environment → region hierarchy
- **DRY Principle**: Organization name defined once at repo root, inherited by all environments
- **Multi-Region Ready**: Region-specific configs make it easy to add new AWS regions

### **Security Enhancements**
- **Environment-Specific Security**: Prod EKS endpoint is private-only, dev can be restricted to CIDRs
- **CloudWatch Logging**: EKS control plane logging enabled (7 days dev, 30 days prod)
- **Encryption**: EKS secrets encryption at rest enabled
- **VPC Flow Logs**: Enabled for prod environment

### **Operational Improvements**
- **Pre-commit Hooks**: Automated Terraform validation, formatting, and security scanning
- **Resource Tagging**: Standardized common tags across all resources
- **Environment-Specific Configs**: Different instance sizes, node counts for dev vs prod
- **Cost Optimization**: Prod uses multiple NAT gateways for HA, dev uses single NAT

### **Soda Agent Module Updates (January 2025)**
- **Namespace Creation**: Added explicit `kubernetes_namespace` resource to ensure namespace exists before creating secrets
- **Dependency Management**: Improved resource dependencies to prevent race conditions
- **Helm Configuration**: Disabled `create_namespace` in Helm release since we create it explicitly
- **Image Registry Credentials (1.2.0+)**:
  - **Fallback Configuration**: Image registry credentials automatically fall back to main API keys if `SODA_IMAGE_APIKEY_ID` is not set
  - **Configuration**: Uses locals in Terragrunt to compute credentials with fallback logic
  - **Implementation**: 
    ```hcl
    locals {
      api_key_id     = get_env("SODA_API_KEY_ID", "")
      api_key_secret = get_env("SODA_API_KEY_SECRET", "")
      image_credentials_id     = get_env("SODA_IMAGE_APIKEY_ID", local.api_key_id)
      image_credentials_secret = get_env("SODA_IMAGE_APIKEY_SECRET", local.api_key_secret)
    }
    ```
  - **Benefits**: Simplifies configuration - same API keys can be used for both Soda Cloud and image registry (default behavior per Soda documentation)
  - **Applied to**: Both dev and prod environments
- **Chart Version Pinning**:
  - **Current Version**: `1.3.13` (pinned for both dev and prod)
  - **Upgrade Path**: Successfully upgraded from `1.2.4` to `1.3.13` via fresh install
  - **Status**: ✅ Agent operational with new version, processing instructions successfully
  - **Bug Fixes**: Resolved NullPointerException instruction fetching bug present in `1.2.4`
- **Configuration Consistency**:
  - **Dev and Prod Alignment**: Both environments now use identical configuration structure
  - **Image Credentials**: Same fallback logic implemented in both environments
  - **Version Management**: Consistent chart version pinning across environments

### **Terragrunt Configuration Fixes**
- **Mock Outputs**: Added proper mock outputs for all dependency blocks to enable validation
- **Mock Outputs During Destroy**: Updated `mock_outputs_allowed_terraform_commands` to include `"destroy"` to allow dependencies to work when parent resources are already destroyed
- **Dependency Ordering**: Ensured correct `dependencies` and `dependency` block usage
- **Configuration Validation**: Fixed corrupted terragrunt.hcl files that contained error messages
- **Orphaned Resource Cleanup**: Added comprehensive troubleshooting guide for stuck VPC destruction and manual cleanup procedures

### **Deployment Scripts**
- **Automated Deployment**: Enhanced deployment scripts with better error handling
- **Phase-based Deployment**: Improved phase-by-phase deployment with proper dependency resolution
- **Bootstrap Safety**: Added multiple safety checks and confirmations for bootstrap process
- **Bootstrap Destruction**: Added `destroy-bootstrap.sh` script with explicit confirmation requirements
- **Bootstrap Re-run Support**: Bootstrap script now handles already-enabled bootstrap gracefully

### **Bootstrap Module Enhancements**
- **S3 Lifecycle Management**: Automatic transition to Glacier after 30 days, deletion after 90 days
- **S3 Lifecycle Filter**: Added required `filter {}` blocks to lifecycle rules (AWS provider requirement)
- **DynamoDB Point-in-Time Recovery**: Enabled for disaster recovery
- **DynamoDB Encryption**: Server-side encryption enabled
- **Consistent Tagging**: Uses common_tags from parent configuration
- **Provider Version**: Updated to match other modules (>= 5.61.0, < 6.0.0)
- **Bootstrap Destruction Script**: Added `destroy-bootstrap.sh` for safe bootstrap resource cleanup
- **Standalone Configuration**: Bootstrap uses direct value construction to avoid nested include issues

### **Ops Infrastructure Fine-Tuning (January 2025)**
- **Configuration Architecture**:
  - Uses direct path includes to env-level `root.hcl` (e.g., `../../../root.hcl` for 3-level deep modules)
  - Proper state management with `remote_state`, `provider`, and `backend` generation blocks
  - Region extraction from path for consistency
- **Security Group Hardening**:
  - Restricted HTTPS egress from `0.0.0.0/0` to VPC CIDR block (uses VPC endpoints for all AWS service communication)
  - Added HTTP (port 80) egress for package updates to AWS repositories
  - Improved security group descriptions and rule documentation
  - All traffic now routes through VPC endpoints for enhanced security and cost control
- **EC2 Instance Enhancements**:
  - Added `AmazonEC2ContainerRegistryReadOnly` IAM policy for ECR access (pulling container images)
  - Added `CloudWatchLogsFullAccess` IAM policy for better observability and log management
  - Enhanced root block device configuration with explicit GP3 IOPS (3000) and throughput (125 MB/s)
  - Added `delete_on_termination = true` for proper cleanup
  - Improved instance metadata security with `http_put_response_hop_limit = 1` and `instance_metadata_tags = enabled`
  - **CPU Credit Specification**: Dev uses `unlimited` credits (prevents CPU throttling), Prod uses `standard` credits (predictable costs)
  - **Instance Placement**: Explicit tenancy configuration for cost optimization
  - **EBS Optimization**: Explicit configuration for cost savings
- **Cost Optimizations**:
  - **Dev**: `t3.micro` instance (smallest available), unlimited CPU credits
  - **Prod**: `t3.small` instance, standard CPU credits
  - GP3 volumes with baseline IOPS/throughput (minimum for dev, baseline for prod)
- **Applied to Both Environments**: All improvements applied consistently to both dev and prod environments

### **EKS Cluster Fine-Tuning (January 2025)**
- **Configuration Architecture**:
  - Uses direct path includes to env-level `root.hcl` (e.g., `../../root.hcl` for 2-level deep modules)
  - Proper state management with `remote_state`, `provider`, and `backend` generation blocks
  - Region extraction from path for consistency
- **Node Group Enhancements**:
  - **Disk Configuration**: GP3 disks with explicit IOPS/throughput (20GB dev, 50GB prod)
  - **Instance Metadata Security**: IMDSv2 required, hop limit set to 2
  - **Node Labels**: Environment, NodeGroup, ManagedBy for better pod scheduling
  - **Update Configuration**: Zero-downtime updates (50% dev, 33% prod max unavailable)
- **Security Improvements**:
  - **Encryption**: Encrypts `secrets` at rest (AWS EKS limitation - only secrets supported)
  - **Metadata Options**: IMDSv2 required on all nodes
- **Cluster Addons**:
  - **CoreDNS**: Resource limits configured (dev: 200m CPU/256Mi mem, prod: 500m CPU/512Mi mem)
  - **VPC CNI**: Prefix delegation enabled for better IP management
  - **EBS CSI Driver**: Added for persistent volumes support
- **Cost Optimizations**:
  - **Dev**: `t3.micro` instances, `min_size=0` (can scale to zero with cluster autoscaler), SPOT pricing
  - **Prod**: `t3.small` instances (reduced from t3.medium/t3.large), SPOT pricing (~70% savings)
  - **Documentation**: Added Cluster Autoscaler and kube-downscaler installation instructions in config files
- **Network Connectivity**:
  - **External Data Sources**: EKS nodes can reach external data sources via NAT Gateway
  - **Default Egress**: EKS module provides default egress rules (all outbound allowed)
  - **Traffic Flow**: Pods → Node SG → NAT Gateway → Internet → External Data Sources

### **Cluster Capacity and Resource Configuration (January 2025)**
- **Current Configuration**:
  - **Node Type**: `t3.small` (2 vCPU, 2GB RAM)
  - **Capacity**: Supports up to 6 scans in parallel
  - **Resource Allocation**:
    - Soda Agent Orchestrator: 500m CPU, 512Mi memory
    - CoreDNS (2 pods): 200m CPU, 140Mi memory
    - System pods (VPC CNI, kube-proxy): ~150m CPU
  - **Available Resources**: ~1.15 CPU cores, ~1.3GB memory available for scan jobs
- **Resource Monitoring**:
  ```bash
  # Check node capacity
  kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.capacity.cpu}{"\t"}{.status.capacity.memory}{"\n"}{end}'
  
  # Check allocated resources
  kubectl describe node | grep -A 10 "Allocated resources:"
  
  # Check pod resource requests/limits
  kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.containers[0].resources.requests.cpu}{"\t"}{.spec.containers[0].resources.requests.memory}{"\n"}{end}'
  ```
- **Scaling Considerations**:
  - Current setup is sufficient for up to 6 parallel scans
  - If more capacity is needed, consider:
    - Increasing `max_size` in node group configuration
    - Upgrading to `t3.medium` (2 vCPU, 4GB RAM) for more memory
    - Installing Cluster Autoscaler for automatic scaling

### **Soda Agent Instruction Fetching Bug (January 2025) - ✅ RESOLVED**

- **Issue**: Agent version `v2.1.19` (image: `registry.cloud.soda.io/sodadata/agent-orchestrator:v2.1.19`) experienced `NullPointerException` when fetching instructions from Soda Cloud
- **Status**: ✅ **RESOLVED** - Fixed by upgrading to chart version `1.3.13` (agent image `v2.2.2`)
- **Resolution Date**: January 24, 2026
- **Resolution Method**: Fresh install with upgraded chart version
- **Previous Symptoms** (now resolved):
  - Agent pod was running and healthy (1/1 Ready, 0 restarts)
  - Agent successfully registered and connected to Soda Cloud
  - Repeated errors in logs: `NullPointerException: Cannot invoke "io.soda.agent.orchestrator.cloud.api.CoreAgentInstructionDTO.getId()" because "dto" is null`
  - Agent could not receive new instructions (including data source connection instructions)
- **Previous Root Cause**: Soda Cloud API returned null entries in the instructions array, and the agent code didn't filter nulls before processing
- **Current Status**: 
  - ✅ Agent successfully fetching and processing instructions
  - ✅ Multiple instructions completed successfully
  - ✅ No NullPointerException errors in logs
  - ✅ Ready for data source connections (Snowflake, etc.)
- **Troubleshooting Steps**:
  1. **Check Agent Status**:
     ```bash
     kubectl get pods -n soda-agent
     kubectl logs -n soda-agent -l app.kubernetes.io/name=soda-agent --tail=50
     ```
  2. **Verify Agent Registration**:
     ```bash
     kubectl logs -n soda-agent -l app.kubernetes.io/name=soda-agent | grep -E "(registered|Connected|Agent ID)"
     ```
  3. **Check for Successful Instruction Fetches**:
     ```bash
     kubectl logs -n soda-agent -l app.kubernetes.io/name=soda-agent | grep -E "(Fetched.*instructions|Received cloud instruction)"
     ```
  4. **Restart Agent Pod** (temporary workaround):
     ```bash
     kubectl delete pod -n soda-agent -l app.kubernetes.io/name=soda-agent
     ```
  5. **Check Agent Version**:
     ```bash
     kubectl describe pod -n soda-agent -l app.kubernetes.io/name=soda-agent | grep "Image:"
     ```
- **Solutions**:
  1. **Contact Soda Support**: Report the bug with:
     - Agent version: `v2.1.19`
     - Error: `NullPointerException` in `CloudMapper.toInstruction()` at line 63
     - Agent name: `datashift-dev-eu-west-1-agent` (or your agent name)
     - Agent ID: Check logs for "Agent registered successfully in Soda Cloud: '<agent-id>'"
  2. **Check for Newer Agent Version**:
     - Current chart version: `""` (latest)
     - Current agent image: `registry.cloud.soda.io/sodadata/agent-orchestrator:v2.1.19`
     - Check available chart versions:
       ```bash
       helm repo update soda-agent
       helm search repo soda-agent/soda-agent --versions
       ```
     - Check available agent image versions (requires Soda registry access):
       ```bash
       # Note: This requires authentication to registry.cloud.soda.io
       # Check Soda documentation for available agent versions
       ```
     - Update chart version in `env/*/eu-west-1/addons/soda-agent/terragrunt.hcl`:
       ```hcl
       chart_version = "X.Y.Z"  # Specify newer version if available
       ```
     - After updating, redeploy:
       ```bash
       cd env/dev/eu-west-1/addons/soda-agent
       terragrunt apply
       ```
  3. **Verify in Soda Cloud UI**:
     - Confirm agent appears as online/connected
     - Verify data source configuration is correct
     - Check if instructions are queued (they won't process until bug is fixed)
- **Resolution**: Upgraded to chart version `1.3.13` which includes fixes for instruction handling
- **Note**: The bug was in the Soda Agent application code (v2.1.19). The fix was included in later versions (v2.2.2+).

## **Soda Agent Deployment Requirements (Official Documentation)**

### **Prerequisites**
- AWS account with permissions to create/access EKS cluster
- `kubectl` v1.22 or v1.23 installed
- `helm` installed
- Enterprise plan (self-hosted agents require Enterprise plan; contact https://www.soda.io/contact)

### **Network Requirements - URLs to Whitelist**

**Required Outbound Access (Port 443/HTTPS)**:

**For Soda EU Region** (`https://cloud.soda.io`):
- `cloud.soda.io` (Soda Cloud API)
- `collect.soda.io` (Soda Cloud collector)
- `registry.cloud.soda.io` (Soda container registry)
- `soda-cloud-platform-registry.s3.eu-west-1.amazonaws.com` (Soda platform registry)
- `*.docker.io` (Docker Hub for base images)

**For Soda US Region** (`https://cloud.us.soda.io`):
- `cloud.us.soda.io` (Soda Cloud API)
- `collect.soda.io` (Soda Cloud collector)
- `registry.us.soda.io` (Soda container registry)
- `soda-cloud-us-platform-registry.s3.us-west-2.amazonaws.com` (Soda platform registry)
- `*.docker.io` (Docker Hub for base images)

**Current Configuration Status**:
- ✅ EKS node security group allows all outbound traffic (0.0.0.0/0) on all ports
- ✅ Port 443 accessible to `cloud.soda.io` and `collect.soda.io` (verified)
- ✅ DNS resolution working for all required FQDNs
- ✅ Network path: Pods → Node SG → NAT Gateway → Internet → Soda Cloud

**Note**: The agent only requires outbound communication. It polls Soda Cloud for instructions, and when Soda Cloud needs to deliver instructions, the agent opens a bidirectional channel. No inbound rules are required.

### **System Requirements**
- **Minimum Cluster Size**: 2 CPU and 2GB RAM
- **Capacity**: Sufficient to run up to 6 scans in parallel
- **Current Configuration**: `t3.small` (2 vCPU, 2GB RAM) - ✅ Meets requirements

**Performance Optimization**:
- Fine-tune resources using `soda.agent.resources` and `soda.scanlauncher.resources` parameters
- Adding more resources to scan-launcher can improve scan times by up to 30%
- Consider adding more nodes or cluster autoscaler for larger workloads
- **Reference**: Soda-hosted agent uses:
  ```yaml
  soda:
    agent:
      resources:
        limits:
          cpu: 250m
          memory: 375Mi
        requests:
          cpu: 250m
          memory: 375Mi
  ```

### **Helm Chart Repository**
- **Official Repository URL**: `https://helm.soda.io/soda-agent/`
- **Repository Name**: `soda-agent` (used in configuration)
- **Chart Name**: `soda-agent`
- **Current Status**: ✅ Repository is configured locally (`helm repo list` shows `soda-agent`)
- **Configuration**: 
  - Terragrunt config uses `chart_repo = "soda-agent"` (repository name)
  - Helm provider automatically resolves the repository name to the configured URL
  - To add/update the repository manually: `helm repo add soda-agent https://helm.soda.io/soda-agent/`

### **Cloud Endpoint Configuration**
- **US Region**: `https://cloud.us.soda.io`
- **EU/Other Regions**: `https://cloud.soda.io`
- **Current Configuration**: Configurable via `SODA_CLOUD_REGION` environment variable (defaults to EU)
- **Critical**: The endpoint must match the region where your Soda Cloud account was created

### **Resource Configuration (Optional)**
To customize resource limits and requests, you can add the following to your Helm values (currently not exposed in Terraform module, but can be added):

```yaml
soda:
  agent:
    resources:
      limits:
        cpu: x
        memory: x
      requests:
        cpu: x
        memory: x
  scanlauncher:
    resources:
      limits:
        cpu: x
        memory: x
      requests:
        cpu: x
        memory: x
```

**Note**: Allocating too many resources may be costly relative to the small benefit of improved scan times. The default configuration (2 CPU, 2GB RAM) is sufficient for most use cases.

### **Troubleshooting Deployment Issues (Official)**

**Problem**: Agent not visible in Soda Cloud after deployment

**Solution**: The `soda.cloud.endpoint` value must correspond with the region you selected when you signed up for a Soda Cloud account:
- Use `https://cloud.us.soda.io` for the United States
- Use `https://cloud.soda.io` for all else

**Problem**: Network connectivity issues

**Solution**: Define outgoing port 443 and allowlist the fully-qualified domain names:
- `cloud.us.soda.io` (for US region) OR `cloud.soda.io` (for EU region)
- AND `collect.soda.io` (required for all regions)
- Plus registry URLs and S3 buckets (see "Network Requirements" above)

**Problem**: `UnauthorizedOperation: You are not authorized to perform this operation`

**Solution**: Your user profile is not authorized to create the cluster. Contact your AWS Administrator to request the appropriate permissions.

**Current Configuration Status**:
- ✅ Cloud endpoint: Configurable via `SODA_CLOUD_REGION` env var (defaults to EU: `https://cloud.soda.io`)
- ✅ Network access: All required FQDNs are accessible (verified via connectivity tests)
- ✅ Security groups: EKS nodes allow all outbound traffic (0.0.0.0/0)

## **Collibra DQ Standalone Stack Deployment**

### **Quick Start**

Deploy the entire Collibra DQ Standalone stack:

```bash
# Set required environment variables
export COLLIBRA_DQ_ADMIN_PASSWORD="<secure-password>"
export COLLIBRA_DQ_LICENSE_KEY="<license-key>"

# Optional: Package uploads are automatically optimized (prevents re-uploads)
# To force a re-upload when updating the package, temporarily set this to false or use terraform taint
export COLLIBRA_DQ_SKIP_PACKAGE_UPLOAD=true

# Deploy Collibra DQ stack
./deploy-stack.sh collibra-dq dev

# For production
./deploy-stack.sh collibra-dq prod
```

**What gets deployed:**
1. Bootstrap (if missing)
2. VPC and VPC Endpoints (reused if exists)
3. Collibra DQ Security Group
4. RDS Security Group
5. RDS PostgreSQL Database
6. Package Upload to S3 (automatically optimized - prevents re-uploads)
7. EC2 Instance with Collibra DQ (includes PostgreSQL client for testing)
8. ALB Security Group
9. Application Load Balancer (HTTP by default, HTTPS when certificate provided)
10. Target Group Attachment

**Package Upload Optimization:**
- Package uploads are automatically optimized - Terraform ignores file content changes to prevent unnecessary re-uploads
- The S3 object resource remains in state and won't be destroyed
- **To force a re-upload** (e.g., when updating the package file):
  - Temporarily set `COLLIBRA_DQ_SKIP_PACKAGE_UPLOAD=false` and run apply, or
  - Use `terraform taint` on the S3 object resource
- Saves 20+ minutes on redeployments by avoiding large file uploads

**Recent Improvements:**
- ✅ PostgreSQL client (`psql`) automatically installed for RDS testing
- ✅ Health check accepts HTTP 200 and 302 (redirect) responses
- ✅ HTTPS support (conditional - enabled when ACM certificate provided)
- ✅ Automatic package structure detection (handles `owl/` subdirectory)
- ✅ Improved error handling and deployment script reliability
- ✅ RDS connectivity testing helper script

### **Environment Variables**

**Required:**
```bash
export COLLIBRA_DQ_ADMIN_PASSWORD="<secure-password>"  # Must meet password policy
export COLLIBRA_DQ_LICENSE_KEY="<license-key>"
```

**Optional:**
```bash
export COLLIBRA_DQ_LICENSE_NAME="collibra-partners"     # Defaults to this
export COLLIBRA_DQ_OWL_BASE="/opt/collibra-dq"          # Defaults to this
export COLLIBRA_DQ_SPARK_PACKAGE="spark-3.5.6-bin-hadoop3.tgz"
export COLLIBRA_DQ_PACKAGE_FILENAME="dq-2025.11-SPARK356-JDK17-package-full.tar"
export COLLIBRA_DQ_SKIP_PACKAGE_UPLOAD="true"           # Optional - uploads are automatically optimized

# HTTPS Configuration (optional)
export COLLIBRA_DQ_ACM_CERTIFICATE_ARN="arn:aws:acm:..."  # Enable HTTPS when set
export COLLIBRA_DQ_DOMAIN_NAME="collibra-dq-dev.example.com"  # Optional domain name
```

### **Package File**

Place the Collibra DQ installation package in:
```
packages/collibra-dq/<package-filename>
```

The deployment script will automatically upload it to S3 if found locally.

### **Destroy Collibra DQ Stack**

```bash
# Destroy Collibra DQ stack (keeps shared resources)
./destroy-stack.sh collibra-dq dev

# Destroy bootstrap (only after both stacks are destroyed)
./destroy-stack.sh collibra-dq dev --destroy-bootstrap
```

**Warning**: Destroying the stack will delete the RDS database and all Collibra DQ data!

### **Testing and Verification**

After deployment, test all components:

```bash
# Comprehensive test
./scripts/test-collibra-dq-deployment.sh dev

# Quick status check
./scripts/utils/check-deployment-status.sh dev

# Test RDS connection (via SSM)
cd env/dev/eu-west-1/addons/collibra-dq-standalone
INSTANCE_ID=$(terragrunt output -raw instance_id)
aws ssm start-session --target $INSTANCE_ID --region eu-west-1
# Then run: /usr/local/bin/test-rds-connection.sh
```

### **HTTPS Configuration**

By default, the ALB uses HTTP for dev/testing. To enable HTTPS:

1. Request an ACM certificate for your domain
2. Set `COLLIBRA_DQ_ACM_CERTIFICATE_ARN` environment variable
3. Redeploy the ALB - HTTPS will be automatically enabled

When HTTPS is enabled:
- HTTPS listener on port 443 with TLS termination
- HTTP automatically redirects to HTTPS (301 redirect)
- TLS 1.3 security policy

### **Scaling**

**Vertical Scaling (Scale Up)** - Easiest:
- Update `instance_type` in `terragrunt.hcl` (e.g., `m5.large` → `m5.xlarge`)
- Redeploy: `terragrunt apply`

**Horizontal Scaling (Scale Out)** - For HA:
- Requires Auto Scaling Group implementation
- See detailed documentation for architecture changes

### **Detailed Documentation**

For detailed Collibra DQ documentation, see: [env/dev/eu-west-1/addons/collibra-dq-standalone/README.md](env/dev/eu-west-1/addons/collibra-dq-standalone/README.md)


## **Upgrading Soda Agent**

### **Overview**
The Soda Agent is deployed as a Helm chart. To take advantage of new features and improvements, you can upgrade to newer versions. Upgrades use Kubernetes' default `RollingUpdate` strategy, so there is **no downtime** associated with upgrading.

### **Version Information**

**Latest Available Version**: `1.3.14` (released January 20, 2026)
- **ArtifactHub**: https://artifacthub.io/packages/helm/soda-agent/soda-agent
- **Recent Versions**:
  - `1.3.14` (January 20, 2026)
  - `1.3.13` (January 7, 2026)
  - `1.3.12` (December 30, 2025)

**Current Deployment**: `1.3.13` (deployed January 24, 2026)
- **App Version**: `1.13.1`
- **Status**: Successfully upgraded from `1.2.4` to `1.3.13`
- **Agent Status**: ✅ Operational and processing instructions successfully

**Note**: The current configuration uses `chart_version = "1.3.13"` (pinned version) for both dev and prod environments. This ensures consistent deployments across environments.

### **Finding Current Version and Upgrade Information**

1. **Check Current Deployment**:
   ```bash
   # List Helm releases to see current version
   helm list -n soda-agent
   
   # Example output:
   # NAME        NAMESPACE   REVISION   CHART              APP VERSION
   # soda-agent  soda-agent  1          soda-agent-1.2.4  1.12.8
   
   # Get current values (including API keys)
   helm get values -n soda-agent soda-agent
   ```

2. **Check Available Versions**:
   ```bash
   # Update Helm repository
   helm repo update soda-agent
   
   # Search for latest version
   helm search repo soda-agent/soda-agent --versions
   
   # Or search ArtifactHub
   helm search hub soda-agent
   
   # Or visit: https://artifacthub.io/packages/helm/soda-agent/soda-agent
   ```

3. **Verify Kubernetes Context**:
   ```bash
   # Check which cluster you're accessing
   kubectl config get-contexts
   
   # Switch context if needed
   kubectl config use-context <cluster-name>
   ```

### **Upgrading via Terraform/Terragrunt (Recommended)**

The recommended way to upgrade is through Terraform/Terragrunt, which ensures configuration consistency:

1. **Update Chart Version**:
   
   **Option A: Pin to Latest Version** (Recommended for stability):
   ```hcl
   # In env/*/eu-west-1/addons/soda-agent/terragrunt.hcl
   chart_version = "1.3.14"  # Pin to latest stable version
   ```
   
   **Option B: Use Latest Available** (Gets newest on each apply):
   ```hcl
   # In env/*/eu-west-1/addons/soda-agent/terragrunt.hcl
   chart_version = ""  # Empty = use latest available at deployment time
   ```
   
   **Current Configuration**: Uses `chart_version = "1.3.13"` (Option A - pinned version)
   
   **Recommendation**: Pinned versions are recommended for production environments to ensure consistent deployments. Both dev and prod are currently pinned to `1.3.13`.

2. **Apply Changes**:
   ```bash
   cd env/dev/eu-west-1/addons/soda-agent
   terragrunt plan   # Review changes (should show chart version update)
   terragrunt apply  # Apply upgrade
   ```

   **Example: Upgrading from 1.2.4 to 1.3.14**:
   ```bash
   # 1. Update chart_version in terragrunt.hcl
   # chart_version = "1.3.14"
   
   # 2. Review the plan
   cd env/dev/eu-west-1/addons/soda-agent
   terragrunt plan
   
   # 3. Apply the upgrade (no downtime - RollingUpdate)
   terragrunt apply
   
   # 4. Verify the upgrade
   helm list -n soda-agent
   kubectl get pods -n soda-agent
   ```

3. **Verify Upgrade**:
   ```bash
   # Check pod status
   kubectl get pods -n soda-agent
   
   # Check logs
   kubectl logs -n soda-agent -l app.kubernetes.io/name=soda-agent --tail=50
   
   # Verify in Soda Cloud UI
   # Navigate to: Your Avatar > Agents
   ```

### **Upgrading via Helm CLI (Alternative)**

If you need to upgrade directly via Helm (not recommended for infrastructure managed by Terraform):

```bash
helm upgrade soda-agent soda-agent/soda-agent \
  --set soda.agent.name=datashift-dev-eu-west-1-agent \
  --set soda.cloud.endpoint=https://cloud.soda.io \
  --set soda.apikey.id=*** \
  --set soda.apikey.secret=**** \
  --set soda.agent.logFormat=raw \
  --set soda.agent.loglevel=INFO \
  --namespace soda-agent
```

**Note**: If using Terraform, prefer `terragrunt apply` to maintain state consistency.

### **Version-Specific Upgrade Notes**

#### **Upgrading to 1.3.x from 1.2.x**

**Current Status**: ✅ Successfully upgraded from `1.2.4` to `1.3.13` (January 24, 2026)

**Key Changes in 1.3.x**:
- Continued improvements to instruction handling
- Enhanced error handling and logging
- Performance optimizations
- Bug fixes (including fixes for instruction fetching issues)
- Improved agent registration and state management

**Upgrade Experience**:
- **Initial Attempt**: Direct upgrade from `1.2.4` to `1.3.13` encountered agent ID mismatch issues
- **Resolution**: Performed fresh install (deleted namespace and redeployed) which resolved the issue
- **Result**: Agent successfully registered with new ID and is processing instructions correctly
- **Status**: ✅ Operational with version `1.3.13`

**Lessons Learned**:
- If upgrading encounters agent ID issues, a fresh install may be necessary
- Fresh install process: `helm uninstall`, `kubectl delete namespace`, then redeploy
- New agent will register with a fresh ID in Soda Cloud
- All previous agent state is cleared, allowing clean registration

**Current Configuration**:
- Chart version: `1.3.13` (pinned in both dev and prod)
- App version: `1.13.1`
- Agent status: ✅ Running and processing instructions successfully

### **Upgrading from 1.1.x to 1.2.x+ (Breaking Changes)**

Starting from version 1.2.0, all images are distributed using Soda's private container registry. Important changes:

#### **1. Image Registry Authentication**

**Option A: Use Existing API Keys (Default) - ✅ Current Configuration**
- **Implementation**: Automatically uses main API keys for image registry if separate credentials are not provided
- **Configuration**: Uses locals with fallback logic in `env/*/eu-west-1/addons/soda-agent/terragrunt.hcl`:
  ```hcl
  locals {
    api_key_id     = get_env("SODA_API_KEY_ID", "")
    api_key_secret = get_env("SODA_API_KEY_SECRET", "")
    
    # Fallback to main API keys if image credentials not provided
    image_credentials_id     = get_env("SODA_IMAGE_APIKEY_ID", local.api_key_id)
    image_credentials_secret = get_env("SODA_IMAGE_APIKEY_SECRET", local.api_key_secret)
  }
  ```
- **Benefits**: Simplifies configuration - no need to set separate image credentials unless required
- **Status**: ✅ Working correctly in both dev and prod environments

**Option B: Use Separate Image Registry Credentials**
- **Configuration**: Set `SODA_IMAGE_APIKEY_ID` and `SODA_IMAGE_APIKEY_SECRET` environment variables
- **Behavior**: If set, these override the fallback and are used exclusively for image registry authentication
- **Use Case**: When you want to use different credentials for image registry vs Soda Cloud API

#### **2. Image Pull Secrets Configuration**

- ✅ **Current Configuration**: Already compatible
- The module uses `existingImagePullSecrets` (correct for 1.2.x+)
- Configuration in: `module/application/helm/soda-agent/main.tf` (line 158)
- If you have an existing secret, set `existing_image_pull_secret` in Terragrunt config

#### **3. Cloud Region Property (New in 1.2.x)**

**Current Status**: ⚠️ **Not yet implemented** - using `cloud_endpoint` instead

The new `soda.cloud.region` property (values: `"eu"` or `"us"`) automatically sets the correct endpoint and registry. Currently, the module uses:
- `soda.cloud.endpoint` (explicit endpoint URL)
- `SODA_CLOUD_REGION` environment variable (for determining endpoint)

**Future Enhancement**: The module could be updated to use `soda.cloud.region` instead of `soda.cloud.endpoint` for better compatibility with 1.2.x+ charts.

**Current Workaround**: The existing `cloud_endpoint` configuration works correctly with 1.2.x+ charts.

#### **4. Scan Launcher Naming**

- ⚠️ **Note**: If you have custom `scanlauncher` configuration, it should be renamed to `scanLauncher` (camelCase)
- **Current Configuration**: No custom scan launcher configuration, so no changes needed

### **Upgrade Checklist**

Before upgrading:
- [ ] Verify current version: `helm list -n soda-agent`
- [ ] Check available versions: `helm search repo soda-agent/soda-agent --versions` or visit [ArtifactHub](https://artifacthub.io/packages/helm/soda-agent/soda-agent)
- [ ] Review release notes for breaking changes (especially when upgrading major/minor versions)
- [ ] Backup current values: `helm get values -n soda-agent soda-agent > values-backup.yaml`
- [ ] Verify API keys are set: `echo $SODA_API_KEY_ID`
- [ ] Verify image credentials (if using separate): `echo $SODA_IMAGE_APIKEY_ID`
- [ ] Check Kubernetes context: `kubectl config get-contexts`
- [ ] For production: Consider testing upgrade in dev environment first

After upgrading:
- [ ] Verify pod status: `kubectl get pods -n soda-agent` (should show Running)
- [ ] Check logs for errors: `kubectl logs -n soda-agent -l app.kubernetes.io/name=soda-agent --tail=50`
- [ ] Verify new chart version: `helm list -n soda-agent` (should show updated version)
- [ ] Verify agent appears in Soda Cloud UI (agent should be online)
- [ ] Test a scan to ensure functionality
- [ ] Monitor for any new errors or warnings in logs

### **Rollback Procedure**

If an upgrade causes issues:

**Via Terraform**:
```bash
cd env/dev/eu-west-1/addons/soda-agent
# Revert chart_version in terragrunt.hcl to previous version
terragrunt apply
```

**Via Helm**:
```bash
# List revisions
helm history soda-agent -n soda-agent

# Rollback to previous revision
helm rollback soda-agent -n soda-agent

# Or rollback to specific revision
helm rollback soda-agent <revision-number> -n soda-agent
```

### **Fresh Install Process (January 2025)**

If you encounter agent ID issues or need to start completely fresh:

1. **Uninstall Helm Release**:
   ```bash
   helm uninstall soda-agent -n soda-agent
   ```

2. **Delete Namespace** (removes all secrets and state):
   ```bash
   kubectl delete namespace soda-agent
   ```

3. **Verify Cleanup**:
   ```bash
   kubectl get namespace soda-agent  # Should show "NotFound"
   ```

4. **Update Configuration**:
   - Ensure `create_namespace = true` in Terragrunt config
   - Verify API keys are set in environment variables
   - Check chart version is set correctly

5. **Redeploy**:
   ```bash
   cd env/dev/eu-west-1/addons/soda-agent
   terragrunt apply
   ```

6. **Verify New Agent**:
   - Agent will register with a new ID in Soda Cloud
   - Check logs: `kubectl logs -n soda-agent -l app.kubernetes.io/name=soda-agent`
   - Verify in Soda Cloud UI: Your Avatar > Agents

**Note**: Fresh install clears all previous agent state, including stored agent ID. The agent will register as a new agent in Soda Cloud.

## **Notes**

- **Bootstrap**: Set to `skip = true` by default. Run `./deploy-bootstrap.sh <env>` for new environments.
- **State Management**: Uses S3 backend with DynamoDB locking (created by bootstrap).
  - S3 versioning and lifecycle policies for cost optimization
  - DynamoDB point-in-time recovery for disaster recovery
  - Both resources use consistent tagging from parent configuration
- **Provider Versions**: Pinned to specific versions for stability.
- **Tags**: Consistent tagging strategy across all resources.
- **Security**: VPC endpoints for private communication, minimal public access.
- **Namespace Management**: Soda Agent namespace is now created explicitly by Terraform for better control.

---

### **Recent Updates (January 28, 2025)**

- **Collibra DQ Standalone**: Added standalone EC2-based deployment option for Collibra DQ
  - Automated package upload to S3
  - EC2 instance with automated installation
  - Application Load Balancer for web access
  - Support for both dev and prod environments
  - Production-ready configuration (larger instances, deletion protection, logging)
- **Soda Agent Upgrade**: Successfully upgraded from `1.2.4` to `1.3.13`
- **Image Credentials Configuration**: Implemented automatic fallback to main API keys for image registry authentication
- **Fresh Install Process**: Documented procedure for clean agent reinstallation
- **Bug Resolution**: Resolved NullPointerException instruction fetching bug via upgrade
- **Production Configuration**: Updated prod environment to match dev configuration
- **Documentation**: Enhanced upgrade and troubleshooting sections
- **Collibra DQ Integration**: Added Collibra DQ Helm module and RDS PostgreSQL database architecture
- **Dependency Management**: Removed hardcodings and standardized dependency usage across all terragrunt files

### **Future Enhancements**

- **Automated Testing**: Integration tests for infrastructure deployments
- **Monitoring & Alerting**: Enhanced observability and alerting for deployed components

---

**Last Updated**: January 29, 2026  
**Terraform Version**: >= 1.6  
**Terragrunt Version**: >= 0.54  
**AWS Provider**: >= 5.0, < 6.0  
**Soda Agent Chart Version**: 1.3.13 (pinned)
