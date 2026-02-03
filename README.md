# DQ-Infrastructures

<<<<<<< HEAD
Infrastructure as Code (IaC) project for deploying data quality tools on AWS using Terraform and Terragrunt. This project manages two independent application stacks: **Soda Agent** (containerized on EKS) and **Collibra DQ** (standalone EC2 deployment).

## Table of Contents

- [Overview](#overview)
- [Package Contents (Root)](#package-contents-root)
- [Project Structure](#project-structure)
- [Architecture & Design Decisions](#architecture--design-decisions)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Deployment Guide](#deployment-guide)
- [Components](#components)
- [Environment Variables](#environment-variables)
- [Package Deployment](#package-deployment)
- [Troubleshooting](#troubleshooting)
- [Security Notes](#security-notes)
- [Contributing](#contributing)
- [Additional Documentation](#additional-documentation)

## Overview

This repository contains Terraform modules and Terragrunt configurations for deploying:

1. **Soda Agent Stack**: Data quality monitoring tool deployed on Amazon EKS (Kubernetes) using Helm
2. **Collibra DQ Stack**: Data quality platform deployed as a standalone application on EC2 with Application Load Balancer (ALB) and RDS PostgreSQL

Both stacks are **completely independent** with separate VPCs, network resources, and state management. This design eliminates cross-stack dependencies and simplifies deployment/destruction operations.

## Package Contents (Root)

Root-level files included in this production-ready package:

| File | Purpose |
|------|---------|
| **deploy-stack.sh** | Main deployment orchestrator. Deploys bootstrap (if needed), then stack modules in order. Supports `--skip-addons` for core-only deployment. |
| **destroy-stack.sh** | Stack destruction in reverse order. Options: `--destroy-bootstrap` to also remove state backend. Prompts for confirmation. |
| **deploy-bootstrap.sh** | Bootstrap-only: creates S3 state bucket and DynamoDB lock table. Used automatically by deploy-stack.sh when needed. |
| **destroy-bootstrap.sh** | Destroys bootstrap (S3 + DynamoDB). Requires typing `DESTROY BOOTSTRAP` to confirm. |
| **README.md** | This file: overview, structure, prerequisites, quick start, deployment guide, env vars, troubleshooting. |
| **.gitignore** | Excludes Terraform/Terragrunt caches, state, generated files, secrets (`scripts/set-env.sh`), and large packages. |
| **.pre-commit-config.yaml** | Pre-commit hooks: trailing whitespace, YAML/JSON checks, Terraform fmt/validate/tflint, detect-private-key. Run `pre-commit install` then `pre-commit run --all-files` before shipping. |

**Required for deployment:** Copy `scripts/set-env.example.sh` to `scripts/set-env.sh`, fill in values, and `source scripts/set-env.sh` before running deploy/destroy. See [Environment Variables](#environment-variables).

**Before you ship:** Ensure `scripts/set-env.example.sh` exists (template for secrets); run `pre-commit run --all-files` to catch formatting/lint issues; do not commit `scripts/set-env.sh` or any file containing secrets (they are git-ignored); run a full deploy/destroy test if possible; and confirm no secrets are in the repo. See [CONTRIBUTING.md](CONTRIBUTING.md) for the release checklist.

## Project Structure

```
DQ-Infrastructures/
├── env/                              # Terragrunt configuration hierarchy
│   ├── root.hcl                     # Global config: validations, remote state, shared inputs
│   ├── env.hcl                      # Environment definitions (dev/prod) and account mappings
│   ├── common.hcl                   # Common provider/backend generation blocks
│   ├── region.hcl                    # Region-specific configuration (tags, state naming)
│   └── stack/                       # Live infrastructure configurations (what gets deployed)
│       ├── bootstrap/                # Shared: Terraform state backend (S3 + DynamoDB)
│       ├── soda-agent/              # Independent Soda Agent stack
│       │   ├── network/
│       │   │   ├── vpc/              # VPC, subnets, routing, NAT
│       │   │   └── vpc-endpoints/    # VPC endpoints for AWS services
│       │   ├── ops/
│       │   │   ├── sg-ops/           # Security groups for ops instances
│       │   │   └── ec2-ops/          # Ops EC2 instance (SSM access, debugging)
│       │   ├── eks/
│       │   │   ├── terragrunt.hcl    # EKS cluster + managed node groups
│       │   │   └── ops-ec2-eks-access/ # IAM/RBAC for ops → EKS access
│       │   └── addons/
│       │       └── soda-agent/      # Soda Agent Helm chart deployment
│       └── collibra-dq/              # Independent Collibra DQ stack
│           ├── network/
│           │   ├── vpc/              # VPC, subnets, routing, NAT
│           │   └── vpc-endpoints/   # VPC endpoints (SSM, S3)
│           ├── database/
│           │   └── rds-collibra-dq/
│           │       ├── sg-rds/       # RDS security group
│           │       └── rds/          # PostgreSQL database
│           └── addons/
│               └── collibra-dq-standalone/
│                   ├── package-upload/    # S3 package upload module
│                   ├── sg-collibra-dq/    # EC2 security group
│                   ├── terragrunt.hcl     # EC2 instance
│                   └── alb/
│                       ├── sg-alb/        # ALB security group
│                       ├── terragrunt.hcl # Application Load Balancer
│                       └── target-group-attachment/ # EC2 → ALB attachment
│
├── module/                           # Reusable Terraform modules
│   ├── application/                  # Application-specific modules
│   │   ├── collibra-dq-standalone/  # Collibra DQ EC2 deployment
│   │   └── helm/                     # Helm chart deployment (Soda Agent)
│   ├── compute/                      # Compute resources
│   │   ├── ec2/ops/                  # Ops EC2 instance module
│   │   └── eks/cluster/              # EKS cluster module
│   ├── database/
│   │   └── rds/postgresql/           # RDS PostgreSQL module
│   ├── network/
│   │   ├── alb/                      # Application Load Balancer modules
│   │   ├── vpc/                      # VPC module
│   │   └── vpc-endpoints/            # VPC endpoints module
│   ├── security/
│   │   ├── iam/                      # IAM roles/policies
│   │   └── security-group/          # Security group modules
│   └── storage/
│       └── s3-package/               # S3 package storage module
│
├── packages/                         # Large binary artifacts (git-ignored)
│   └── collibra-dq/                  # Collibra DQ installation package
│
├── scripts/                          # Utility and validation scripts
│   ├── set-env.example.sh            # Environment variable template
│   ├── validate-env.sh               # Environment validation
│   ├── verify-soda-keys.sh           # Soda Agent key sanity check
│   ├── test-terragrunt.sh            # Terragrunt config validation (stack-first)
│   └── test-modules.sh               # Terraform module validation
│
├── deploy-stack.sh                   # Main deployment orchestrator
├── destroy-stack.sh                  # Main destruction orchestrator
├── deploy-bootstrap.sh              # Bootstrap-only deployment
├── destroy-bootstrap.sh             # Bootstrap-only destruction
└── README.md                         # This file
```

### Key Directories Explained

- **`env/stack/`**: "Live" configurations that define what actually gets deployed. Each subdirectory is a separate Terraform state boundary.
- **`module/`**: Reusable Terraform modules that encapsulate infrastructure patterns. These are called by the live configs in `env/stack/`.
- **`packages/`**: Large binary files (e.g., Collibra DQ installer) that are git-ignored but required for deployment.
- **`scripts/`**: Helper scripts for validation, testing, and deployment orchestration.

## Architecture & Design Decisions

### 1. Independent Stacks Architecture

**Decision**: Each application stack (`soda-agent` and `collibra-dq`) has its own completely independent VPC and network resources.

**Rationale**:
- **Eliminates dependency conflicts**: No shared resources means no cross-stack dependency issues
- **Simplifies destroy operations**: Each stack can be destroyed independently without affecting the other
- **Enables parallel development**: Teams can work on different stacks without coordination
- **Reduces blast radius**: Issues in one stack don't affect the other
- **Follows microservices principles**: Each application is self-contained

**Trade-offs**:
- Slightly higher AWS costs (separate VPCs, NAT gateways)
- More network resources to manage
- **Accepted trade-off**: The operational simplicity and safety outweigh the cost

### 2. Terragrunt for Orchestration

**Decision**: Use Terragrunt instead of pure Terraform for managing the infrastructure.

**Rationale**:
- **DRY (Don't Repeat Yourself)**: Shared configuration in `env/root.hcl`, `env/common.hcl`, `env/region.hcl`
- **Dependency management**: Terragrunt's `dependency` blocks automatically handle module ordering
- **Remote state management**: Automatic S3 backend configuration per module
- **Environment/region abstraction**: Easy switching between dev/prod and regions
- **Validation**: Built-in environment and account validation

**How it works**:
- Each `env/stack/**/terragrunt.hcl` includes shared configs from `env/`
- Terragrunt automatically configures Terraform backends (S3 + DynamoDB)
- Dependencies are declared explicitly and Terragrunt ensures correct ordering

### 3. Package Upload Orchestration

**Decision**: Collibra DQ package is uploaded to S3 via a separate Terraform module (`package-upload`) before EC2 instance deployment.

**Rationale**:
- **Separation of concerns**: Package management is separate from compute deployment
- **Idempotency**: Package upload can be managed independently (skip re-uploads if needed)
- **Dependency enforcement**: Terragrunt dependency ensures EC2 waits for package upload
- **Flexibility**: Package can be updated without redeploying EC2 instance

**Implementation**:
- `package-upload` module uses `module/storage/s3-package`
- EC2 module declares `dependency "package_upload"` with `skip_outputs = false`
- EC2 uses `dependency.package_upload.outputs.s3_url` in its user data
- Deploy script ensures package-upload completes before EC2 deployment

### 4. Security Group Dependency Ordering

**Decision**: Security groups are deployed in a specific order (ALB SG → EC2 SG → RDS SG) and destroyed in reverse order.

**Rationale**:
- **AWS constraint**: Security groups with ingress rules referencing other security groups cannot be deleted while the referenced SG exists
- **Explicit ordering**: Deploy script enforces correct order to prevent failures
- **Destroy safety**: Destroy script reverses the order to handle dependencies correctly

**Example**:
- Collibra DQ EC2 SG has ingress rule allowing traffic from ALB SG
- Therefore: ALB SG must be created before EC2 SG
- Destroy: EC2 SG must be destroyed before ALB SG

### 5. Single Resource Pattern for S3 Package Upload

**Decision**: S3 package upload module uses a single `aws_s3_object` resource with conditional lifecycle rules instead of multiple resources.

**Rationale**:
- **Best practice**: Avoids state migration issues when toggling `skip_upload_if_exists`
- **Simpler state management**: One resource is easier to manage than conditional resource creation
- **Proper change detection**: Uses Terraform's etag comparison for file changes
- **Flexible lifecycle**: Conditional `ignore_changes` based on `skip_upload_if_exists` variable

### 6. Bootstrap Import-Aware Design

**Decision**: Bootstrap deployment automatically imports existing S3 bucket and DynamoDB table if they exist but state is missing.

**Rationale**:
- **Recovery from state loss**: If Terraform state is lost, infrastructure can be recovered
- **CI/CD friendly**: Handles cases where resources exist but state wasn't committed
- **Safety**: Prevents accidental resource creation when resources already exist

### 7. Mock Outputs for Validation

**Decision**: All Terragrunt dependencies include `mock_outputs` with `mock_outputs_allowed_terraform_commands = ["init", "plan", "validate"]`.

**Rationale**:
- **Validation without full deployment**: Can validate configurations without deploying dependencies
- **CI/CD efficiency**: Validation pipelines don't need full infrastructure
- **Developer experience**: Developers can validate changes locally without deploying
- **Explicit real outputs**: `skip_outputs = false` ensures real outputs are used during `apply`

### 8. Naming Conventions

**Decision**: Consistent naming patterns across all resources.

**Patterns**:
- Resources: `${org}-${env}-${component}` (e.g., `datashift-dev-collibra-dq-standalone`)
- ALB/Target Groups: Shortened with abbreviations (`ds-${env}-dq-${vpc-suffix}`) to meet AWS 32-char limit
- IAM roles: Include VPC suffix to avoid collisions between stacks
- Security groups: `${org}-${env}-${component}-sg`

**Rationale**:
- **Predictability**: Engineers can find resources by name pattern
- **AWS constraints**: Some resources have character limits (ALB names: 32 chars)
- **Collision avoidance**: VPC suffixes prevent name conflicts between stacks

## Prerequisites

### Required Tools

Install these tools locally (and in CI if you run validation there):

| Tool | Purpose | Minimum Version |
|------|---------|----------------|
| **Terraform** | Infrastructure provisioning | >= 1.5.0 |
| **Terragrunt** | Terraform orchestration and DRY config | Latest |
| **AWS CLI** | AWS API access and credential management | v2.x |
| **kubectl** | Kubernetes/EKS access (for Soda Agent stack) | Latest |
| **Helm** | Kubernetes package manager (optional, for debugging) | v3.x |
| **jq** | JSON processing in scripts (optional) | Latest |

### AWS Account Setup

1. **AWS Account**: Access to an AWS account with appropriate permissions
2. **IAM Permissions**: Your AWS credentials need permissions to create:
   - VPC, subnets, route tables, NAT gateways
   - EC2 instances, security groups, IAM roles
   - EKS clusters (for Soda Agent stack)
   - RDS databases (for Collibra DQ stack)
   - S3 buckets, DynamoDB tables
   - Application Load Balancers
   - CloudWatch Logs

3. **AWS Credentials**: Configure one of:
   - AWS Profile: `~/.aws/config` and `~/.aws/credentials`
   - Access Keys: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variables

## Quick Start

### 1. Clone and Setup

```bash
git clone <repository-url>
cd DQ-Infrastructures
```

### 2. Configure Environment Variables

```bash
# Copy the example template
cp scripts/set-env.example.sh scripts/set-env.sh

# Edit with your values
vim scripts/set-env.sh  # or use your preferred editor
```

Required variables in `scripts/set-env.sh`:
- `TF_VAR_environment` (dev or prod)
- `TF_VAR_region` (eu-west-1, us-east-1, or eu-central-1)
- AWS credentials (profile or access keys)
- Application-specific secrets (see [Environment Variables](#environment-variables))

### 3. Source Environment and Deploy

```bash
# Source the environment variables (IMPORTANT: must be in same shell)
source scripts/set-env.sh

# Deploy a stack
./deploy-stack.sh collibra-dq
# or
./deploy-stack.sh soda-agent
```

### 4. Verify Deployment

```bash
# Get ALB URL (Collibra DQ)
cd env/stack/collibra-dq/addons/collibra-dq-standalone/alb
terragrunt output load_balancer_dns_name

# Check EKS cluster (Soda Agent)
cd env/stack/soda-agent/eks
terragrunt output cluster_endpoint
```

## Deployment Guide

### Deployment Phases

Both stacks follow a phased deployment approach where each phase depends on previous phases completing successfully.

#### Collibra DQ Stack Deployment Order

1. **Bootstrap** (shared): Creates S3 bucket for Terraform state and DynamoDB table for state locking
2. **VPC**: Creates VPC, public/private subnets, internet gateway, NAT gateway, route tables
3. **VPC Endpoints**: Creates VPC endpoints for SSM, S3 (required for EC2 to download packages)
4. **ALB Security Group**: Security group for Application Load Balancer
5. **Collibra DQ Security Group**: Security group for EC2 instance (depends on ALB SG)
6. **RDS Security Group**: Security group for PostgreSQL database (allows traffic from EC2 SG)
7. **RDS Database**: PostgreSQL database for Collibra DQ metastore
8. **Package Upload**: Uploads Collibra DQ package from `packages/collibra-dq/` to S3
9. **EC2 Instance**: Deploys EC2 instance with Collibra DQ (waits for package upload via Terragrunt dependency)
10. **Application Load Balancer**: Creates ALB with HTTP listener and target group
11. **Target Group Attachment**: Attaches EC2 instance to ALB target group

#### Soda Agent Stack Deployment Order

1. **Bootstrap** (shared): Same as above
2. **VPC**: Creates VPC and networking (separate from Collibra DQ VPC)
3. **VPC Endpoints**: Creates endpoints for EKS requirements (ECR, STS, CloudWatch Logs, etc.)
4. **Ops Security Group**: Security group for ops EC2 instance
5. **EKS Cluster**: Creates EKS cluster with managed node groups
6. **Ops EC2 Instance**: EC2 instance for operational tasks and EKS access
7. **EKS Access Configuration**: IAM roles and RBAC for ops instance to access EKS
8. **Soda Agent**: Helm chart deployment into EKS cluster

### Deployment Commands

```bash
# Full stack deployment
source scripts/set-env.sh
./deploy-stack.sh collibra-dq
./deploy-stack.sh soda-agent

# Core-only deployment (skip application add-ons)
./deploy-stack.sh collibra-dq --skip-addons
./deploy-stack.sh soda-agent --skip-addons

# Individual module deployment (advanced)
cd env/stack/collibra-dq/network/vpc
terragrunt apply
```

### Destruction

```bash
# Destroy a stack (keeps bootstrap)
source scripts/set-env.sh
./destroy-stack.sh collibra-dq
# (interactive) type: yes

# Destroy including bootstrap (DANGEROUS: deletes all Terraform state)
./destroy-stack.sh collibra-dq --destroy-bootstrap
# (interactive) type:
#   - yes
#   - DESTROY BOOTSTRAP
```

**Important**: Destroy operations happen in reverse order of deployment. The scripts handle dependency ordering automatically. Both deploy and destroy set `TF_INPUT=0` and `TG_INPUT=0` so they run non-interactively (suitable for CI, background runs, or piped input).

## Components

### Bootstrap (Shared)

**Location**: `env/stack/bootstrap/`

**Purpose**: Creates the Terraform remote state backend that all other modules depend on.

**Resources**:
- S3 bucket for storing Terraform state files
- DynamoDB table for state locking (prevents concurrent modifications)

**Design Note**: Shared by both stacks to avoid duplicating state management infrastructure. The bootstrap is import-aware: if S3 bucket and DynamoDB table exist but state is missing, they are automatically imported.

### Soda Agent Stack

**Purpose**: Deploys Soda Agent (data quality monitoring) on Amazon EKS.

**Key Components**:
- **VPC**: Isolated network with public/private subnets
- **VPC Endpoints**: Private connectivity to AWS services (ECR, STS, CloudWatch Logs, S3)
- **EKS Cluster**: Managed Kubernetes cluster with node groups
- **Ops EC2**: Bastion-like instance for operational access (via SSM Session Manager)
- **Soda Agent**: Helm chart deployment into EKS

**Access**:
- EKS cluster: `kubectl` via `aws eks update-kubeconfig`
- Ops instance: AWS Systems Manager Session Manager (no SSH)

### Collibra DQ Stack

**Purpose**: Deploys Collibra DQ (data quality platform) as a standalone application.

**Key Components**:
- **VPC**: Isolated network with public/private subnets
- **VPC Endpoints**: Private connectivity to S3 (for package download) and SSM
- **RDS PostgreSQL**: Database for Collibra DQ metastore
- **EC2 Instance**: Application server running Collibra DQ
- **Application Load Balancer**: Internet-facing ALB for web UI access
- **Package Upload**: S3 bucket for storing Collibra DQ installation package

**Architecture Flow**:
1. Package is uploaded to S3 during deployment
2. EC2 instance downloads package from S3 during boot (user data script)
3. Collibra DQ installs and connects to RDS database
4. ALB routes traffic to EC2 instance (port 9000 for web UI; health checks use the same traffic port)

**Access**:
- Web UI: Via ALB DNS name (HTTP on port 80)
- EC2 instance: AWS Systems Manager Session Manager

## Environment Variables

### Required for All Deployments

| Variable | Description | Example |
|----------|-------------|---------|
| `TF_VAR_environment` | Environment identifier | `dev` or `prod` |
| `TF_VAR_region` | AWS region | `eu-west-1`, `us-east-1`, `eu-central-1` |
| `AWS_PROFILE` OR | AWS profile name | `my-aws-profile` |
| `AWS_ACCESS_KEY_ID` + | AWS access key ID | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret access key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |

**Note**: If using access keys, ensure `AWS_PROFILE` is unset (or unset it in `scripts/set-env.sh`).

### Collibra DQ Stack Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `COLLIBRA_DQ_ADMIN_PASSWORD` | ✅ Yes | - | Admin user password for Collibra DQ |
| `COLLIBRA_DQ_LICENSE_KEY` | ✅ Yes | - | Collibra DQ license key |
| `COLLIBRA_DQ_PACKAGE_FILENAME` | ❌ No | `dq-2025.11-SPARK356-JDK17-package-full.tar` | Package filename in `packages/collibra-dq/` |
| `COLLIBRA_DQ_PACKAGE_URL` | ❌ No | Auto-generated from S3 | Override S3 URL (usually not needed) |
| `COLLIBRA_DQ_OWL_BASE` | ❌ No | `/opt/collibra-dq` | Installation directory |
| `COLLIBRA_DQ_SPARK_PACKAGE` | ❌ No | `spark-3.5.6-bin-hadoop3.tgz` | Spark package name |
| `COLLIBRA_DQ_LICENSE_NAME` | ❌ No | `collibra-partners` | License name |
| `COLLIBRA_DQ_RDS_PASSWORD` | ❌ No | Auto-generated | RDS database password |
| `COLLIBRA_DQ_ENABLE_S3_ACCELERATION` | ❌ No | `false` | Enable S3 Transfer Acceleration |
| `COLLIBRA_DQ_SKIP_PACKAGE_UPLOAD` | ❌ No | `false` | Skip re-upload if package exists in S3 |

### Soda Agent Stack Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SODA_API_KEY_ID` | ✅ Yes | - | Soda Cloud API key ID (from **Data Sources → Agents → New Soda Agent** only) |
| `SODA_API_KEY_SECRET` | ✅ Yes | - | Soda Cloud API key secret |
| `SODA_CLOUD_REGION` | ❌ No | `eu` | Soda Cloud region (`eu` or `us`) |
| `SODA_LOG_LEVEL` | ❌ No | `INFO` | Log level |
| `SODA_LOG_FORMAT` | ❌ No | `raw` | Log format |
| `SODA_AGENT_ID` | ❌ No | (unset) | Existing agent ID from Soda Cloud (Agents → agent → ID in URL). Set when redeploying and the agent name is already registered to avoid CrashLoopBackOff. |
| `SODA_IMAGE_APIKEY_ID` | ❌ No | `SODA_API_KEY_ID` | Image registry API key (only if Soda gave separate registry credentials) |
| `SODA_IMAGE_APIKEY_SECRET` | ❌ No | `SODA_API_KEY_SECRET` | Image registry API key secret |

### Optional Safety Override

| Variable | Description | Use Case |
|----------|-------------|----------|
| `TG_EXPECTED_ACCOUNT_ID` | Override expected AWS account ID | CI/CD pipelines (avoids committing account IDs) |

**Template**: Copy `scripts/set-env.example.sh` to `scripts/set-env.sh` and fill in your values.

## Package Deployment

### Collibra DQ Package Management

The Collibra DQ package (~2.5GB) is uploaded to S3 during deployment via the `package-upload` module. The package is then downloaded by the EC2 instance during boot.

**Package Location**: `packages/collibra-dq/dq-2025.11-SPARK356-JDK17-package-full.tar`

**S3 Upload Process**:
1. Package is uploaded to S3 bucket: `${ACCOUNT_ID}-datashift-${ENV}-packages-${REGION}/collibra-dq/`
2. Upload happens automatically during `package-upload` module deployment
3. EC2 instance downloads from S3 using IAM role permissions
4. Package upload can be skipped if already exists: Set `COLLIBRA_DQ_SKIP_PACKAGE_UPLOAD=true`

**Upload Time**: ~10-15 minutes for 2.5GB package (depends on network speed)

**Optimization Tips**:
- Use `COLLIBRA_DQ_SKIP_PACKAGE_UPLOAD=true` to skip re-uploads if package hasn't changed
- Enable S3 Transfer Acceleration: `COLLIBRA_DQ_ENABLE_S3_ACCELERATION=true` (adds cost but faster)
- Monitor upload progress: Check CloudWatch metrics or S3 console

**Manual Upload** (if Terraform upload fails):
```bash
BUCKET_NAME="$(aws sts get-caller-identity --query Account --output text)-datashift-${TF_VAR_environment}-packages-${TF_VAR_region}"

aws s3 cp \
  "packages/collibra-dq/dq-2025.11-SPARK356-JDK17-package-full.tar" \
  "s3://${BUCKET_NAME}/collibra-dq/dq-2025.11-SPARK356-JDK17-package-full.tar" \
  --region $TF_VAR_region

# Then update Terraform state
cd env/stack/collibra-dq/addons/collibra-dq-standalone/package-upload
terragrunt apply --auto-approve
```

## Troubleshooting

### Common Issues

#### AWS Credentials Not Working

**Symptom**: `Error finding AWS credentials` or authentication failures.

**Solution**:
1. Ensure you've sourced `scripts/set-env.sh` in the **same shell** where you run deploy/destroy
2. If using access keys, verify `AWS_PROFILE` is unset: `unset AWS_PROFILE`
3. Test credentials: `aws sts get-caller-identity`

#### EC2 Instance Unhealthy After Deployment

**Symptoms**:
- Deployment script reports success
- All infrastructure created (VPC, RDS, EC2, ALB, etc.)
- ALB target health shows "unhealthy"
- Collibra DQ web interface not accessible

**Root Cause**: Usually the Collibra DQ package was not uploaded to S3 or EC2 installation failed.

**Diagnosis Steps**:

1. **Check ALB target health:**
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn $(cd env/stack/collibra-dq/addons/collibra-dq-standalone/alb && terragrunt output -raw target_group_arns | jq -r '.["collibra-dq"]') \
     --region $TF_VAR_region
   ```

2. **Check if package is in S3:**
   ```bash
   aws s3 ls s3://$(aws sts get-caller-identity --query Account --output text)-datashift-${TF_VAR_environment}-packages-${TF_VAR_region}/collibra-dq/ --human-readable
   ```
   
   Expected: You should see `dq-2025.11-SPARK356-JDK17-package-full.tar` (~2.5 GB)
   
   If missing: Package upload failed or didn't complete.

3. **Check EC2 installation logs:**
   ```bash
   # Get instance ID
   INSTANCE_ID=$(cd env/stack/collibra-dq/addons/collibra-dq-standalone && terragrunt output -raw instance_id)
   
   # Connect via SSM
   aws ssm start-session --target $INSTANCE_ID --region $TF_VAR_region
   
   # Inside the instance:
   tail -100 /var/log/collibra-dq-install.log
   ```
   
   Look for: `fatal error: An error occurred (404) when calling the HeadObject operation: Key "collibra-dq/dq-2025.11-SPARK356-JDK17-package-full.tar" does not exist`

**Resolution**:

1. **Upload the package to S3:**
   ```bash
   BUCKET_NAME="$(aws sts get-caller-identity --query Account --output text)-datashift-${TF_VAR_environment}-packages-${TF_VAR_region}"
   
   aws s3 cp \
     "packages/collibra-dq/dq-2025.11-SPARK356-JDK17-package-full.tar" \
     "s3://${BUCKET_NAME}/collibra-dq/dq-2025.11-SPARK356-JDK17-package-full.tar" \
     --region $TF_VAR_region
   ```

2. **Update package-upload state:**
   ```bash
   cd env/stack/collibra-dq/addons/collibra-dq-standalone/package-upload
   terragrunt apply --auto-approve
   ```

3. **Recreate the EC2 instance:**
   ```bash
   cd env/stack/collibra-dq/addons/collibra-dq-standalone
   terragrunt destroy --auto-approve
   terragrunt apply --auto-approve
   ```

4. **Monitor the installation:**
   
   Installation takes 10-15 minutes. Monitor progress:
   ```bash
   INSTANCE_ID=$(terragrunt output -raw instance_id)
   
   # Connect
   aws ssm start-session --target $INSTANCE_ID --region $TF_VAR_region
   
   # Inside instance
   tail -f /var/log/collibra-dq-install.log
   ```

5. **Verify health:**
   
   Once installation completes, check target health:
   ```bash
   cd env/stack/collibra-dq/addons/collibra-dq-standalone/alb
   
   TARGET_GROUP_ARN=$(terragrunt output -json target_group_arns | jq -r '.["collibra-dq"]')
   
   aws elbv2 describe-target-health \
     --target-group-arn "$TARGET_GROUP_ARN" \
     --region $TF_VAR_region
   ```
   
   Expected: `"State": "healthy"`

#### Package Upload Fails (404 Error)

**Symptom**: EC2 instance fails to download package from S3 with "404 Not Found".

**Solution**:
1. Verify package file exists: `ls -lh packages/collibra-dq/dq-2025.11-SPARK356-JDK17-package-full.tar`
2. Check package-upload module completed: `cd env/stack/collibra-dq/addons/collibra-dq-standalone/package-upload && terragrunt output`
3. Verify S3 bucket and key: `aws s3 ls s3://<bucket-name>/collibra-dq/`
4. Re-upload package: `cd env/stack/collibra-dq/addons/collibra-dq-standalone/package-upload && terragrunt apply`

#### Package Upload Timeout

**Symptom**: Terragrunt times out when uploading large package file.

**Resolution**: Upload directly with AWS CLI:
```bash
aws s3 cp \
  "packages/collibra-dq/dq-2025.11-SPARK356-JDK17-package-full.tar" \
  "s3://$(aws sts get-caller-identity --query Account --output text)-datashift-${TF_VAR_environment}-packages-${TF_VAR_region}/collibra-dq/dq-2025.11-SPARK356-JDK17-package-full.tar" \
  --region $TF_VAR_region
```

Then update the Terraform state:
```bash
cd env/stack/collibra-dq/addons/collibra-dq-standalone/package-upload
terragrunt apply --auto-approve
```

#### Target Group Already Exists (ALB deploy)

**Symptom**: `Error: ELBv2 Target Group (ds-dev-dq-c16cb6-tg) already exists` when deploying the Application Load Balancer.

**Cause**: The target group was left in AWS from a previous destroy (or partial deploy). Terraform tries to create it and AWS reports it already exists.

**Fix**: Import the existing target group into Terraform state, then re-run deploy (or apply the ALB module):

```bash
# 1. Get target group ARN (replace region if needed)
TG_ARN=$(aws elbv2 describe-target-groups --names ds-dev-dq-c16cb6-tg --region "${TF_VAR_region:-eu-west-1}" --query 'TargetGroups[0].TargetGroupArn' --output text)

# 2. Import into ALB module state (from project root, with env vars set)
cd env/stack/collibra-dq/addons/collibra-dq-standalone/alb
terragrunt import 'module.alb.aws_lb_target_group.this["collibra-dq"]' "$TG_ARN"

# 3. Re-run deploy or apply
cd -  # back to project root
./deploy-stack.sh collibra-dq
# or: cd env/stack/collibra-dq/addons/collibra-dq-standalone/alb && terragrunt apply --auto-approve
```

Then continue with the rest of the stack (e.g. target group attachment) or re-run `./deploy-stack.sh collibra-dq` so it proceeds from the ALB step.

#### 502 Bad Gateway from ALB

**Symptom**: ALB returns 502 Bad Gateway when accessing Collibra DQ web UI.

**Diagnosis Steps**:
1. Check target group health: AWS Console → EC2 → Target Groups → Check health status
2. Check EC2 instance logs: `aws ssm start-session --target <instance-id>` then `sudo tail -f /var/log/collibra-dq-install.log`
3. Verify security groups: EC2 SG must allow ingress on port 9000 from ALB SG
4. Check application is running: `sudo systemctl status collibra-dq`
5. Verify port binding: `ss -tlnp | grep 9000` (should show `0.0.0.0:9000`)

**Common Causes**:
- Package not uploaded to S3 (EC2 installation failed)
- Security group misconfiguration (ALB can't reach EC2)
- Application not started (check systemd service)
- Application bound to localhost instead of 0.0.0.0

#### EC2 Installation Fails

**Symptom**: Installation log shows errors downloading from S3.

**Check**:
1. Verify IAM role has S3 read permissions
2. Verify package exists in S3
3. Verify VPC endpoints for S3 are configured
4. Check instance internet connectivity (NAT gateway)

**Resolution**:
```bash
# Re-run installation manually
INSTANCE_ID=<instance-id>
aws ssm start-session --target $INSTANCE_ID --region $TF_VAR_region

# Inside instance
sudo -i
cd /opt/collibra-dq
aws s3 cp s3://<bucket>/collibra-dq/<package> .
bash /tmp/install_collibra_dq.sh
```

#### State Lock Error

**Symptom**:
```
Error: Error acquiring the state lock
ConditionalCheckFailedException: The conditional request failed
```

**Resolution**: Only unlock if you are sure no other Terraform/Terragrunt process is using the state (e.g. a previous run crashed). Extract the lock ID from the error message, then run:

```bash
./scripts/unlock-terraform-lock.sh <module-path> <lock-id>
```

**Example**:
```bash
./scripts/unlock-terraform-lock.sh collibra-dq/network/vpc 58b32bea-b71b-6385-e816-f98ecba14b71
```

`module-path` is relative to `env/stack` (e.g. `collibra-dq/network/vpc`). See [scripts/README.md](scripts/README.md#state-lock-unlock).

#### RDS Security Group Deletion Fails

**Symptom**: `destroy-stack.sh` fails when destroying RDS security group with "ENI attached" error.

**Solution**: The destroy script checks for this automatically. If RDS instance still exists in AWS:
1. Delete RDS instance manually: `aws rds delete-db-instance --db-instance-identifier <id> --skip-final-snapshot`
2. Wait for deletion to complete
3. Re-run destroy script

#### Bootstrap Resources Exist But State Missing

**Symptom**: Bootstrap deployment fails with "bucket already exists" or similar.

**Solution**: The deploy script automatically imports existing resources. If it doesn't:
```bash
cd env/stack/bootstrap
terragrunt import aws_s3_bucket.tfstate <bucket-name>
terragrunt import aws_dynamodb_table.locks <table-name>
terragrunt apply
```

### Prevention Tips

To prevent common issues:

1. **Always use absolute paths** in Terragrunt when referencing local files (use `get_repo_root()`)
2. **Verify S3 uploads** before proceeding with dependent resources
3. **Monitor installation logs** during first deployment
4. **Test fileexists()** in Terraform console before deploying:
   ```bash
   cd <module>
   terragrunt console <<< 'fileexists(var.local_file_path)'
   ```

### Getting Help

1. **Check logs**: All deployment scripts output detailed logs
2. **Validate configuration**: `scripts/test-terragrunt.sh` validates Terragrunt configs
3. **Check AWS Console**: Verify resources were created as expected
4. **Review Terragrunt output**: Each module outputs resource IDs and endpoints
5. **Check installation logs**: Connect via SSM and review `/var/log/collibra-dq-install.log`

## Security Notes

⚠️ **Important Security Considerations**:

1. **Terraform State Contains Secrets**: Even with `sensitive = true`, state files contain sensitive values. Treat state files as secrets.
2. **Never Commit Secrets**: `scripts/set-env.sh` is git-ignored. Never commit it.
3. **Rotate Secrets Immediately**: If secrets are accidentally logged or exposed, rotate them immediately.
4. **State Backend Security**: S3 bucket for state should have encryption enabled and restricted access.
5. **CI/CD Secrets**: Store secrets in CI/CD secret management (GitHub Secrets, AWS Secrets Manager, etc.).

## Contributing

- **Branching**: Work on short-lived feature branches; do not commit directly to `main`. Merge via Pull Requests. Release branches (`release/x.y.z`) are for stabilization only. See [CONTRIBUTING.md](CONTRIBUTING.md).
- **Commits**: Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/): `feat(scope): description`, `fix(scope): description`, `docs: ...`, etc.
- **PRs**: Keep PRs small and focused; describe why the change exists, not only what changed.
- **Pre-commit**: Run `pre-commit install` and `pre-commit run --all-files` before pushing.

## Additional Documentation

| Document | Description |
|----------|-------------|
| [env/stack/README.md](env/stack/README.md) | Live stack layout and module map |
| [env/README.md](env/README.md) | Terragrunt config hierarchy (`root.hcl`, `env.hcl`, etc.) |
| [scripts/README.md](scripts/README.md) | Utility scripts (validate-env, test-terragrunt, verify-soda-keys) |
| [packages/README.md](packages/README.md) | Package storage (Collibra DQ) |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Branching, commits, PRs, and release checklist |
| Module READMEs | `module/**/README.md` — inputs, outputs, and usage per module |

Architecture and design decisions are in the [Architecture & Design Decisions](#architecture--design-decisions) section above.

## License

Proprietary. See repository or maintainers for license terms.
=======
Terraform/Terragrunt infrastructure on AWS. Generic core (VPC, bootstrap, EKS, ops) plus add-ons:

- **soda-agent** — Soda Agent on EKS (Helm)
- **collibra-dq** — Collibra DQ Standalone (EC2 + ALB + RDS)

Live configs: `env/stack/`. Shared Terragrunt config: `env/`.

## Prerequisites

Install these tools locally (and in CI if you run validation there):

- Terraform (used by the modules)
- Terragrunt (orchestrates Terraform and remote state)
- AWS CLI (credentials + EKS kubeconfig helper)
- kubectl (for EKS verification/troubleshooting)
- Helm (optional but useful for debugging; Terraform uses the Helm provider)
- jq (optional; some helper scripts use it)

## Environment variables

Deploy and destroy scripts use **environment variables** from your shell or CI. Set them before running:

- **Required:** `TF_VAR_environment`, `TF_VAR_region`, and AWS credentials (`AWS_PROFILE` or `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`)
- **Add-on:** For soda-agent: `SODA_API_KEY_ID`, `SODA_API_KEY_SECRET`. For collibra-dq: `COLLIBRA_DQ_ADMIN_PASSWORD`, `COLLIBRA_DQ_LICENSE_KEY`

When using access keys (not a profile), ensure `AWS_PROFILE` is unset so the AWS CLI uses your keys.

## What gets deployed

### Core platform (shared)

These components are shared and are intended to be reusable by multiple add-ons:

- Terraform remote state bootstrap (S3 bucket + DynamoDB lock table)
- VPC (public/private subnets across multiple AZs)
- VPC endpoints (SSM, ECR, STS, CloudWatch Logs, S3, etc.)
- Ops security group and an Ops EC2 instance (optional; used for access and operations)
- EKS cluster with managed node groups (optional; required for the soda-agent add-on)
- EKS access configuration (optional; IAM/RBAC glue for ops)

### Add-ons (application layers)

Add-ons deploy workloads. Details live in `env/stack/addons/<addon>/README.md`:

- **soda-agent** — Helm deployment into EKS
- **collibra-dq** — EC2 + ALB + RDS (Collibra DQ Standalone)

## Repository layout

```
DQ-Infrastructures/
├── env/
│   ├── root.hcl                    # Global Terragrunt config (locals, validations, remote_state, inputs)
│   ├── env.hcl                     # Environment definitions and defaults
│   ├── common.hcl                  # Common generate blocks (provider, backend)
│   ├── region.hcl                  # Region-level shared config (state, tags)
│   └── stack/                      # Terragrunt live configs (what you actually apply)
│       ├── bootstrap/              # Phase 0: Bootstrap (S3+DDB)
│       ├── network/
│       │   ├── vpc/
│       │   └── vpc-endpoints/
│       ├── ops/
│       │   ├── sg-ops/
│       │   └── ec2-ops/
│       ├── eks/
│       │   └── ops-ec2-eks-access/
│       ├── database/
│       │   └── rds-collibra-dq/
│       └── addons/
│           ├── soda-agent/
│           └── collibra-dq-standalone/
├── module/                         # Terraform modules used by the live configs
├── scripts/                        # Validation + test utilities
├── packages/                       # Large artifacts (e.g., Collibra DQ package) are git-ignored
├── deploy-stack.sh                 # Deploy a stack (soda-agent | collibra-dq)
├── destroy-stack.sh                # Destroy a stack
├── deploy-bootstrap.sh             # Bootstrap only
├── destroy-bootstrap.sh            # Destroy bootstrap only
└── README.md
```

Entry points:

- `deploy-stack.sh <stack>` — deploy soda-agent or collibra-dq (set env vars first)
- `destroy-stack.sh <stack>` — destroy a stack
- `deploy-bootstrap.sh` / `destroy-bootstrap.sh` — bootstrap only

Other docs: `env/README.md`, `env/stack/README.md`, `scripts/README.md`, `env/stack/addons/*/README.md`

## Terragrunt configuration flow

High-level flow:

- `env/root.hcl`:
  - reads environment definitions from `env/env.hcl`
  - validates `TF_VAR_environment`, `TF_VAR_region`, and the AWS account safety check
  - defines `remote_state` naming (S3 bucket + DynamoDB table)
  - exposes shared `inputs` and `locals`

- Each module in `env/stack/**/terragrunt.hcl`:
  - includes `env/root.hcl`
  - optionally includes `env/common.hcl` / `env/region.hcl`
  - sets module-specific inputs and dependencies

## Deployment phases

### soda-agent stack

1) `env/stack/bootstrap`
2) `env/stack/network/vpc`
3) `env/stack/network/vpc-endpoints`
4) `env/stack/ops/sg-ops`
5) `env/stack/eks`
6) `env/stack/ops/ec2-ops`
7) `env/stack/eks/ops-ec2-eks-access`
8) `env/stack/addons/soda-agent`

### collibra-dq stack

1) `env/stack/bootstrap` (shared)
2) `env/stack/network/vpc` + `env/stack/network/vpc-endpoints` (shared)
3) `env/stack/addons/collibra-dq-standalone/alb/sg-alb`
4) `env/stack/addons/collibra-dq-standalone/sg-collibra-dq`
5) `env/stack/database/rds-collibra-dq/sg-rds`
6) `env/stack/database/rds-collibra-dq/rds`
7) `env/stack/addons/collibra-dq-standalone/package-upload`
8) `env/stack/addons/collibra-dq-standalone` (EC2 instance)
9) `env/stack/addons/collibra-dq-standalone/alb`
10) `env/stack/addons/collibra-dq-standalone/alb/target-group-attachment`

