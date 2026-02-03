# Soda Agent add-on (EKS)

This folder deploys the Soda Agent into the EKS cluster using the Terraform Helm provider.

## What it deploys

- Kubernetes namespace (default: `soda-agent`)
- Helm release for the Soda Agent chart
- Image pull secret configuration (optional, defaults to Soda API keys)

## Prerequisites

- Core infrastructure deployed (at minimum):
  - `env/stack/eks`

## Environment variables

Required (unless you deploy core-only with `--skip-addons`):

- `SODA_API_KEY_ID`
- `SODA_API_KEY_SECRET`

Optional:

- `SODA_CLOUD_REGION` (`eu` or `us`, default: `eu`)
- `SODA_LOG_LEVEL` (default: `INFO`)
- `SODA_LOG_FORMAT` (`raw` or `json`, default: `raw`)
- `SODA_IMAGE_APIKEY_ID` (defaults to `SODA_API_KEY_ID`)
- `SODA_IMAGE_APIKEY_SECRET` (defaults to `SODA_API_KEY_SECRET`)

## Deploy

Recommended (orchestrated):

```bash
./deploy-stack.sh soda-agent
```

Core-only (skips this add-on):

```bash
./deploy-stack.sh soda-agent --skip-addons
```

Direct (advanced):

```bash
cd env/stack/addons/soda-agent
terragrunt apply
```

## Destroy

```bash
./destroy-stack.sh soda-agent
```

Core-only (keeps add-ons intact):

```bash
./destroy-stack.sh soda-agent --skip-addons
```

## Verify

Get the cluster name:

```bash
cd env/stack/eks
terragrunt output -raw cluster_name
```

Configure kubeconfig:

```bash
aws eks update-kubeconfig --name <cluster_name> --region "$TF_VAR_region"
```

Check pods:

```bash
kubectl -n soda-agent get pods
kubectl -n soda-agent logs deploy/soda-agent
```

## Troubleshooting

- Missing API keys: ensure `SODA_API_KEY_ID` and `SODA_API_KEY_SECRET` are set.
- Cluster not reachable: make sure `env/stack/eks` is deployed and your AWS credentials allow EKS access.

### Namespace stuck in Terminating

Some chart-created Jobs can leave finalizers behind and block namespace deletion.

If `kubectl get ns soda-agent` shows `Terminating` and mentions remaining `jobs.batch` with a finalizer, you can remove the Job finalizer and/or force-finalize the namespace.

Example (replace job name as needed):

```bash
kubectl -n soda-agent get jobs
kubectl -n soda-agent patch job <job-name> -p '{"metadata":{"finalizers":[]}}' --type=merge
```

If the namespace still won’t delete:

```bash
kubectl get ns soda-agent -o json > /tmp/soda-agent-ns.json
python - <<'PY'
import json
p=\"/tmp/soda-agent-ns.json\"
data=json.load(open(p))
data[\"spec\"][\"finalizers\"]=[]
open(p,\"w\").write(json.dumps(data))
PY
kubectl replace --raw \"/api/v1/namespaces/soda-agent/finalize\" -f /tmp/soda-agent-ns.json
```
