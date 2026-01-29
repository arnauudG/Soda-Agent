#!/bin/bash

# Unified Stack Deployment Script
# Deploys either Soda Agent or Collibra DQ Standalone stack
# Handles bootstrap automatically (checks if exists, creates if needed)

set -e
set -o pipefail  # Ensure pipeline failures are detected

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
    print_error "Usage: $0 <stack> <environment>"
    print_error "Stack: soda-agent | collibra-dq"
    print_error "Environment: dev | prod"
    print_error ""
    print_error "Examples:"
    print_error "  $0 soda-agent dev      # Deploy Soda Agent stack"
    print_error "  $0 collibra-dq prod    # Deploy Collibra DQ stack"
    exit 1
fi

STACK=$1
ENVIRONMENT=$2

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

# Get script directory (project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR/env/$ENVIRONMENT/eu-west-1"

# Validate environment variables before deployment
print_status "Validating environment variables..."
if [ -f "$SCRIPT_DIR/scripts/validate-env.sh" ]; then
    if ! "$SCRIPT_DIR/scripts/validate-env.sh" "$STACK" "$ENVIRONMENT"; then
        print_error "Environment validation failed. Please fix the issues above and try again."
        exit 1
    fi
else
    print_warning "validate-env.sh not found, skipping environment validation"
fi

# Check if bootstrap exists
check_bootstrap() {
    local bootstrap_dir="$BASE_DIR/bootstrap"
    local original_dir=$(pwd)
    
    if [ ! -d "$bootstrap_dir" ]; then
        return 1  # Bootstrap directory doesn't exist
    fi
    
    cd "$bootstrap_dir" || return 1
    if terragrunt output -json state_bucket >/dev/null 2>&1; then
        cd "$original_dir" || cd "$SCRIPT_DIR" || true
        return 0  # Bootstrap exists and has outputs
    fi
    
    cd "$original_dir" || cd "$SCRIPT_DIR" || true
    return 1  # Bootstrap directory exists but outputs not available
}

# Deploy bootstrap if needed
deploy_bootstrap() {
    print_status "Checking bootstrap status..."
    if check_bootstrap; then
        print_success "Bootstrap already exists, skipping..."
        return 0
    fi
    
    print_warning "Bootstrap not found. This is required for both stacks."
    print_status "Deploying bootstrap for $ENVIRONMENT environment..."
    
    if [ ! -f "$SCRIPT_DIR/deploy-bootstrap.sh" ]; then
        print_error "deploy-bootstrap.sh not found in $SCRIPT_DIR"
        print_error "Please ensure you're running this script from the project root"
        exit 1
    fi
    
    # Save current directory before calling deploy-bootstrap.sh
    local original_dir=$(pwd)
    
    # Run bootstrap script (it will change directories)
    cd "$SCRIPT_DIR" || exit 1
    "$SCRIPT_DIR/deploy-bootstrap.sh" "$ENVIRONMENT"
    
    # Return to original directory (deploy-bootstrap.sh may have changed it)
    cd "$original_dir" || cd "$SCRIPT_DIR" || true
    
    # Verify bootstrap was created
    if ! check_bootstrap; then
        print_error "Bootstrap deployment failed - outputs not available"
        print_error "Bootstrap may have completed but outputs are not accessible"
        exit 1
    fi
    
    print_success "Bootstrap deployed successfully"
}

# Deploy module helper
deploy_module() {
    local module_path=$1
    local module_name=$2
    
    print_status "Deploying $module_name..."
    cd "$BASE_DIR/$module_path" || {
        print_error "Module directory not found: $BASE_DIR/$module_path"
        exit 1
    }
    
    # Try to apply, if it fails with provider error, initialize and retry
    local log_file="/tmp/terragrunt-output-$$.log"
    local apply_exit_code=0
    
    if ! terragrunt apply --auto-approve 2>&1 | tee "$log_file"; then
        apply_exit_code=${PIPESTATUS[0]}
        
        # Check if it's a provider initialization error
        if grep -q "Required plugins are not installed\|terraform init" "$log_file"; then
            print_warning "Provider initialization needed, running terraform init..."
            terragrunt init -upgrade || true
            print_status "Retrying deployment..."
            if ! terragrunt apply --auto-approve 2>&1 | tee "$log_file"; then
                apply_exit_code=${PIPESTATUS[0]}
                print_error "Failed to deploy $module_name after initialization"
                print_error "Check the log file: $log_file"
                rm -f "$log_file"
                cd "$SCRIPT_DIR" || true
                exit 1
            fi
        else
            print_error "Failed to deploy $module_name"
            print_error "Exit code: $apply_exit_code"
            print_error "Check the log file: $log_file"
            rm -f "$log_file"
            cd "$SCRIPT_DIR" || true
            exit 1
        fi
    fi
    
    rm -f "$log_file"
    
    print_success "$module_name deployed successfully"
    cd "$SCRIPT_DIR" || true
}