Notes:
- Collibra DQ is deployed as a minimal EC2+ALB+RDS stack. It does not require EKS.
- The Collibra DQ RDS security group allows Postgres (5432) from the Collibra DQ instance security group.
  If you later want RDS reachable from EKS nodes or an ops box, add it as an optional SG allowlist (without making EKS a hard dependency).

## Deployment modes

### Full stack (default)

Deploys the selected stack including its add-ons.

### Core-only (skip add-ons)

`deploy-stack.sh` supports deploying all shared/core infrastructure *without* deploying add-ons:

- `--skip-addons` skips add-on/application layers.
- This is useful to validate networking and (for the Soda stack) EKS/ops tooling before deploying workloads.

`destroy-stack.sh --skip-addons` destroys only core/shared infrastructure and refuses to run if any add-on modules are detected (to prevent orphaning resources).

## Environment variables (explicit)

These are the variables used by `deploy-stack.sh` and `destroy-stack.sh` (set in your shell or CI).

### Required for all deployments (local and CI/CD)

- `TF_VAR_environment`
  - environment key used by Terragrunt to pick config from `env/env.hcl`
- `TF_VAR_region`
  - AWS region to deploy into
- AWS credentials (one of):
  - `AWS_PROFILE` — use a profile from `~/.aws/config`
  - `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` — when using keys, **unset** `AWS_PROFILE` or the CLI will prefer the profile and ignore the keys

