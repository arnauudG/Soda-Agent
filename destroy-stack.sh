#!/bin/bash

# Unified Stack Destruction Script
# Destroys either Soda Agent or Collibra DQ Standalone stack
# Handles bootstrap carefully (only destroys if no other stack uses it)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Usage
if [ $# -lt 2 ]; then
    print_error "Usage: $0 <stack> <environment> [--destroy-bootstrap]"
    print_error "Stack: soda-agent | collibra-dq"
    print_error "Environment: dev | prod"
    print_error ""
    print_error "Examples:"
    print_error "  $0 soda-agent dev              # Destroy Soda Agent stack (keeps bootstrap)"
    print_error "  $0 collibra-dq prod           # Destroy Collibra DQ stack (keeps bootstrap)"
    print_error "  $0 soda-agent dev --destroy-bootstrap  # Also destroy bootstrap (use with caution!)"
    exit 1
fi

STACK=$1
ENVIRONMENT=$2
DESTROY_BOOTSTRAP=${3:-}

# Validate inputs
if [[ ! "$STACK" =~ ^(soda-agent|collibra-dq)$ ]]; then
    print_error "Invalid stack: $STACK"
    print_error "Valid stacks: soda-agent, collibra-dq"
    exit 1
fi

if [[ ! "$ENVIRONMENT" =~ ^(dev|prod)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT"
    print_error "Valid environments: dev, prod"
    exit 1
fi

BASE_DIR="env/$ENVIRONMENT/eu-west-1"

# Check if module exists
check_module_exists() {
    local module_path=$1
    cd "$BASE_DIR/$module_path" 2>/dev/null || return 1
    terragrunt output -json >/dev/null 2>&1
    local result=$?
    cd - >/dev/null
    return $result
}

# Check if other stack exists
check_other_stack_exists() {
    local other_stack=$1
    case $other_stack in
        soda-agent)
            check_module_exists "addons/soda-agent"
            ;;
        collibra-dq)
            check_module_exists "addons/collibra-dq-standalone"
            ;;
    esac
}

# Destroy module helper
destroy_module() {
    local module_path=$1
    local module_name=$2
    
    if ! check_module_exists "$module_path"; then
        print_warning "$module_name not found, skipping..."
        return 0
    fi
    
    print_status "Destroying $module_name..."
    cd "$BASE_DIR/$module_path" || {
        print_error "Module directory not found: $BASE_DIR/$module_path"
        exit 1
    }
    
    terragrunt destroy --auto-approve
    print_success "$module_name destroyed successfully"
    
    cd - >/dev/null
}

# Destroy Soda Agent stack
destroy_soda_agent() {
    print_warning "This will destroy the Soda Agent stack in $ENVIRONMENT environment!"
    read -p "Are you sure? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Destruction cancelled"
        exit 0
    fi
    
    print_status "Destroying Soda Agent stack..."
    
    # Phase 7: Soda Agent
    destroy_module "addons/soda-agent" "Soda Agent"
    
    # Phase 6: EKS Access Configuration
    destroy_module "eks/ops-ec2-eks-access" "EKS Access Configuration"
    
    # Phase 5: EC2 Ops Instance
    destroy_module "ops/ec2-ops" "EC2 Ops Instance"
    
    # Phase 4: EKS Cluster
    destroy_module "eks" "EKS Cluster"
    
    # Phase 3: Security Groups (Ops)
    destroy_module "ops/sg-ops" "Security Groups (Ops)"
    
    # Phase 2: VPC Endpoints (only if Collibra DQ doesn't exist)
    if ! check_other_stack_exists "collibra-dq"; then
        destroy_module "network/vpc-endpoints" "VPC Endpoints"
    else
        print_warning "VPC Endpoints still in use by Collibra DQ, skipping..."
    fi
    
    # Phase 1: VPC (only if Collibra DQ doesn't exist)
    if ! check_other_stack_exists "collibra-dq"; then
        destroy_module "network/vpc" "VPC"
    else
        print_warning "VPC still in use by Collibra DQ, skipping..."
    fi
    
    print_success "Soda Agent stack destroyed successfully!"
}

# Destroy Collibra DQ stack
destroy_collibra_dq() {
    print_warning "This will destroy the Collibra DQ Standalone stack in $ENVIRONMENT environment!"
    read -p "Are you sure? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Destruction cancelled"
        exit 0
    fi
    
    print_status "Destroying Collibra DQ Standalone stack..."
    
    # Phase 10: Target Group Attachment
    destroy_module "addons/collibra-dq-standalone/alb/target-group-attachment" "Target Group Attachment"
    
    # Phase 9: Application Load Balancer
    destroy_module "addons/collibra-dq-standalone/alb" "Application Load Balancer"
    
    # Phase 8: ALB Security Group
    destroy_module "addons/collibra-dq-standalone/alb/sg-alb" "ALB Security Group"
    
    # Phase 7: EC2 Instance
    destroy_module "addons/collibra-dq-standalone" "Collibra DQ EC2 Instance"
    
    # Phase 6: Package Upload
    destroy_module "addons/collibra-dq-standalone/package-upload" "Package Upload (S3)"
    
    # Phase 5: Collibra DQ Security Group
    destroy_module "addons/collibra-dq-standalone/sg-collibra-dq" "Collibra DQ Security Group"
    
    # Phase 4: RDS Database
    destroy_module "database/rds-collibra-dq/rds" "RDS PostgreSQL Database"
    
    # Phase 3: RDS Security Group
    destroy_module "database/rds-collibra-dq/sg-rds" "RDS Security Group"
    
    # Phase 2: VPC Endpoints (only if Soda Agent doesn't exist)
    if ! check_other_stack_exists "soda-agent"; then
        destroy_module "network/vpc-endpoints" "VPC Endpoints"
    else
        print_warning "VPC Endpoints still in use by Soda Agent, skipping..."
    fi
    
    # Phase 1: VPC (only if Soda Agent doesn't exist)
    if ! check_other_stack_exists "soda-agent"; then
        destroy_module "network/vpc" "VPC"
    else
        print_warning "VPC still in use by Soda Agent, skipping..."
    fi
    
    print_success "Collibra DQ Standalone stack destroyed successfully!"
}

# Handle bootstrap destruction
handle_bootstrap() {
    if [ "$DESTROY_BOOTSTRAP" != "--destroy-bootstrap" ]; then
        print_status "Bootstrap preserved (shared resource)"
        return 0
    fi
    
    # Check if other stack exists
    local other_stack=""
    if [ "$STACK" = "soda-agent" ]; then
        other_stack="collibra-dq"
    else
        other_stack="soda-agent"
    fi
    
    if check_other_stack_exists "$other_stack"; then
        print_error "Cannot destroy bootstrap: $other_stack stack still exists!"
        print_error "Destroy $other_stack stack first, or remove --destroy-bootstrap flag"
        exit 1
    fi
    
    print_warning "Destroying bootstrap (this will delete all Terraform state!)"
    read -p "Type 'DESTROY BOOTSTRAP' to confirm: " -r
    if [ "$REPLY" != "DESTROY BOOTSTRAP" ]; then
        print_status "Bootstrap destruction cancelled"
        return 0
    fi
    
    cd "$BASE_DIR/bootstrap" || {
        print_error "Bootstrap directory not found"
        exit 1
    }
    
    terragrunt destroy --auto-approve
    print_success "Bootstrap destroyed successfully"
    
    cd - >/dev/null
}

# Main destruction logic
print_status "Destroying $STACK stack in $ENVIRONMENT environment..."

case $STACK in
    soda-agent)
        destroy_soda_agent
        ;;
    collibra-dq)
        destroy_collibra_dq
        ;;
    *)
        print_error "Unknown stack: $STACK"
        exit 1
        ;;
esac

# Handle bootstrap
handle_bootstrap

print_success "Destruction completed successfully!"
print_status "Stack: $STACK"
print_status "Environment: $ENVIRONMENT"