# Deploy Soda Agent stack
deploy_soda_agent() {
    print_status "Deploying Soda Agent stack..."
    
    # Bootstrap (shared)
    deploy_bootstrap
    
    # Phase 1: VPC
    deploy_module "network/vpc" "VPC"
    
    # Phase 2: VPC Endpoints
    deploy_module "network/vpc-endpoints" "VPC Endpoints"
    
    # Phase 3: Security Groups (Ops)
    deploy_module "ops/sg-ops" "Security Groups (Ops)"
    
    # Phase 4: EKS Cluster
    deploy_module "eks" "EKS Cluster"
    
    # Phase 5: EC2 Ops Instance
    deploy_module "ops/ec2-ops" "EC2 Ops Instance"
    
    # Phase 6: EKS Access Configuration
    deploy_module "eks/ops-ec2-eks-access" "EKS Access Configuration"
    
    # Phase 7: Soda Agent
    deploy_module "addons/soda-agent" "Soda Agent"
    
    print_success "Soda Agent stack deployed successfully!"
}

# Deploy Collibra DQ stack
deploy_collibra_dq() {
    print_status "Deploying Collibra DQ Standalone stack..."
    
    # Bootstrap (shared)
    deploy_bootstrap
    
    # Phase 1: VPC (if not exists)
    if ! check_module_exists "network/vpc"; then
        deploy_module "network/vpc" "VPC"
    else
        print_status "VPC already exists, skipping..."
    fi
    
    # Phase 2: VPC Endpoints (if not exists)
    if ! check_module_exists "network/vpc-endpoints"; then
        deploy_module "network/vpc-endpoints" "VPC Endpoints"
    else
        print_status "VPC Endpoints already exist, skipping..."
    fi
    
    # Phase 3: Collibra DQ Security Group (deploy before RDS SG since RDS SG depends on it)
    deploy_module "addons/collibra-dq-standalone/sg-collibra-dq" "Collibra DQ Security Group"
    
    # Phase 4: RDS Security Group (depends on Collibra DQ SG)
    deploy_module "database/rds-collibra-dq/sg-rds" "RDS Security Group"
    
    # Phase 5: RDS Database
    deploy_module "database/rds-collibra-dq/rds" "RDS PostgreSQL Database"
    
    # Phase 6: Package Upload
    deploy_module "addons/collibra-dq-standalone/package-upload" "Package Upload (S3)"
    
    # Phase 7: EC2 Instance
    deploy_module "addons/collibra-dq-standalone" "Collibra DQ EC2 Instance"
    
    # Phase 8: ALB Security Group
    deploy_module "addons/collibra-dq-standalone/alb/sg-alb" "ALB Security Group"
    
    # Phase 9: Application Load Balancer
    deploy_module "addons/collibra-dq-standalone/alb" "Application Load Balancer"
    
    # Phase 10: Target Group Attachment
    deploy_module "addons/collibra-dq-standalone/alb/target-group-attachment" "Target Group Attachment"
    
    print_success "Collibra DQ Standalone stack deployed successfully!"
}

# Check if module exists (has state)
check_module_exists() {
    local module_path=$1
    local original_dir=$(pwd)
    cd "$BASE_DIR/$module_path" 2>/dev/null || return 1
    terragrunt output -json >/dev/null 2>&1
    local result=$?
    cd "$original_dir" || cd "$SCRIPT_DIR" || true
    return $result
}

# Main deployment logic
print_status "Deploying $STACK stack to $ENVIRONMENT environment..."

case $STACK in
    soda-agent)
        deploy_soda_agent
        ;;
    collibra-dq)
        deploy_collibra_dq
        ;;
    *)
        print_error "Unknown stack: $STACK"
        exit 1
        ;;
esac

print_success "Deployment completed successfully!"
print_status "Stack: $STACK"
print_status "Environment: $ENVIRONMENT"
