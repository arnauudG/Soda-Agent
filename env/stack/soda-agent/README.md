# Soda Agent Stack

Independent Terragrunt stack that deploys **Soda Agent** (data quality monitoring) on Amazon EKS. This stack owns its own VPC, EKS cluster, ops instance, and the Soda Agent Helm add-on.

## Purpose

- Run Soda Agent in Kubernetes to connect to Soda Cloud and execute data quality checks.
- Provide a production-ready, repeatable deployment via IaC (Terraform/Terragrunt) and AWS (EKS, VPC, SSM).

## Stack Layout

| Path | Description |
|------|-------------|
| `network/vpc` | VPC, public/private subnets, NAT gateway(s) |
| `network/vpc-endpoints` | Interface and gateway endpoints (ECR, S3, SSM, STS, CloudWatch Logs, etc.) |
| `ops/sg-ops` | Security groups for ops resources |
| `ops/ec2-ops` | Ops EC2 instance (SSM Session Manager, no SSH keys) |
| `eks` | EKS cluster + managed node group(s) + core add-ons |
| `eks/ops-ec2-eks-access` | IAM so the ops role can describe the cluster (e.g. for `kubectl`) |
| `addons/soda-agent` | Soda Agent Helm chart (orchestrator + jobs) |

## Deployment Order

Deploy via the root orchestrator (recommended):

```bash
export TF_VAR_environment=dev TF_VAR_region=eu-west-1
# Required for add-on: SODA_API_KEY_ID, SODA_API_KEY_SECRET (from Soda Cloud → Data Sources → Agents → New Soda Agent)
./deploy-stack.sh soda-agent
```

Core-only (no Soda Agent add-on):

```bash
./deploy-stack.sh soda-agent --skip-addons
```

## Required Environment Variables (add-on)

| Variable | Description |
|----------|-------------|
| `SODA_API_KEY_ID` | Soda Cloud API key ID (Service Account keys from **New Soda Agent** dialog only) |
| `SODA_API_KEY_SECRET` | Soda Cloud API key secret |

**Important:** Use only keys from **Data Sources → Agents → New Soda Agent** in Soda Cloud. Do not use Profile → API Keys (human user keys cause `403 Invalid user type`).

## Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SODA_CLOUD_REGION` | `eu` | Soda Cloud region: `eu` or `us` (sets cloud endpoint) |
| `SODA_LOG_LEVEL` | `INFO` | Log level (e.g. DEBUG, INFO, WARN, ERROR) |
| `SODA_LOG_FORMAT` | `raw` | Log format: `raw` or `json` |
| `SODA_AGENT_ID` | (unset) | Existing agent ID from Soda Cloud (Agents → agent → ID in URL). **Leave unset for first-time install** (orchestrator will register a new agent with `agent_name`). Set when redeploying or when the agent name is already taken to avoid CrashLoopBackOff. |
| `SODA_IMAGE_APIKEY_ID` | same as `SODA_API_KEY_ID` | Image registry API key (only if Soda gave separate registry credentials) |
| `SODA_IMAGE_APIKEY_SECRET` | same as `SODA_API_KEY_SECRET` | Image registry API key secret |

## Destroy

```bash
export TF_VAR_environment=dev TF_VAR_region=eu-west-1
./destroy-stack.sh soda-agent
```

Add-on is destroyed first (Helm uninstall), then EKS, ops, network. Bootstrap is left in place unless you pass `--destroy-bootstrap`.

## Documentation

- **Module (Helm chart wrapper):** [module/application/helm/soda-agent/README.md](../../../module/application/helm/soda-agent/README.md) — inputs, outputs, API keys, troubleshooting.
- **Scripts:** [scripts/README.md](../../../scripts/README.md) — minimal helpers (`set-env.example.sh`, `validate-env.sh`, `verify-soda-keys.sh`, test scripts).
- **Root:** [README.md](../../../README.md) — project overview, deployment guide, all env vars.
- **Contributing:** [CONTRIBUTING.md](../../../CONTRIBUTING.md) — branching, commits, PRs, release checklist.

## Debugging (minimal)

This repo intentionally keeps helper scripts minimal. For day-2 operations, use AWS CLI + kubectl:

```bash
export TF_VAR_environment=dev TF_VAR_region=eu-west-1
aws eks update-kubeconfig --name "datashift-${TF_VAR_environment}-soda-agent-eks" --region "$TF_VAR_region"
kubectl get pods -n soda-agent
kubectl logs -n soda-agent <pod> --previous --tail=100
```

## Production Readiness

- **Chart version:** Prod pins `chart_version` in `env/env.hcl` (e.g. `1.3.15`); dev may use latest.
- **Chart repo:** Full URL `https://helm.soda.io/soda-agent/` is used so Terraform does not depend on a pre-run `helm repo add`.
- **Agent ID:** Set `SODA_AGENT_ID` when reusing an existing agent (e.g. after destroy/redeploy) to avoid CrashLoopBackOff ("agent name already registered").
- **Secrets:** API keys are sensitive and not logged; prefer a secrets manager + CI/CD injection; do not commit secrets.
- **State:** Terraform state may contain sensitive values; restrict access to state bucket and lock table.
- **Networking:** EKS nodes need outbound HTTPS to Soda Cloud and `registry.cloud.soda.io`; VPC endpoints (ECR, S3, etc.) are deployed for private connectivity where applicable.