Scripts use whatever is in the shell; they do not load any env file. Authoritative environment/region lists are in `env/env.hcl`.

### Optional safety override (recommended for CI/CD)

- `TG_EXPECTED_ACCOUNT_ID`
  - overrides the expected AWS account check so you don’t have to commit account IDs to `env/env.hcl`

### soda-agent add-on variables

Only required when deploying the soda-agent add-on (not needed with `--skip-addons`).

Required:
- `SODA_API_KEY_ID`
- `SODA_API_KEY_SECRET`

Optional:
- `SODA_CLOUD_REGION` (default: `eu`)
- `SODA_LOG_LEVEL` (default: `INFO`)
- `SODA_LOG_FORMAT` (default: `raw`)
- `SODA_IMAGE_APIKEY_ID` (defaults to `SODA_API_KEY_ID`)
- `SODA_IMAGE_APIKEY_SECRET` (defaults to `SODA_API_KEY_SECRET`)

### collibra-dq add-on variables

Only required when deploying the collibra-dq add-on (not needed with `--skip-addons`).

Required:
- `COLLIBRA_DQ_ADMIN_PASSWORD`
- `COLLIBRA_DQ_LICENSE_KEY`

Optional (read by Terragrunt configs under `env/stack/addons/collibra-dq-standalone/**`):
- `COLLIBRA_DQ_OWL_BASE` (default: `/opt/collibra-dq`)
- `COLLIBRA_DQ_SPARK_PACKAGE` (default: `spark-3.5.6-bin-hadoop3.tgz`)
- `COLLIBRA_DQ_PACKAGE_FILENAME` (default: `dq-2025.11-SPARK356-JDK17-package-full.tar`)
- `COLLIBRA_DQ_PACKAGE_URL` (optional override; default is the S3 path created by the package upload module)
- `COLLIBRA_DQ_LICENSE_NAME` (default: `collibra-partners`)
- `COLLIBRA_DQ_ENABLE_S3_ACCELERATION` (default: `false`)
- `COLLIBRA_DQ_SKIP_PACKAGE_UPLOAD` (default: `false`)

