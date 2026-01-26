#!/bin/bash
# test-modules.sh - Quick validation of all modules

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "🔍 Validating all modules..."

# Find all module directories with main.tf
MODULE_DIRS=$(find module -type f -name "main.tf" | xargs dirname | sort -u)

VALIDATION_FAILED=0

for module_dir in $MODULE_DIRS; do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Validating: $module_dir"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd "$module_dir"
    
    # Initialize Terraform
    if ! terraform init -backend=false -input=false > /dev/null 2>&1; then
        echo "❌ Failed to initialize: $module_dir"
        VALIDATION_FAILED=1
        cd "$PROJECT_ROOT"
        continue
    fi
    
    # Validate syntax
    if ! terraform validate > /dev/null 2>&1; then
        echo "❌ Validation failed: $module_dir"
        terraform validate
        VALIDATION_FAILED=1
    else
        echo "✅ Syntax valid"
    fi
    
    # Check formatting
    if ! terraform fmt -check -recursive > /dev/null 2>&1; then
        echo "⚠️  Formatting issues found (run 'terraform fmt')"
    else
        echo "✅ Formatting OK"
    fi
    
    cd "$PROJECT_ROOT"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $VALIDATION_FAILED -eq 0 ]; then
    echo "✅ All modules validated successfully!"
    exit 0
else
    echo "❌ Some modules failed validation"
    exit 1
fi
