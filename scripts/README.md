# Scripts

Validation and test utilities. Deploy/destroy entry points are at the repo root: `deploy-stack.sh` / `destroy-stack.sh`.

**Environment:** Scripts use whatever environment variables are already set in your shell or CI. Set `TF_VAR_environment`, `TF_VAR_region`, AWS credentials, and add-on secrets (e.g. `SODA_*`, `COLLIBRA_DQ_*`) before running deploy/destroy.

## Structure

```
scripts/
├── test-modules.sh                    # Terraform module validation
├── test-terragrunt.sh                 # Terragrunt config validation (stack-first)
├── test-collibra-dq-deployment.sh     # End-to-end collibra-dq checks (requires deployed infra)
└── utils/
    └── check-deployment-status.sh    # Quick deployment status
```

## Usage

### Terragrunt validation (stack-first)

Validates the live configs under `env/stack/**` (uses mock outputs where available).

```bash
./scripts/test-terragrunt.sh [environment] [region]
# Example:
./scripts/test-terragrunt.sh dev eu-west-1
```

### Module validation

```bash
./scripts/test-modules.sh
```

### Collibra DQ end-to-end checks

Requires collibra-dq to be deployed and EC2 reachable via SSM.

```bash
./scripts/test-collibra-dq-deployment.sh [environment] [region]
# Example:
./scripts/test-collibra-dq-deployment.sh dev eu-west-1
```

### Quick deployment status

```bash
./scripts/utils/check-deployment-status.sh [environment] [region]
# Example:
./scripts/utils/check-deployment-status.sh dev eu-west-1
```
