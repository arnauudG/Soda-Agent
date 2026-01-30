#!/bin/bash

# Stack destruction: soda-agent or collibra-dq
# Supports multi-account, multi-region deployment via environment variables
#
# Configuration Variables:
#   TF_VAR_environment - Environment (dev, prod)
#   TF_VAR_region      - AWS region (eu-west-1, us-east-1, etc.)
#   AWS_PROFILE        - AWS profile to use (alternative to access keys)
#   AWS_ACCESS_KEY_ID  - AWS access key (alternative to profile)
#   AWS_SECRET_ACCESS_KEY - AWS secret key

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
usage() {
    cat << EOF
Usage: $0 <stack> [--destroy-bootstrap]

Stack Options:
  soda-agent    Destroy soda-agent stack (EKS)
  collibra-dq   Destroy collibra-dq stack (EC2+ALB+RDS)

Options:
  --destroy-bootstrap   Also destroy the bootstrap (S3 bucket and DynamoDB table)
                        WARNING: This will delete all Terraform state!

Environment Variables (Required):
  TF_VAR_environment  - Environment (dev, prod)
  TF_VAR_region       - AWS region (eu-west-1, us-east-1, eu-central-1)

AWS Credentials (one of):
  AWS_PROFILE         - AWS profile name
  AWS_ACCESS_KEY_ID   - AWS access key ID
  AWS_SECRET_ACCESS_KEY - AWS secret access key

Examples:
  # Destroy soda-agent (set env vars first)
  echo "yes" | $0 soda-agent

  # Destroy collibra-dq and bootstrap
  echo "yes" | $0 collibra-dq --destroy-bootstrap
EOF
    exit 1
}

# Validate required environment variables
validate_env() {
    local missing=()

    if [ -z "$TF_VAR_environment" ]; then
        missing+=("TF_VAR_environment")
    fi

    if [ -z "$TF_VAR_region" ]; then
        missing+=("TF_VAR_region")
    fi

    if [ -z "$AWS_PROFILE" ] && [ -z "$AWS_ACCESS_KEY_ID" ]; then
        missing+=("AWS_PROFILE or AWS_ACCESS_KEY_ID")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required environment variables:"
        for var in "${missing[@]}"; do
            print_error "  - $var"
        done
        echo ""
        usage
    fi

    if [[ ! "$TF_VAR_environment" =~ ^(dev|prod)$ ]]; then
        print_error "Invalid TF_VAR_environment: $TF_VAR_environment"
        print_error "Valid values: dev, prod"
        exit 1
    fi

    if [[ ! "$TF_VAR_region" =~ ^(eu-west-1|us-east-1|eu-central-1)$ ]]; then
        print_error "Invalid TF_VAR_region: $TF_VAR_region"
        print_error "Valid values: eu-west-1, us-east-1, eu-central-1"
        exit 1
    fi
}

