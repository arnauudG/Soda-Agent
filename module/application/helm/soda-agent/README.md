# Soda Agent Helm Module

Deploys the Soda Agent to an EKS cluster using Helm.

## Description

This module deploys the Soda Agent to Kubernetes via Helm. The Soda Agent:

- Connects to Soda Cloud for data quality monitoring
- Executes data quality checks on your data sources
- Runs on EKS with auto-configured authentication

## Usage

```hcl
module "soda_agent" {
  source = "../../../module/application/helm/soda-agent"

  cluster_name = dependency.eks.outputs.cluster_name
  region       = "eu-west-1"
  namespace    = "soda-agent"
  agent_name   = "datashift-dev-eu-west-1-agent"

  chart_repo    = "soda-agent"
  chart_version = "1.3.13"
  chart_name    = "soda-agent"

  cloud_endpoint = "https://cloud.soda.io"

  api_key_id     = var.SODA_API_KEY_ID
  api_key_secret = var.SODA_API_KEY_SECRET

  # Image registry credentials (defaults to API keys for v1.2.0+)
  image_credentials_id     = var.SODA_API_KEY_ID
  image_credentials_secret = var.SODA_API_KEY_SECRET

  create_namespace = true
}
```

## Required Inputs

| Name | Description | Type |
|------|-------------|------|
| `cluster_name` | EKS cluster name | `string` |
| `region` | AWS region of the cluster | `string` |
| `agent_name` | Soda agent name (unique per Soda Cloud account) | `string` |
| `api_key_id` | Soda Cloud API key ID | `string` |
| `api_key_secret` | Soda Cloud API key secret | `string` |

## Optional Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `namespace` | Kubernetes namespace | `string` | `"soda-agent"` |
| `chart_repo` | Helm chart repository | `string` | `"https://registry.cloud.soda.io/chartrepo/agent"` |
| `chart_version` | Chart version (empty for latest) | `string` | `""` |
| `chart_name` | Helm chart name | `string` | `"soda-agent"` |
| `cloud_endpoint` | Soda Cloud endpoint | `string` | `"https://cloud.soda.io"` |
| `image_credentials_id` | Registry API key ID | `string` | `""` |
| `image_credentials_secret` | Registry API key secret | `string` | `""` |
| `existing_image_pull_secret` | Existing image pull secret name | `string` | `""` |
| `log_format` | Log format (raw/json) | `string` | `"raw"` |
| `log_level` | Log level (ERROR/WARN/INFO/DEBUG/TRACE) | `string` | `"INFO"` |
| `create_namespace` | Create namespace if not exists | `bool` | `true` |

## Outputs

| Name | Description |
|------|-------------|
| `release_name` | Helm release name |
| `namespace` | Kubernetes namespace |
| `agent_name` | Soda agent name |

## Soda Cloud Regions

| Region | Endpoint |
|--------|----------|
| EU | `https://cloud.soda.io` |
| US | `https://cloud.us.soda.io` |

Set `cloud_endpoint` based on your Soda Cloud region.

## Security Considerations

- API keys are marked as sensitive and not logged
- Image pull secrets are created automatically
- Agent runs with minimal permissions in dedicated namespace
- Use IRSA for AWS data source access (not yet implemented)

## Cost Implications

The Soda Agent itself runs on your EKS cluster nodes:

| Resource | Cost Impact |
|----------|-------------|
| Pod resources | ~0.5 vCPU, 1GB RAM per agent pod |
| Data transfer | Variable (depends on check frequency) |

## Dependencies

- `compute/eks/cluster` - EKS cluster for agent deployment

## Getting API Keys

1. Log in to Soda Cloud
2. Go to Profile > API Keys
3. Click "Create API Key"
4. Copy the ID and Secret

**Important**: The agent name must be unique within your Soda Cloud account. If you get registration errors, try a different name or delete the old agent from Soda Cloud.

## Troubleshooting

### Agent not appearing in Soda Cloud
```bash
# Check pod logs
kubectl logs -n soda-agent -l app.kubernetes.io/name=soda-agent

# Check pod status
kubectl get pods -n soda-agent
```

### Image pull errors
Verify your API keys are correct and have access to the Soda private registry.

### Connection issues
- Check EKS node security groups allow outbound HTTPS
- Verify VPC NAT Gateway is working for internet access
