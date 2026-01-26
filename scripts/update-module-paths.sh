#!/bin/bash
# update-module-paths.sh - Update Terragrunt configs to use new module paths

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

ENV=${1:-dev}

echo "🔄 Updating module paths in Terragrunt configs for $ENV..."
echo ""

# Function to update path in file
update_path() {
    local file=$1
    local old_path=$2
    local new_path=$3
    
    if grep -q "$old_path" "$file" 2>/dev/null; then
        echo "  📝 Updating $file: $old_path → $new_path"
        
        # Use sed to replace paths (works on macOS and Linux)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|${old_path}|${new_path}|g" "$file"
        else
            sed -i "s|${old_path}|${new_path}|g" "$file"
        fi
        
        return 0
    fi
    return 1
}

# Find all terragrunt.hcl files
TERRAGRUNT_FILES=$(find "env/$ENV" -name "terragrunt.hcl" -type f)

UPDATED=0

for file in $TERRAGRUNT_FILES; do
    UPDATED_FILE=0
    
    # Update each path mapping (compatible with bash 3.2+)
    update_path "$file" "vpc-network" "network/vpc" && UPDATED_FILE=1
    update_path "$file" "vpc-endpoints" "network/vpc-endpoints" && UPDATED_FILE=1
    update_path "$file" "security-group-ops" "security/security-group/ops" && UPDATED_FILE=1
    update_path "$file" "ops-ec2-eks-access" "security/iam/ops-eks-access" && UPDATED_FILE=1
    update_path "$file" "ec2-ops-instance" "compute/ec2/ops" && UPDATED_FILE=1
    update_path "$file" "eks-cluster" "compute/eks/cluster" && UPDATED_FILE=1
    update_path "$file" "helm-soda-agent" "application/helm/soda-agent" && UPDATED_FILE=1
    
    if [ $UPDATED_FILE -eq 1 ]; then
        echo "    ✅ Updated"
        UPDATED=1
    fi
done

echo ""
if [ $UPDATED -eq 1 ]; then
    echo "✅ Module paths updated!"
    echo ""
    echo "⚠️  Next steps:"
    echo "  1. Review changes: git diff"
    echo "  2. Test: ./scripts/test-terragrunt.sh $ENV"
    echo "  3. Commit changes"
else
    echo "ℹ️  No files needed updating (paths may already be correct)"
fi