Database optional:
- `COLLIBRA_DQ_RDS_PASSWORD` (if unset, the RDS module generates a random password)

Set these in your shell or in CI secrets before running deploy/destroy.

## Usage

### Quick start

```bash
export TF_VAR_environment=dev
export TF_VAR_region=eu-west-1
export AWS_PROFILE=your-profile   # or AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY
# Add-on secrets if needed: SODA_*, COLLIBRA_DQ_*

./deploy-stack.sh soda-agent
# or
./deploy-stack.sh collibra-dq
```

### Destroy

```bash
# Same env vars in shell
echo "yes" | ./destroy-stack.sh collibra-dq
# or
echo "yes" | ./destroy-stack.sh soda-agent
```

### Other options

- **Core-only (skip add-ons):** `./deploy-stack.sh <stack> --skip-addons` or `./destroy-stack.sh <stack> --skip-addons`
- **Destroy bootstrap (dangerous):** `./destroy-stack.sh <stack> --destroy-bootstrap`

## Bootstrap behavior (import-aware)

Bootstrap creates the Terraform state backend:

- S3 bucket for state files
- DynamoDB table for state locking

If the S3 bucket and DynamoDB table already exist but the Terraform state is missing:

- `deploy-stack.sh` will import them before continuing.
- `destroy-stack.sh --destroy-bootstrap` will import them before destroying.

