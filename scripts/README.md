# Scripts Directory

This directory contains testing, validation, and utility scripts. Deployment and destruction are handled by unified scripts in the project root.

## Structure

```
scripts/
├── test-collibra-dq-deployment.sh  # Comprehensive testing for Collibra DQ
├── test-modules.sh                  # Validates Terraform modules
├── test-terragrunt.sh               # Validates Terragrunt configurations
├── validate-env.sh                   # Environment variable validation
├── utils/                            # Utility scripts
│   └── check-deployment-status.sh   # Quick deployment status check
└── README.md                         # This file
```

## Usage

### Testing Scripts

**Comprehensive Collibra DQ Testing**:
```bash
./scripts/test-collibra-dq-deployment.sh [env] [region]
# Example: ./scripts/test-collibra-dq-deployment.sh dev eu-west-1
```

Tests all components:
- EC2 instance status
- Collibra DQ service status
- Health endpoints
- ALB and target group health
- RDS connectivity

**Module Validation**:
```bash
./scripts/test-modules.sh
```

**Terragrunt Validation**:
```bash
./scripts/test-terragrunt.sh [env] [region]
# Example: ./scripts/test-terragrunt.sh dev eu-west-1
```

**Environment Validation** (called automatically by deploy scripts):
```bash
./scripts/validate-env.sh <stack>
# Example: ./scripts/validate-env.sh soda-agent
```

Validates required environment variables before deployment:
- Soda Agent: `SODA_API_KEY_ID`, `SODA_API_KEY_SECRET`
- Collibra DQ: `COLLIBRA_DQ_ADMIN_PASSWORD`, `COLLIBRA_DQ_LICENSE_KEY`

### Utility Scripts

**Quick Deployment Status**:
```bash
./scripts/utils/check-deployment-status.sh [env]
# Example: ./scripts/utils/check-deployment-status.sh dev
```

## Root-Level Scripts (Primary Entry Points)

All deployment and destruction is handled by unified scripts in the project root:

**Deployment**:
```bash
# Deploy Soda Agent stack
./deploy-stack.sh soda-agent <env>

# Deploy Collibra DQ stack
./deploy-stack.sh collibra-dq <env>
```

**Destruction**:
```bash
# Destroy Soda Agent stack
./destroy-stack.sh soda-agent <env>

# Destroy Collibra DQ stack
./destroy-stack.sh collibra-dq <env>
```

**Bootstrap**:
```bash
# Bootstrap environment (one-time)
./deploy-bootstrap.sh <env>

# Destroy bootstrap (after all stacks destroyed)
./destroy-bootstrap.sh <env>
```

These unified scripts handle:
- Dependency ordering
- Error handling
- Automatic retries
- Bootstrap management
- Resource reuse (VPC, endpoints)

## Migration from Old Scripts

If you were using old scripts, here are the equivalents:

| Old Script | New Command |
|------------|-------------|
| `scripts/deploy/deploy-collibra-dq.sh` | `./deploy-stack.sh collibra-dq <env>` |
| `scripts/destroy/destroy-collibra-dq.sh` | `./destroy-stack.sh collibra-dq <env>` |
| `scripts/test-collibra-dq.sh` | `./scripts/test-collibra-dq-deployment.sh <env>` |
| `scripts/test-collibra-dq-quick.sh` | `./scripts/test-collibra-dq-deployment.sh <env>` |
| `scripts/check-collibra-dq-health.sh` | `./scripts/test-collibra-dq-deployment.sh <env>` |
| `scripts/diagnose-collibra-dq.sh` | `./scripts/test-collibra-dq-deployment.sh <env>` |
