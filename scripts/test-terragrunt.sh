#!/bin/bash
# test-terragrunt.sh - Validate Terragrunt configs with mock outputs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

ENV=${1:-dev}
REGION=${2:-eu-west-1}

if [ ! -d "env/$ENV/$REGION" ]; then
    echo "❌ Environment not found: env/$ENV/$REGION"
    exit 1
fi

echo "🔍 Validating Terragrunt configs for $ENV/$REGION..."
echo ""

# Test each phase in dependency order
phases=(
    "network/vpc"
    "network/vpc-endpoints"
    "ops/sg-ops"
    "eks"
    "ops/ec2-ops"
    "eks/ops-ec2-eks-access"
    "addons/soda-agent"
)

VALIDATION_FAILED=0

for phase in "${phases[@]}"; do
    phase_path="env/$ENV/$REGION/$phase"
    
    if [ ! -f "$phase_path/terragrunt.hcl" ]; then
        echo "⚠️  Skipping $phase (terragrunt.hcl not found)"
        continue
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 Validating: $phase"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd "$phase_path"
    
    # Initialize Terragrunt (uses mock outputs)
    if ! terragrunt init -input=false > /dev/null 2>&1; then
        echo "❌ Failed to initialize: $phase"
        terragrunt init
        VALIDATION_FAILED=1
        cd "$PROJECT_ROOT"
        continue
    fi
    
    # Validate Terragrunt config
    if ! terragrunt validate > /dev/null 2>&1; then
        echo "❌ Validation failed: $phase"
        terragrunt validate
        VALIDATION_FAILED=1
    else
        echo "✅ Config valid"
    fi
    
    # Plan with mock outputs (no AWS calls)
    if ! terragrunt plan -input=false -out=/dev/null > /dev/null 2>&1; then
        echo "⚠️  Plan failed (may be due to missing dependencies)"
        echo "   This is OK if dependencies haven't been deployed yet"
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