# Parse arguments
if [ $# -lt 1 ]; then
    usage
fi

STACK=$1
DESTROY_BOOTSTRAP=""

# Parse optional flags
shift
while [ $# -gt 0 ]; do
    case $1 in
        --destroy-bootstrap)
            DESTROY_BOOTSTRAP="yes"
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
    shift
done

if [[ ! "$STACK" =~ ^(soda-agent|collibra-dq)$ ]]; then
    print_error "Invalid stack: $STACK"
    print_error "Valid stacks: soda-agent, collibra-dq"
    exit 1
fi

# Validate environment
validate_env

ENVIRONMENT="$TF_VAR_environment"
REGION="$TF_VAR_region"

# Get script directory (project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR/env/stack"

# Export environment variables for Terragrunt
export TF_VAR_environment="$ENVIRONMENT"
export TF_VAR_region="$REGION"

# Get AWS account information
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")

print_status "=================================================="
print_status "Destruction Configuration"
print_status "=================================================="
print_status "Stack:       $STACK"
print_status "Environment: $ENVIRONMENT"
print_status "Region:      $REGION"
print_status "AWS Account: $AWS_ACCOUNT_ID"
print_status "Base Dir:    $BASE_DIR"
print_status "=================================================="

# Check if module exists
check_module_exists() {
    local module_path=$1
    local original_dir=$(pwd)
    cd "$BASE_DIR/$module_path" 2>/dev/null || return 1
    local output
    output=$(terragrunt output -json 2>/dev/null || true)
    local result=1
    if [ -n "$output" ] && [ "$output" != "{}" ]; then
        result=0
    fi
    cd "$original_dir" || cd "$SCRIPT_DIR" || true
    return $result
}

# Check bootstrap state (state exists in terraform)
check_bootstrap_state() {
    local bootstrap_dir="$BASE_DIR/bootstrap"
    local original_dir=$(pwd)

    if [ ! -d "$bootstrap_dir" ]; then
        return 1
    fi

    cd "$bootstrap_dir" || return 1
    if terragrunt output -json state_bucket >/dev/null 2>&1; then
        cd "$original_dir" || cd "$SCRIPT_DIR" || true
        return 0
    fi

    cd "$original_dir" || cd "$SCRIPT_DIR" || true
    return 1
}

# Check bootstrap resources directly in AWS
check_bootstrap_resources() {
    local org="datashift"
    local bucket_name="${AWS_ACCOUNT_ID}-${org}-${ENVIRONMENT}-tfstate-${REGION}"
    local table_name="${AWS_ACCOUNT_ID}-${org}-${ENVIRONMENT}-tf-locks"

    aws s3api head-bucket --bucket "$bucket_name" >/dev/null 2>&1 && \
    aws dynamodb describe-table --table-name "$table_name" --region "$REGION" >/dev/null 2>&1
}

# Import bootstrap resources into state if needed
import_bootstrap_state() {
    local bootstrap_dir="$BASE_DIR/bootstrap"
    local org="datashift"
    local bucket_name="${AWS_ACCOUNT_ID}-${org}-${ENVIRONMENT}-tfstate-${REGION}"
    local table_name="${AWS_ACCOUNT_ID}-${org}-${ENVIRONMENT}-tf-locks"
    local original_dir=$(pwd)

    cd "$bootstrap_dir" || {
        print_error "Bootstrap directory not found"
        exit 1
    }

    terragrunt init -upgrade || true
    terragrunt import aws_s3_bucket.tfstate "$bucket_name"
    terragrunt import aws_dynamodb_table.locks "$table_name"
    cd "$original_dir" || cd "$SCRIPT_DIR" || true
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
    cd "$SCRIPT_DIR" || true
}

# Destroy Soda Agent stack
destroy_soda_agent() {
    print_warning "This will destroy the Soda Agent stack!"
    print_warning "Environment: $ENVIRONMENT"
    print_warning "Region: $REGION"
    print_warning "AWS Account: $AWS_ACCOUNT_ID"
    read -p "Are you sure? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Destruction cancelled"
        exit 0
    fi

    print_status "Destroying Soda Agent stack..."

    # Reverse order of deployment
    if [ "$SKIP_ADDONS" = "yes" ]; then
        if check_module_exists "addons/soda-agent"; then
            print_error "Refusing to run with --skip-addons: Soda Agent add-on still exists."
            print_error "Destroy the add-on first or rerun without --skip-addons."
            exit 1
        fi
        print_status "Core-only mode: skipping Soda Agent add-on"
    else
        destroy_module "addons/soda-agent" "Soda Agent"
    fi
    destroy_module "eks/ops-ec2-eks-access" "EKS Access Configuration"
    destroy_module "ops/ec2-ops" "EC2 Ops Instance"
    destroy_module "eks" "EKS Cluster"
    destroy_module "ops/sg-ops" "Security Groups (Ops)"

    # VPC resources (only if Collibra DQ doesn't exist)
    if ! check_other_stack_exists "collibra-dq"; then
        destroy_module "network/vpc-endpoints" "VPC Endpoints"
        destroy_module "network/vpc" "VPC"
    else
        print_warning "VPC resources still in use by Collibra DQ, skipping..."
    fi

    print_success "Soda Agent stack destroyed successfully!"
}

# Destroy Collibra DQ stack
destroy_collibra_dq() {
    print_warning "This will destroy the Collibra DQ Standalone stack!"
    print_warning "Environment: $ENVIRONMENT"
    print_warning "Region: $REGION"
    print_warning "AWS Account: $AWS_ACCOUNT_ID"
    read -p "Are you sure? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Destruction cancelled"
        exit 0
    fi

    print_status "Destroying Collibra DQ Standalone stack..."

    if [ "$SKIP_ADDONS" = "yes" ]; then
        # Ensure no add-on/database modules exist before destroying shared infra.
        if check_module_exists "addons/collibra-dq-standalone" || \
           check_module_exists "addons/collibra-dq-standalone/alb" || \
           check_module_exists "addons/collibra-dq-standalone/alb/sg-alb" || \
           check_module_exists "addons/collibra-dq-standalone/alb/target-group-attachment" || \
           check_module_exists "addons/collibra-dq-standalone/package-upload" || \
           check_module_exists "addons/collibra-dq-standalone/sg-collibra-dq" || \
           check_module_exists "database/rds-collibra-dq/rds" || \
           check_module_exists "database/rds-collibra-dq/sg-rds"; then
            print_error "Refusing to run with --skip-addons: Collibra DQ add-on/database modules still exist."
            print_error "Destroy the add-on layers first or rerun without --skip-addons."
            exit 1
        fi

        # Only shared/core infrastructure (network + bootstrap).
        # Collibra DQ minimal stack does not manage EKS or ops instances.
        if ! check_other_stack_exists "soda-agent"; then
            destroy_module "network/vpc-endpoints" "VPC Endpoints"
            destroy_module "network/vpc" "VPC"
        else
            print_warning "VPC resources still in use by Soda Agent, skipping..."
        fi

        print_success "Collibra DQ Standalone core infrastructure destroyed successfully!"
        return 0
    fi

    # Reverse order of deployment
    destroy_module "addons/collibra-dq-standalone/alb/target-group-attachment" "Target Group Attachment"
    destroy_module "addons/collibra-dq-standalone/alb" "Application Load Balancer"
    destroy_module "addons/collibra-dq-standalone/alb/sg-alb" "ALB Security Group"
    destroy_module "addons/collibra-dq-standalone" "Collibra DQ EC2 Instance"
    destroy_module "addons/collibra-dq-standalone/package-upload" "Package Upload (S3)"
    destroy_module "addons/collibra-dq-standalone/sg-collibra-dq" "Collibra DQ Security Group"
    destroy_module "database/rds-collibra-dq/rds" "RDS PostgreSQL Database"
    destroy_module "database/rds-collibra-dq/sg-rds" "RDS Security Group"

    # VPC resources (only if Soda Agent doesn't exist)
    if ! check_other_stack_exists "soda-agent"; then
        destroy_module "network/vpc-endpoints" "VPC Endpoints"
        destroy_module "network/vpc" "VPC"
    else
        print_warning "VPC resources still in use by Soda Agent, skipping..."
    fi

    print_success "Collibra DQ Standalone stack destroyed successfully!"
}

# Handle bootstrap destruction
handle_bootstrap() {
    if [ "$DESTROY_BOOTSTRAP" != "yes" ]; then
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
        print_error "Destroy $other_stack stack first"
        exit 1
    fi

    # Check if VPC still exists
    if check_module_exists "network/vpc"; then
        print_error "Cannot destroy bootstrap: VPC still exists!"
        print_error "Destroy VPC first"
        exit 1
    fi

    if ! check_bootstrap_state; then
        if check_bootstrap_resources; then
            print_warning "Bootstrap resources exist but state is missing; importing..."
            import_bootstrap_state
        else
            print_warning "Bootstrap state not found and resources do not exist; skipping..."
            return 0
        fi
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
    cd "$SCRIPT_DIR" || true
}

# Main destruction logic
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

print_success "=================================================="
print_success "Destruction completed successfully!"
print_success "=================================================="
print_status "Stack:       $STACK"
print_status "Environment: $ENVIRONMENT"
print_status "Region:      $REGION"
print_status "AWS Account: $AWS_ACCOUNT_ID"
print_success "=================================================="
