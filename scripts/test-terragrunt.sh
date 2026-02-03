#!/bin/bash
# test-terragrunt.sh - Validate Terragrunt live configs under env/stack using mock outputs where configured.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

ENVIRONMENT=${1:-${TF_VAR_environment:-dev}}
REGION=${2:-${TF_VAR_region:-eu-west-1}}

export TF_VAR_environment="$ENVIRONMENT"
export TF_VAR_region="$REGION"

BASE_DIR="env/stack"

if [ ! -d "$BASE_DIR" ]; then
    echo "❌ Stack directory not found: $BASE_DIR"
    exit 1
fi

echo "🔍 Validating Terragrunt configs for env=$ENVIRONMENT region=$REGION (stack-first)"
echo ""

# Test phases in a sensible dependency order.
phases=(
    "bootstrap"

    # Soda Agent stack
    "soda-agent/network/vpc"
    "soda-agent/network/vpc-endpoints"

    "soda-agent/ops/sg-ops"
    "soda-agent/eks"
    "soda-agent/ops/ec2-ops"
    "soda-agent/eks/ops-ec2-eks-access"

    "soda-agent/addons/soda-agent"

    # Collibra DQ stack
    "collibra-dq/network/vpc"
    "collibra-dq/network/vpc-endpoints"

    "collibra-dq/addons/collibra-dq-standalone/alb/sg-alb"
    "collibra-dq/addons/collibra-dq-standalone/sg-collibra-dq"
    "collibra-dq/database/rds-collibra-dq/sg-rds"
    "collibra-dq/database/rds-collibra-dq/rds"
    "collibra-dq/addons/collibra-dq-standalone/package-upload"
    "collibra-dq/addons/collibra-dq-standalone"
    "collibra-dq/addons/collibra-dq-standalone/alb"
    "collibra-dq/addons/collibra-dq-standalone/alb/target-group-attachment"
)

VALIDATION_FAILED=0

for phase in "${phases[@]}"; do
    phase_path="$BASE_DIR/$phase"

    if [ ! -f "$phase_path/terragrunt.hcl" ]; then
        echo "⚠️  Skipping $phase (terragrunt.hcl not found)"
        continue
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 Validating: $phase"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    cd "$phase_path"

    # Initialize Terragrunt (dependency mocks should make init/plan possible without deployed deps).
    if ! terragrunt init -input=false > /dev/null 2>&1; then
        echo "❌ Failed to initialize: $phase"
        terragrunt init
        VALIDATION_FAILED=1
        cd "$PROJECT_ROOT"
        continue
    fi

    if ! terragrunt validate > /dev/null 2>&1; then
        echo "❌ Validation failed: $phase"
        terragrunt validate
        VALIDATION_FAILED=1
    else
        echo "✅ Config valid"
    fi

    # Plan with mock outputs (may still fail if a module requires real provider/AWS access).
    # We don't persist plan files; this is only a quick sanity check.
    if ! terragrunt plan -input=false -lock=false > /dev/null 2>&1; then
        echo "⚠️  Plan failed (may be due to missing dependencies or missing provider credentials)"
    else
        echo "✅ Plan successful"
    fi

    cd "$PROJECT_ROOT"
    echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $VALIDATION_FAILED -eq 0 ]; then
    echo "✅ All Terragrunt configs validated!"
    exit 0
else
    echo "❌ Some configs failed validation"
    exit 1
fi
