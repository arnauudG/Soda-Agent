#!/usr/bin/env bash
# Example environment file for deploy-stack.sh / destroy-stack.sh.
#
# Usage:
#   cp scripts/set-env.example.sh scripts/set-env.sh
#   edit scripts/set-env.sh
#   source scripts/set-env.sh
#   ./deploy-stack.sh soda-agent
#
# Notes:
# - scripts/set-env.sh is git-ignored (do not commit secrets).
# - These exports apply to the *current shell*, so you must source the file.

set -a

# -----------------------------------------------------------------------------
# Required for all deployments
# -----------------------------------------------------------------------------
export TF_VAR_environment=dev          # dev or prod
export TF_VAR_region=eu-west-1         # eu-west-1, us-east-1, eu-central-1

# AWS credentials (choose one approach)
export AWS_PROFILE=your-aws-profile
# OR:
# export AWS_ACCESS_KEY_ID=your-access-key
# export AWS_SECRET_ACCESS_KEY=your-secret-key
# unset AWS_PROFILE   # if using access keys, unset profile

# Optional safety: fail if you are authenticated to the wrong AWS account
# export TG_EXPECTED_ACCOUNT_ID=123456789012

# -----------------------------------------------------------------------------
# Soda Agent stack (required when deploying soda-agent without --skip-addons)
# -----------------------------------------------------------------------------
# Get these from Soda Cloud: Data Sources → Agents → New Soda Agent
# (Do NOT use Profile → API Keys; those are human user keys and will 403.)
#
# export SODA_API_KEY_ID=your-soda-api-key-id
# export SODA_API_KEY_SECRET=your-soda-api-key-secret
#
# Optional Soda settings
# export SODA_CLOUD_REGION=eu              # eu or us
# export SODA_LOG_LEVEL=INFO
# export SODA_LOG_FORMAT=raw
# export SODA_AGENT_ID=                    # Existing agent UUID when redeploying (Agents → agent → ID in URL)
# export SODA_IMAGE_APIKEY_ID=             # Only if Soda gave separate registry credentials
# export SODA_IMAGE_APIKEY_SECRET=

# -----------------------------------------------------------------------------
# Collibra DQ stack (required when deploying collibra-dq without --skip-addons)
# -----------------------------------------------------------------------------
# export COLLIBRA_DQ_ADMIN_PASSWORD=
# export COLLIBRA_DQ_LICENSE_KEY=
#
# Optional Collibra DQ settings
# export COLLIBRA_DQ_VERSION=2024.11.0
# export COLLIBRA_DQ_ALLOWED_CIDR=10.0.0.0/8
# export COLLIBRA_DQ_RDS_PASSWORD=         # Leave empty for auto-generated

set +a