Bootstrap-only helpers:

- `./deploy-bootstrap.sh` bootstraps only (same import-aware logic as `deploy-stack.sh`)
- `./destroy-bootstrap.sh` destroys only the bootstrap backend (import-aware)

## Add-ons (detailed)

### soda-agent add-on

- Deploys the Soda Agent Helm chart into EKS; creates namespace (default `soda-agent`).
- Depends on `env/stack/eks`. Reads `SODA_API_KEY_ID` / `SODA_API_KEY_SECRET`.
- Skip: `./deploy-stack.sh soda-agent --skip-addons`.

Details: `env/stack/addons/soda-agent/README.md`

### collibra-dq add-on

- EC2 + ALB (HTTP) + RDS PostgreSQL; package-upload to S3. Depends on VPC, endpoints, SGs, `env/stack/database/rds-collibra-dq/**`.
- Package: local file under `packages/collibra-dq/`, name from `COLLIBRA_DQ_PACKAGE_FILENAME`.
- Skip: `./deploy-stack.sh collibra-dq --skip-addons`.

Details: `env/stack/addons/collibra-dq-standalone/README.md`

## Scripts

- `scripts/test-modules.sh` — Terraform module validation
- `scripts/test-terragrunt.sh` — Terragrunt config validation (stack-first)
- `scripts/test-collibra-dq-deployment.sh` — end-to-end collibra-dq checks (requires deployed infra)
- `scripts/utils/check-deployment-status.sh` — quick deployment status

