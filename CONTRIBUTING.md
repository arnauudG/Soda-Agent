# Contributing to DQ-Infrastructures

This document describes how to contribute to this repository and how to prepare a release.

## Branching Strategy

This project follows **Trunk-Based Development** with optional release branches.

- **`main`** is always stable and releasable. Do **not** commit directly to `main`.
- All changes must be made on **short-lived feature branches**.
- Feature branches must be merged via **Pull Requests** (PRs).
- **Release branches** (`release/x.y.z`) are allowed only for stabilization (e.g. release/1.0.0). Ask before creating one.
- There is no long-lived `develop` branch.

## Commit Messages

All commit messages must follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification.

**Format:** `<type>(optional scope): <description>`

**Allowed types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`, `build`, `revert`

**Rules:**

- Description must be concise and imperative (e.g. "Add ALB timeout" not "Added ALB timeout").
- Scope is optional; if present it must be in parentheses (e.g. `feat(alb): add destroy timeout`).
- Avoid vague messages like "update", "fix stuff", or "changes".

**Examples:**

```
feat(collibra-dq): add TF_INPUT=0 for non-interactive destroy
fix(destroy-stack): handle state lock in ALB destroy
docs: update README quick start
chore: bump terraform-aws-modules/alb to 9.x
```

## Pull Requests

- Explain **why** the change exists, not only **what** changed.
- Keep PRs small and focused. Do not mix unrelated concerns in one PR.
- PRs are the primary review and decision artifact. Use them as self-review checkpoints when working alone; treat PR descriptions as long-term documentation.

## Pre-commit

Before pushing, run:

```bash
pre-commit install
pre-commit run --all-files
```

This runs trailing-whitespace checks, YAML/JSON checks, Terraform `fmt`/`validate`/`tflint`, and private-key detection. Fix any reported issues before opening a PR.

## Release Checklist (Before You Ship)

Use this checklist when preparing a release or before merging to `main`:

1. **Environment**
   - [ ] `scripts/set-env.example.sh` exists and is up to date (no secrets; only placeholders).
   - [ ] `scripts/set-env.sh` is **not** committed (git-ignored).
   - [ ] No secrets in the repository (search for API keys, passwords, tokens).

2. **Validation**
   - [ ] `pre-commit run --all-files` passes.
   - [ ] `./scripts/test-terragrunt.sh` passes (Terragrunt config validation).
   - [ ] `./scripts/test-modules.sh` passes (Terraform module validation), if applicable.
   - [ ] `./scripts/validate-env.sh <stack> <env>` succeeds for the stacks you support.

3. **Documentation**
   - [ ] README.md is accurate (prerequisites, quick start, env vars, troubleshooting).
   - [ ] CONTRIBUTING.md is up to date.
   - [ ] `env/stack/README.md` and stack-specific READMEs reflect current module layout.
   - [ ] No broken links or references to removed files (e.g. old script names).

4. **Deploy/Destroy (recommended)**
   - [ ] Full deploy and destroy test for at least one stack (e.g. `collibra-dq` or `soda-agent`) in a non-production environment, if feasible.

5. **Branch and PR**
   - [ ] Changes are on a feature branch, not directly on `main`.
   - [ ] PR description explains the change and why it was made.
   - [ ] Commits follow Conventional Commits.

## Getting Help

- **README**: [README.md](README.md) — overview, quick start, deployment, env vars, troubleshooting.
- **Scripts**: [scripts/README.md](scripts/README.md) — validate-env, test-terragrunt, verify-soda-keys.
- **Stacks**: [env/stack/README.md](env/stack/README.md) — module map; stack-specific READMEs under `env/stack/<stack>/`.
