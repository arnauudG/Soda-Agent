#!/bin/bash

# Soda Infrastructure Destruction Script
# This script destroys the infrastructure in the reverse dependency order

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
    print_error "Environment: dev, prod, gen"
    print_error "Phase: 1-7 (optional, destroy specific phase only)"
    print_error "Example: $0 prod        # Destroy all phases"
    print_error "Example: $0 prod 7      # Destroy phase 7 only (Soda Agent)"
    exit 1
fi

ENVIRONMENT=$1
PHASE=${2:-0}  # Default to 0 (all phases)

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|prod|gen)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT"
    print_error "Valid environments: dev, prod, gen"
    exit 1
fi

# Validate phase
if [ $PHASE -ne 0 ] && [ $PHASE -lt 1 -o $PHASE -gt 7 ]; then
    print_error "Invalid phase: $PHASE"
    print_error "Valid phases: 1-7"
    exit 1
fi

print_status "Destroying infrastructure in environment: $ENVIRONMENT"
if [ $PHASE -ne 0 ]; then
    print_status "Destroying phase: $PHASE only"
fi

# Set base directory
BASE_DIR="env/$ENVIRONMENT/eu-west-1"
cd "$BASE_DIR" || {
    print_error "Environment directory not found: $BASE_DIR"
    exit 1
}

print_status "Working directory: $(pwd)"

# Function to destroy a module
destroy_module() {
    local module_path=$1
    local module_name=$2
    
    print_status "Destroying $module_name..."
    cd "$module_path" || {
        print_error "Module directory not found: $module_path"
        exit 1
    }
    
    terragrunt destroy --auto-approve
    print_success "$module_name destroyed successfully"
    
    cd - > /dev/null
}

# Function to destroy a specific phase
destroy_phase() {
    local phase=$1
    
    case $phase in
        7)
            print_status "Phase 7: Destroying Soda Agent..."
            destroy_module "addons/soda-agent" "Soda Agent"
            ;;
        6)
            print_status "Phase 6: Destroying EKS Access Configuration..."
            destroy_module "eks/ops-ec2-eks-access" "EKS Access"
            ;;
        5)
            print_status "Phase 5: Destroying Ops Infrastructure..."
            destroy_module "ops/ec2-ops" "EC2 Ops Instance"
            ;;
        4)
            print_status "Phase 4: Destroying EKS Cluster..."
            destroy_module "eks" "EKS Cluster"
            ;;

        3)
            print_status "Phase 3: Destroying Security Group Ops Infrastructure..."
            destroy_module "ops/sg-ops" "Security Groups"
            ;;

        2)
            print_status "Phase 2: Destroying VPC Endpoints..."
            destroy_module "network/vpc-endpoints" "VPC Endpoints"
            ;;
        1)
            print_status "Phase 1: Destroying VPC..."
            destroy_module "network/vpc" "VPC"
            ;;
        *)
            print_error "Invalid phase: $phase"
            exit 1
            ;;
    esac
}

# Main destruction logic
if [ $PHASE -eq 0 ]; then
    print_warning "This will destroy ALL infrastructure in the $ENVIRONMENT environment!"
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Destruction cancelled"
        exit 0
    fi
    
    print_status "Destroying all phases in reverse order..."
    
    # Phase 7: Soda Agent
    destroy_phase 7
    
    # Phase 6: EKS Access Configuration
    destroy_phase 6
    
    # Phase 5: Ops Infrastructure
    destroy_phase 5
    
    # Phase 4: EKS Cluster
    destroy_phase 4

    # Phase 3: Security Group Ops
    destroy_phase 3
    
    # Phase 2: VPC Endpoints
    destroy_phase 2
    
    # Phase 1: VPC
    destroy_phase 1
    
    print_success "All phases destroyed successfully!"
else
    destroy_phase $PHASE
fi

print_status "Destruction completed successfully!"
print_status "Environment: $ENVIRONMENT"
print_status "Current directory: $(pwd)"
