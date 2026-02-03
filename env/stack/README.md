# Live stacks (`env/stack/`)

This folder contains the Terragrunt "live" configurations. Each subfolder is a module boundary with its own `terragrunt.hcl` and its own remote state.

## Structure

Stacks are now **completely independent** - each has its own VPC and network resources:

- `bootstrap/` - Shared (Terraform state management only)
- `soda-agent/` - Independent Soda Agent stack
- `collibra-dq/` - Independent Collibra DQ stack

## How to run

Preferred: use the orchestrators at the repo root (see root [README.md](../../README.md) and [CONTRIBUTING.md](../../CONTRIBUTING.md) for release checklist):

- `./deploy-stack.sh <stack> [--skip-addons]`
- `./destroy-stack.sh <stack> [--destroy-bootstrap]`

Core-only behavior (`--skip-addons`):

- **soda-agent** core-only: bootstrap + network + ops + EKS (see root `README.md`).
- **collibra-dq** core-only: bootstrap + network only (no database/app).

Advanced: run an individual module directly:

```bash
cd env/stack/soda-agent/network/vpc
terragrunt apply
```

## Module map

### Bootstrap (shared)

- `env/stack/bootstrap`
  - Creates the Terraform backend: S3 bucket for state and DynamoDB table for locking.
  - Must exist before any other module can use remote state.
  - Shared by both stacks.

### Soda Agent Stack

- `env/stack/soda-agent/network/vpc`
  - VPC, public/private subnets, routing, NAT (depending on config).

- `env/stack/soda-agent/network/vpc-endpoints`
  - Interface and gateway endpoints used by workloads (SSM, ECR, S3, logs, STS, ...).

- `env/stack/soda-agent/ops/sg-ops`
  - Ops/security groups for the stack.

- `env/stack/soda-agent/ops/ec2-ops`
  - Ops EC2 instance (commonly used for access, debugging, and operational tasks).

- `env/stack/soda-agent/eks`
  - EKS cluster + managed node groups + core addons.

- `env/stack/soda-agent/eks/ops-ec2-eks-access`
  - IAM bits that make it easier for the ops instance/user to interact with EKS.

- `env/stack/soda-agent/addons/soda-agent`
  - Soda Agent add-on (EKS/Helm). See [soda-agent stack README](soda-agent/README.md) and [Helm module README](../../module/application/helm/soda-agent/README.md).

### Collibra DQ Stack

- `env/stack/collibra-dq/network/vpc`
  - VPC, public/private subnets, routing, NAT (depending on config).

- `env/stack/collibra-dq/network/vpc-endpoints`
  - Interface and gateway endpoints used by workloads (SSM, S3, ...).

- `env/stack/collibra-dq/database/rds-collibra-dq/sg-rds`
  - RDS security group for Collibra DQ PostgreSQL.

- `env/stack/collibra-dq/database/rds-collibra-dq/rds`
  - RDS PostgreSQL database for Collibra DQ.

- `env/stack/collibra-dq/addons/collibra-dq-standalone/**`
  - Collibra DQ add-on (EC2 + ALB + package upload). See [collibra-dq/README.md](collibra-dq/README.md).
