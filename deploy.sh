#!/bin/bash

# Soda Infrastructure Deployment Script
# This script deploys the infrastructure in the correct dependency order

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if environment is provided
if [ $# -eq 0 ]; then
    print_error "Usage: $0 <environment> [phase]"
    print_error "Environment: dev, prod"
    print_error "Phase: 1-7 (optional, deploy specific phase only)"
    print_error "Example: $0 prod        # Deploy all phases"
    print_error "Example: $0 prod 3      # Deploy phase 3 only (Security Group - Ops)"
    exit 1
fi

ENVIRONMENT=$1
PHASE=${2:-0}  # Default to 0 (all phases)

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|prod)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT"
    print_error "Valid environments: dev, prod"
    exit 1
fi

# Validate phase
if [ $PHASE -ne 0 ] && [ $PHASE -lt 1 -o $PHASE -gt 7 ]; then
    print_error "Invalid phase: $PHASE"
    print_error "Valid phases: 1-7"
    exit 1
fi

print_status "Deploying to environment: $ENVIRONMENT"
if [ $PHASE -ne 0 ]; then
    print_status "Deploying phase: $PHASE only"
fi

# Set base directory
BASE_DIR="env/$ENVIRONMENT/eu-west-1"
cd "$BASE_DIR" || {
    print_error "Environment directory not found: $BASE_DIR"
    exit 1
}

print_status "Working directory: $(pwd)"

# Function to deploy a module
deploy_module() {
    local module_path=$1
    local module_name=$2
    
    print_status "Deploying $module_name..."
    cd "$module_path" || {
        print_error "Module directory not found: $module_path"
        exit 1
    }
    
    terragrunt apply --auto-approve
    print_success "$module_name deployed successfully"
    
    cd - > /dev/null
}

# Function to deploy a specific phase
deploy_phase() {
    local phase=$1
    
    case $phase in
        1)
            print_status "Phase 1: Deploying VPC..."
            deploy_module "network/vpc" "VPC"
            ;;
        2)
            print_status "Phase 2: Deploying VPC Endpoints..."
            deploy_module "network/vpc-endpoints" "VPC Endpoints"
            ;;
        3)
            print_status "Phase 3: Deploying Ops Infrastructure..."
            deploy_module "ops/sg-ops" "Security Groups"
            ;;
        4)
            print_status "Phase 4: Deploying EKS Cluster..."
            deploy_module "eks" "EKS Cluster"
            ;;
        5)
            print_status "Phase 5: Deploying Ops Infrastructure..."
            deploy_module "ops/ec2-ops" "EC2 Ops Instance"
            ;;
        6)
            print_status "Phase 6: Deploying EKS Access Configuration..."
            deploy_module "eks/ops-ec2-eks-access" "EKS Access"
            ;;
        7)
            print_status "Phase 7: Deploying Soda Agent..."
            deploy_module "addons/soda-agent" "Soda Agent"
            ;;
        *)
            print_error "Invalid phase: $phase"
            exit 1
            ;;
    esac
}

# Main deployment logic
if [ $PHASE -eq 0 ]; then
    print_status "Deploying all phases in order..."
    
    # Phase 1: VPC
    deploy_phase 1
    
    # Phase 2: VPC Endpoints
    deploy_phase 2

    # Phase 3: Security Group Ops
    deploy_phase 3
    
    # Phase 4: EKS Cluster
    deploy_phase 4
    
    # Phase 5: Ops Infrastructure
    deploy_phase 5
    
    # Phase 6: EKS Access Configuration
    deploy_phase 6
    
    # Phase 7: Soda Agent
    deploy_phase 7
    
    print_success "All phases deployed successfully!"
else
    deploy_phase $PHASE
fi

print_status "Deployment completed successfully!"
print_status "Environment: $ENVIRONMENT"
print_status "Current directory: $(pwd)"
