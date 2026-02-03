# Collibra DQ Stack

Independent Terragrunt stack that deploys **Collibra DQ** as a standalone application on EC2, fronted by an internet-facing ALB, with an RDS PostgreSQL metastore.

## Layout (stack-first)

- `network/vpc`
- `network/vpc-endpoints`
- `database/rds-collibra-dq/sg-rds`
- `database/rds-collibra-dq/rds`
- `addons/collibra-dq-standalone/package-upload`
- `addons/collibra-dq-standalone/sg-collibra-dq`
- `addons/collibra-dq-standalone` (EC2)
- `addons/collibra-dq-standalone/alb/sg-alb`
- `addons/collibra-dq-standalone/alb`
- `addons/collibra-dq-standalone/alb/target-group-attachment`

## Deployment (recommended)

Use the root orchestrator so ordering is deterministic:

```bash
source scripts/set-env.sh
./deploy-stack.sh collibra-dq
```

Core-only (network only):

```bash
./deploy-stack.sh collibra-dq --skip-addons
```

## ALB behavior (important)

- **Traffic**: ALB forwards to EC2 on **port 9000**.
- **Health checks**: use the **traffic port (9000)** with a tolerant matcher (`200-499`).

This avoids coupling ALB health to the Collibra agent health port (9101), which can be environment/version dependent.

## Verify deployment

Get ALB DNS:

```bash
cd env/stack/collibra-dq/addons/collibra-dq-standalone/alb
terragrunt output -raw load_balancer_dns_name
```

Target health:

```bash
cd env/stack/collibra-dq/addons/collibra-dq-standalone/alb
terragrunt output -json target_group_arns
```

Then use AWS CLI:

```bash
aws elbv2 describe-target-health --target-group-arn "<tg-arn>" --region "$TF_VAR_region"
```

## Notes

- Collibra DQ installation takes time. The target can be unhealthy until the service is up and responding on port 9000.
- The instance is deployed in a private subnet; access is via ALB and SSM Session Manager (no SSH).

## Documentation

- **Root:** [README.md](../../../README.md) — overview, deployment, env vars, package deployment, troubleshooting.
- **Packages:** [packages/collibra-dq/README.md](../../../packages/collibra-dq/README.md) — package file and S3 upload.
- **Contributing:** [CONTRIBUTING.md](../../../CONTRIBUTING.md) — branching, commits, release checklist.
