# Scripts

Validation, testing, and utilities. Deploy/destroy entry points are at the repo root: `deploy-stack.sh` / `destroy-stack.sh`.

## Structure

```
scripts/
├── set-env.example.sh                 # Env template: copy to set-env.sh, edit, then source before deploy/destroy
├── validate-env.sh                    # Env + AWS credential check (used by deploy/destroy)
├── test-modules.sh                    # Terraform module validation
├── test-terragrunt.sh                 # Terragrunt config validation (stack-first)
├── test-collibra-dq-deployment.sh      # End-to-end Collibra DQ checks (requires deployed infra)
└── utils/
    └── check-deployment-status.sh     # Quick status checks
```

## Environment variables

Scripts use whatever is **already in your shell**. They do not load any file.

1. Copy and edit: `cp scripts/set-env.example.sh scripts/set-env.sh` (edit with your AWS keys, Collibra DQ secrets, etc.)
2. In the same shell: `source scripts/set-env.sh` then run deploy/destroy.

When using access keys (not a profile), ensure `unset AWS_PROFILE` in `set-env.sh` or the shell.

## Usage

### Environment validation

`deploy-stack.sh` calls this automatically.

```
./scripts/validate-env.sh <stack> [environment] [skip_addons]

# Examples:
./scripts/validate-env.sh soda-agent
./scripts/validate-env.sh soda-agent dev yes
./scripts/validate-env.sh collibra-dq prod yes
```

Notes:
- When `skip_addons` is `yes`, add-on secrets (Soda/Collibra) are not required.

### Terragrunt validation (stack-first)

Validates the live configs under `env/stack/**` (uses mock outputs where available).

```
./scripts/test-terragrunt.sh [environment] [region]

# Example:
./scripts/test-terragrunt.sh dev eu-west-1
```

### Module validation

```
./scripts/test-modules.sh
```

### Collibra DQ end-to-end checks

Requires that Collibra DQ is deployed and that the EC2 instance is reachable via SSM.

```
./scripts/test-collibra-dq-deployment.sh [environment] [region]

# Example:
./scripts/test-collibra-dq-deployment.sh dev eu-west-1
```

### Quick deployment status

```
./scripts/utils/check-deployment-status.sh [environment] [region]

# Example:
./scripts/utils/check-deployment-status.sh dev eu-west-1
```
