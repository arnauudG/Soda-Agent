# Scripts

Minimal validation and test helpers. Deploy and destroy entry points are at the repo root: `deploy-stack.sh` and `destroy-stack.sh`. Both scripts set `TF_INPUT=0` and `TG_INPUT=0` so they run non-interactively (CI, background, or piped input).

## Structure

```
scripts/
├── set-env.example.sh        # Template env file (copy to scripts/set-env.sh, git-ignored)
├── validate-env.sh           # Environment variable validation (used by deploy/destroy)
├── verify-soda-keys.sh       # Soda key sanity check (Service Account vs HumanUser reminder)
├── unlock-terraform-lock.sh  # Unlock stale Terraform state lock (module path + lock ID)
├── test-terragrunt.sh        # Terragrunt live config validation under env/stack/** (stack-first)
└── test-modules.sh           # Terraform module validation under module/**
```

## Environment variables

Scripts use whatever is **already in your shell**. They do not load any file.

1. Copy and edit: `cp scripts/set-env.example.sh scripts/set-env.sh`
2. In the same shell: `source scripts/set-env.sh` then run deploy/destroy.

When using access keys (not a profile), ensure `unset AWS_PROFILE` in `set-env.sh` or the shell.

## Usage

### State lock unlock

When Terraform reports "Error acquiring the state lock" (e.g. after a crashed run), unlock only if no other process is using the state. Get the lock ID from the error message, then:

```
./scripts/unlock-terraform-lock.sh <module-path> <lock-id>
```

Example:

```
./scripts/unlock-terraform-lock.sh collibra-dq/network/vpc 58b32bea-b71b-6385-e816-f98ecba14b71
```

`module-path` is relative to `env/stack` (e.g. `collibra-dq/network/vpc`, `soda-agent/eks`).

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

### Soda Agent: verify API keys are set

```
./scripts/verify-soda-keys.sh
```

This is a quick sanity check that `SODA_API_KEY_ID` / `SODA_API_KEY_SECRET` are present and reminds you that they must come from **Data Sources → Agents → New Soda Agent** (Service Account keys).

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

### Soda Agent utilities

The repository intentionally keeps helper scripts minimal. For Soda Agent day-2 operations, use standard AWS CLI + kubectl:

```
export TF_VAR_environment=dev TF_VAR_region=eu-west-1
aws eks update-kubeconfig --name "datashift-${TF_VAR_environment}-soda-agent-eks" --region "$TF_VAR_region"
kubectl get pods -n soda-agent
kubectl logs -n soda-agent <pod> --previous --tail=100
```

### Soda Agent: 403 Invalid user type (HumanUser)

If the soda-agent-orchestrator pod is in CrashLoopBackOff and logs show:

- `Agent registration in Soda Cloud failed` with `403` and `Invalid user type: HumanUser`

then **SODA_API_KEY_ID** and **SODA_API_KEY_SECRET** are **Profile (human user) API keys**. Agent registration requires **Service Account** API keys.

**Fix:**

1. In Soda Cloud go to **Data Sources → Agents → New Soda Agent** (or edit an existing agent).
2. Create or copy **Service Account** API keys (not Profile → API Keys).
3. Set `SODA_API_KEY_ID` and `SODA_API_KEY_SECRET` to those values, then redeploy or restart the agent (e.g. update the Kubernetes secret and delete the orchestrator pod so it restarts with the new keys).

Verify key type with: `./scripts/verify-soda-keys.sh` (it reminds you that keys must be Service Account keys).

### Soda Agent: agent name already registered (CrashLoopBackOff)

If the soda-agent-orchestrator pod is in CrashLoopBackOff and logs show:

- `agent with name datashift-dev-agent already registered` or `agent_name_already_exists`

then Soda Cloud already has an agent with that name (e.g. from a previous deployment or "New Soda Agent" setup). The orchestrator tries to register a new agent and fails.

**Fix – use the existing agent:**

1. In Soda Cloud go to **Agents** (or **Data Sources → Agents**), find the agent named e.g. `datashift-dev-agent`.
2. Open the agent and copy its **Agent ID** from the URL (e.g. `https://cloud.soda.io/agents/842feab3-...-06d2813a72c1` → ID is the UUID).
3. Set `SODA_AGENT_ID` to that UUID and redeploy:

   ```bash
   export SODA_AGENT_ID="<uuid-from-soda-cloud>"
   export TF_VAR_environment=dev TF_VAR_region=eu-west-1
   cd env/stack/soda-agent/addons/soda-agent
   terragrunt apply -auto-approve
   ```

4. Or redeploy the full stack with the env var set: `SODA_AGENT_ID=... ./deploy-stack.sh soda-agent`.

To view crash logs: use `kubectl logs` (see above).

### Helm operations stuck (pending-install / pending-upgrade)

If Helm gets stuck, use standard Helm troubleshooting:

```
helm list -n soda-agent -a
helm uninstall soda-agent -n soda-agent
```

## Documentation

- **Root:** [README.md](../README.md) — project overview, deployment, env vars, troubleshooting.
- **Contributing:** [CONTRIBUTING.md](../CONTRIBUTING.md) — branching, commits, release checklist.
