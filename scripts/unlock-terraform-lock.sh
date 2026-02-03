#!/usr/bin/env bash
# Unlock a stale Terraform state lock for a Terragrunt module.
# Use only when you are sure no other Terraform/Terragrunt process is using the state.
#
# Usage: ./scripts/unlock-terraform-lock.sh <module-path> <lock-id>
#   module-path  relative to env/stack (e.g. collibra-dq/network/vpc)
#   lock-id      from the Terraform error (e.g. 58b32bea-b71b-6385-e816-f98ecba14b71)
#
# Example: ./scripts/unlock-terraform-lock.sh collibra-dq/network/vpc 58b32bea-b71b-6385-e816-f98ecba14b71

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR/../env/stack"

if [ $# -lt 2 ]; then
    echo "Usage: $0 <module-path> <lock-id>"
    echo "  module-path  e.g. collibra-dq/network/vpc"
    echo "  lock-id      from Terraform error (ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
    exit 1
fi

MODULE_PATH="$1"
LOCK_ID="$2"
MODULE_DIR="$BASE_DIR/$MODULE_PATH"

if [ ! -d "$MODULE_DIR" ]; then
    echo "Error: Module directory not found: $MODULE_DIR"
    exit 1
fi

cd "$MODULE_DIR"
export TF_INPUT=0
export TG_INPUT=0
terragrunt force-unlock -force "$LOCK_ID"
echo "Unlocked state for $MODULE_PATH"
