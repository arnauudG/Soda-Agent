# DQ-Infrastructures

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
