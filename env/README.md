# Terragrunt configuration (`env/`)

This folder contains the shared Terragrunt configuration and the live ("apply-able") Terragrunt stacks.

## Key files

- `env/root.hcl`
  - The global Terragrunt configuration.
  - Responsibilities:
    - Read environment/region definitions from `env/env.hcl`
    - Compute common values (org, tags, naming, modules_root)
    - Configure `remote_state` (S3 backend + DynamoDB locking)
    - Safety checks (environment validity, region validity, account validation)

- `env/env.hcl`
  - Environment definitions (e.g. `dev`, `prod`) and shared defaults.
  - `deploy-stack.sh` / `destroy-stack.sh` use `TF_VAR_environment` to choose the active environment.

- `env/common.hcl`
  - Common Terragrunt `generate` blocks.
  - Generates a minimal `provider.tf` and an empty Terraform `backend` block.

- `env/region.hcl`
  - Legacy region-level shared configuration (used by older folder layouts).
  - Stack-first configs in `env/stack/` typically include `env/root.hcl` directly instead.

## Live stacks

All live Terragrunt configs (the things you actually `terragrunt apply`) are under:

- `env/stack/`

See `env/stack/README.md`.
