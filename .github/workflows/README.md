# GitHub Actions Workflows

This directory contains CI/CD workflows for deploying infrastructure components.

## Available Workflows

### 1. Deploy Soda Agent (`deploy-soda-agent.yml`)

Deploys the Soda Agent Helm chart to EKS.

**Triggers**:
- Manual workflow dispatch
- Push to `main` branch (when Soda Agent files change)
- Pull requests (plan only)

**Required Secrets**:
- `AWS_ACCESS_KEY_ID` - AWS access key
- `AWS_SECRET_ACCESS_KEY` - AWS secret key
- `SODA_API_KEY_ID` - Soda Cloud API key ID
- `SODA_API_KEY_SECRET` - Soda Cloud API key secret

**Optional Secrets**:
- `SODA_IMAGE_APIKEY_ID` - Image registry API key ID (if different from main API key)
- `SODA_IMAGE_APIKEY_SECRET` - Image registry API key secret (if different from main API key)
- `SODA_CLOUD_REGION` - Cloud region (`eu` or `us`, defaults to `eu`)

**Usage**:
```bash
# Via GitHub UI: Actions → Deploy Soda Agent → Run workflow
# Select environment, region, and action (plan/apply/destroy)
```

### 2. Deploy Collibra DQ (`deploy-collibra-dq.yml`)

Deploys Collibra DQ Helm chart and RDS PostgreSQL database to EKS.

**Triggers**:
- Manual workflow dispatch
- Push to `main` branch (when Collibra DQ or RDS files change)
- Pull requests (plan only)

**Required Secrets**:
- `AWS_ACCESS_KEY_ID` - AWS access key
- `AWS_SECRET_ACCESS_KEY` - AWS secret key
- `COLLIBRA_DQ_LICENSE_KEY` - Collibra DQ license key
- `COLLIBRA_DQ_IMAGE_REGISTRY_USERNAME` - Container registry username
- `COLLIBRA_DQ_IMAGE_REGISTRY_PASSWORD` - Container registry password
- `COLLIBRA_DQ_CHART_REPO` - Helm chart repository URL

**Optional Secrets**:
- `COLLIBRA_DQ_IMAGE_REGISTRY_URL` - Container registry URL (defaults to `registry.collibra.com`)
- `COLLIBRA_DQ_CHART_VERSION` - Specific chart version (defaults to latest)
- `COLLIBRA_DQ_CHART_NAME` - Chart name (defaults to `collibra-dq`)
- `COLLIBRA_DQ_RDS_PASSWORD` - RDS master password (auto-generated if not set)

**Usage**:
```bash
# Via GitHub UI: Actions → Deploy Collibra DQ → Run workflow
# Select environment, region, action, and whether to deploy RDS
```

**Deployment Order**:
1. RDS Security Group (if `deploy_rds` is true)
2. RDS PostgreSQL (if `deploy_rds` is true)
3. Collibra DQ Helm chart

## Setting Up Secrets

### GitHub Repository Secrets

1. Go to your repository → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Add each required secret listed above

### Environment-Specific Secrets

You can also set secrets per environment (dev/prod):
1. Go to Settings → Environments
2. Create environments: `dev` and `prod`
3. Add environment-specific secrets

## Workflow Features

### Automatic Plan on PR
- Pull requests automatically run `terragrunt plan`
- Plan output is commented on the PR
- Plan artifacts are uploaded for review

### Manual Deployment
- Use workflow dispatch for manual deployments
- Choose environment, region, and action
- Supports plan, apply, and destroy actions

### Verification Steps
- Automatically configures kubectl for EKS
- Verifies deployment after apply
- Shows pod and service status

## Troubleshooting

### Workflow Fails at AWS Credentials
- Verify `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set correctly
- Ensure AWS credentials have necessary permissions

### Workflow Fails at EKS Configuration
- Verify EKS cluster exists for the selected environment
- Check cluster name follows naming convention: `{org}-{env}-eks`

### Workflow Fails at Secret Verification
- Ensure all required secrets are set
- Check secret names match exactly (case-sensitive)

### RDS Deployment Takes Too Long
- RDS creation typically takes 10-15 minutes
- This is normal AWS behavior
- Workflow will wait for completion

## Best Practices

1. **Always run plan first**: Use `plan` action before `apply` to review changes
2. **Use PRs for changes**: Let PRs run plan automatically before merging
3. **Environment protection**: Use GitHub environment protection rules for prod
4. **Review plans**: Always review plan output before applying
5. **Monitor deployments**: Check workflow logs and Kubernetes resources after deployment
