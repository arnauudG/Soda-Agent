# Live stacks (`env/stack/`)

This folder contains the Terragrunt "live" configurations. Each subfolder is a module boundary with its own `terragrunt.hcl` and its own remote state.

## How to run

Preferred: use the orchestrators at the repo root:

- `./deploy-stack.sh <stack> [--skip-addons]`
- `./destroy-stack.sh <stack> [--skip-addons] [--destroy-bootstrap]`

Core-only behavior (`--skip-addons`):

- **soda-agent** core-only: bootstrap + network + ops + EKS (see root `README.md`).
- **collibra-dq** core-only: bootstrap + network only (no database/app).

Advanced: run an individual module directly:

```bash
cd env/stack/network/vpc
terragrunt apply
```

## Module map

### Bootstrap

- `env/stack/bootstrap`
  - Creates the Terraform backend: S3 bucket for state and DynamoDB table for locking.
  - Must exist before any other module can use remote state.

### Network

- `env/stack/network/vpc`
  - VPC, public/private subnets, routing, NAT (depending on config).

- `env/stack/network/vpc-endpoints`
  - Interface and gateway endpoints used by workloads (SSM, ECR, S3, logs, STS, ...).

### Ops

- `env/stack/ops/sg-ops`
  - Ops/security groups shared by the stack.

- `env/stack/ops/ec2-ops`
  - Ops EC2 instance (commonly used for access, debugging, and operational tasks).

### EKS

- `env/stack/eks`
  - EKS cluster + managed node groups + core addons.

- `env/stack/eks/ops-ec2-eks-access`
  - IAM bits that make it easier for the ops instance/user to interact with EKS.

### Add-ons

- `env/stack/addons/soda-agent` — soda-agent add-on (EKS/Helm). See `env/stack/addons/soda-agent/README.md`.
- `env/stack/addons/collibra-dq-standalone/**` — collibra-dq add-on (EC2 + ALB + package upload). See `env/stack/addons/collibra-dq-standalone/README.md`.

### Database (collibra-dq)

- `env/stack/database/rds-collibra-dq/sg-rds`, `env/stack/database/rds-collibra-dq/rds` — used by the collibra-dq add-on.