See `scripts/README.md` for usage.

## CI / validation

This repo includes a basic GitHub Actions workflow:

- `.github/workflows/iac-validate.yml`

It runs `pre-commit` (Terraform fmt/validate, Terragrunt validate/hclfmt, shellcheck, markdownlint, etc.). It does not deploy infrastructure.

If you add a deploy workflow later, treat it like production automation:

- Only allow `workflow_dispatch` or protected branches
- Store secrets in the CI secret store
- Use `TG_EXPECTED_ACCOUNT_ID` to enforce account safety without committing account IDs

## Troubleshooting

- **AWS credentials not configured or invalid**: Ensure `TF_VAR_environment`, `TF_VAR_region`, and AWS credentials are set in the same shell (or CI) where you run deploy/destroy. When using access keys, unset `AWS_PROFILE` so the CLI uses the keys.
- **S3 bucket / DynamoDB table already exist**: Bootstrap import will attach existing resources to state.
- **Account mismatch**: Set `TG_EXPECTED_ACCOUNT_ID` (recommended for CI/CD) instead of committing an account ID.
- **Missing add-on secrets during core-only deploy**: Use `--skip-addons` to avoid validating add-on secrets.

## Security notes (read this)

- Terraform state can contain sensitive values. Even if variables are marked `sensitive`, state files still need to be treated as secrets.
- Do not paste full `terraform plan/apply/destroy` output into tickets or chat.
- Rotate secrets immediately if you accidentally log them.
- The soda-agent Helm values use `set_sensitive` for the API key; assume state/logs can still contain secrets.
>>>>>>> origin/main
