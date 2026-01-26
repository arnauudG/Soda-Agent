#!/bin/bash
# reorganize-modules.sh - Reorganize modules by domain

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "🔄 Reorganizing modules by domain..."
echo ""

# Create domain structure
mkdir -p module/network/vpc/submodules
mkdir -p module/network/vpc-endpoints/submodules
mkdir -p module/security/security-group/ops
mkdir -p module/security/iam/ops-eks-access
mkdir -p module/compute/ec2/ops/submodules
mkdir -p module/compute/eks/cluster/submodules
mkdir -p module/application/helm/soda-agent

echo "📁 Created domain structure"
echo ""

# Move modules to appropriate domains
echo "📦 Moving modules..."

# Network domain
if [ -d "module/vpc-network" ]; then
    echo "  → Moving vpc-network → network/vpc"
    mv module/vpc-network/* module/network/vpc/ 2>/dev/null || true
    rmdir module/vpc-network 2>/dev/null || true
fi

if [ -d "module/vpc-endpoints" ]; then
    echo "  → Moving vpc-endpoints → network/vpc-endpoints"
    mv module/vpc-endpoints/* module/network/vpc-endpoints/ 2>/dev/null || true
    rmdir module/vpc-endpoints 2>/dev/null || true
fi

# Security domain
if [ -d "module/security-group-ops" ]; then
    echo "  → Moving security-group-ops → security/security-group/ops"
    mv module/security-group-ops/* module/security/security-group/ops/ 2>/dev/null || true
    rmdir module/security-group-ops 2>/dev/null || true
fi

if [ -d "module/ops-ec2-eks-access" ]; then
    echo "  → Moving ops-ec2-eks-access → security/iam/ops-eks-access"
    mv module/ops-ec2-eks-access/* module/security/iam/ops-eks-access/ 2>/dev/null || true
    rmdir module/ops-ec2-eks-access 2>/dev/null || true
fi

# Compute domain
if [ -d "module/ec2-ops-instance" ]; then
    echo "  → Moving ec2-ops-instance → compute/ec2/ops"
    mv module/ec2-ops-instance/* module/compute/ec2/ops/ 2>/dev/null || true
    rmdir module/ec2-ops-instance 2>/dev/null || true
fi

if [ -d "module/eks-cluster" ]; then
    echo "  → Moving eks-cluster → compute/eks/cluster"
    mv module/eks-cluster/* module/compute/eks/cluster/ 2>/dev/null || true
    rmdir module/eks-cluster 2>/dev/null || true
fi

# Application domain
if [ -d "module/helm-soda-agent" ]; then
    echo "  → Moving helm-soda-agent → application/helm/soda-agent"
    mv module/helm-soda-agent/* module/application/helm/soda-agent/ 2>/dev/null || true
    rmdir module/helm-soda-agent 2>/dev/null || true
fi

echo ""
echo "✅ Modules reorganized!"
echo ""
echo "New structure:"
echo "  module/"
echo "  ├── network/"
echo "  │   ├── vpc/"
echo "  │   └── vpc-endpoints/"
echo "  ├── security/"
echo "  │   ├── security-group/ops/"
echo "  │   └── iam/ops-eks-access/"
echo "  ├── compute/"
echo "  │   ├── ec2/ops/"
echo "  │   └── eks/cluster/"
echo "  └── application/"
echo "      └── helm/soda-agent/"
echo ""
echo "⚠️  Next steps:"
echo "  1. Update Terragrunt configs to use new module paths"
echo "  2. Update modules_root references if needed"
echo "  3. Run: ./scripts/test-modules.sh"
echo "  4. Run: ./scripts/test-terragrunt.sh dev"
