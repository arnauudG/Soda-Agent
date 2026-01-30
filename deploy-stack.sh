#!/bin/bash

# Stack deployment: soda-agent (EKS) or collibra-dq (EC2+ALB+RDS)
# Supports multi-account, multi-region deployment via environment variables
#
# Configuration Variables:
#   TF_VAR_environment - Environment to deploy (dev, prod)
#   TF_VAR_region      - AWS region to deploy (eu-west-1, us-east-1, etc.)
#   AWS_PROFILE        - AWS profile to use (alternative to access keys)
#   AWS_ACCESS_KEY_ID  - AWS access key (alternative to profile)
#   AWS_SECRET_ACCESS_KEY - AWS secret key

set -e
set -o pipefail

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
Usage: $0 <stack>

Stack Options:
  soda-agent    soda-agent stack (EKS + Helm)
  collibra-dq   collibra-dq stack (EC2 + ALB + RDS)

Environment Variables (Required):
  TF_VAR_environment  - Environment to deploy (dev, prod)
  TF_VAR_region       - AWS region (eu-west-1, us-east-1, eu-central-1)

AWS Credentials (one of):
  AWS_PROFILE         - AWS profile name
  AWS_ACCESS_KEY_ID   - AWS access key ID
  AWS_SECRET_ACCESS_KEY - AWS secret access key

Examples:
  # Deploy soda-agent (set TF_VAR_*, AWS creds, add-on secrets in env first)
  export TF_VAR_environment=dev TF_VAR_region=eu-west-1
  $0 soda-agent

  # Deploy collibra-dq
  $0 collibra-dq
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

    # Check for AWS credentials
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

    # Validate environment value
    if [[ ! "$TF_VAR_environment" =~ ^(dev|prod)$ ]]; then
        print_error "Invalid TF_VAR_environment: $TF_VAR_environment"
        print_error "Valid values: dev, prod"
        exit 1
    fi

    # Validate region value
    if [[ ! "$TF_VAR_region" =~ ^(eu-west-1|us-east-1|eu-central-1)$ ]]; then
        print_error "Invalid TF_VAR_region: $TF_VAR_region"
        print_error "Valid values: eu-west-1, us-east-1, eu-central-1"
        exit 1
    fi
}

# Validate stack argument
if [ $# -lt 1 ]; then
    usage
fi

STACK=$1

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
print_status "Deployment Configuration"
print_status "=================================================="
print_status "Stack:       $STACK"
print_status "Environment: $ENVIRONMENT"
print_status "Region:      $REGION"
print_status "AWS Account: $AWS_ACCOUNT_ID"
print_status "Base Dir:    $BASE_DIR"
print_status "=================================================="

# Check if bootstrap exists
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

check_bootstrap_resources() {
    local org="datashift"
    local bucket_name="${AWS_ACCOUNT_ID}-${org}-${ENVIRONMENT}-tfstate-${REGION}"
    local table_name="${AWS_ACCOUNT_ID}-${org}-${ENVIRONMENT}-tf-locks"

    aws s3api head-bucket --bucket "$bucket_name" >/dev/null 2>&1 && \
    aws dynamodb describe-table --table-name "$table_name" --region "$REGION" >/dev/null 2>&1
}

# Deploy bootstrap if needed
deploy_bootstrap() {
    print_status "Checking bootstrap status..."
    if check_bootstrap_state; then
        print_success "Bootstrap already exists, skipping..."
        return 0
    fi

    if check_bootstrap_resources; then
        print_warning "Bootstrap resources exist but state is missing; importing..."
        local bootstrap_dir="$BASE_DIR/bootstrap"
        local org="datashift"
        local bucket_name="${AWS_ACCOUNT_ID}-${org}-${ENVIRONMENT}-tfstate-${REGION}"
        local table_name="${AWS_ACCOUNT_ID}-${org}-${ENVIRONMENT}-tf-locks"
        local original_dir=$(pwd)

        cd "$bootstrap_dir" || {
            print_error "Module directory not found: $bootstrap_dir"
            exit 1
        }

        terragrunt init -upgrade || true
        terragrunt import aws_s3_bucket.tfstate "$bucket_name"
        terragrunt import aws_dynamodb_table.locks "$table_name"
        terragrunt apply --auto-approve
        cd "$original_dir" || cd "$SCRIPT_DIR" || true
    else
        print_warning "Bootstrap not found. Creating S3 bucket and DynamoDB table..."
        deploy_module "bootstrap" "Bootstrap (S3 + DynamoDB)"
    fi

    # Verify bootstrap was created
    if ! check_bootstrap_state; then
        print_error "Bootstrap deployment failed - outputs not available"
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

    local log_file="/tmp/terragrunt-output-$$.log"

    if ! terragrunt apply --auto-approve 2>&1 | tee "$log_file"; then
        local apply_exit_code=${PIPESTATUS[0]}

        # Check if it's a provider initialization error
        if grep -q "Required plugins are not installed\|terraform init" "$log_file"; then
            print_warning "Provider initialization needed, running terraform init..."
            terragrunt init -upgrade || true
            print_status "Retrying deployment..."
            if ! terragrunt apply --auto-approve 2>&1 | tee "$log_file"; then
                print_error "Failed to deploy $module_name after initialization"
                rm -f "$log_file"
                cd "$SCRIPT_DIR" || true
                exit 1
            fi
        else
            print_error "Failed to deploy $module_name"
            print_error "Exit code: $apply_exit_code"
            rm -f "$log_file"
            cd "$SCRIPT_DIR" || true
            exit 1
        fi
    fi

    rm -f "$log_file"
    print_success "$module_name deployed successfully"
    cd "$SCRIPT_DIR" || true
}

# Check if module exists (has state)
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

    # Phase 3: ALB Security Group (must be created before Collibra DQ SG)
    deploy_module "addons/collibra-dq-standalone/alb/sg-alb" "ALB Security Group"

    # Phase 4: Collibra DQ Security Group (depends on ALB SG)
    deploy_module "addons/collibra-dq-standalone/sg-collibra-dq" "Collibra DQ Security Group"

    # Phase 5: RDS Security Group (depends on Collibra DQ SG)
    deploy_module "database/rds-collibra-dq/sg-rds" "RDS Security Group"

    # Phase 6: RDS Database
    deploy_module "database/rds-collibra-dq/rds" "RDS PostgreSQL Database"

    # Phase 7: Package Upload
    deploy_module "addons/collibra-dq-standalone/package-upload" "Package Upload (S3)"

    # Phase 8: EC2 Instance
    deploy_module "addons/collibra-dq-standalone" "Collibra DQ EC2 Instance"

    # Phase 9: Application Load Balancer
    deploy_module "addons/collibra-dq-standalone/alb" "Application Load Balancer"

    # Phase 10: Target Group Attachment
    deploy_module "addons/collibra-dq-standalone/alb/target-group-attachment" "Target Group Attachment"

    print_success "Collibra DQ Standalone stack deployed successfully!"
}

# Main deployment logic
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

print_success "=================================================="
print_success "Deployment completed successfully!"
print_success "=================================================="
print_status "Stack:       $STACK"
print_status "Environment: $ENVIRONMENT"
print_status "Region:      $REGION"
print_status "AWS Account: $AWS_ACCOUNT_ID"
print_success "=================================================="
