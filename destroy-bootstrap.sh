#!/bin/bash

# Soda Infrastructure Bootstrap Destruction Script
# This script destroys the S3 state bucket and DynamoDB lock table
# WARNING: This should only be run AFTER all infrastructure is destroyed
# WARNING: This will delete all Terraform state files!

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
    print_error "Usage: $0 <environment>"
    print_error "Environment: dev, prod"
    print_error "Example: $0 dev"
    exit 1
fi

ENVIRONMENT=$1

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|prod)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT"
    print_error "Valid environments: dev, prod"
    exit 1
fi

print_warning "=========================================="
print_warning "BOOTSTRAP DESTRUCTION WARNING"
print_warning "=========================================="
print_warning "This will destroy:"
print_warning "  - S3 bucket containing ALL Terraform state files"
print_warning "  - DynamoDB table for state locking"
print_warning ""
print_warning "This should ONLY be run after:"
print_warning "  1. All infrastructure has been destroyed"
print_warning "  2. You are sure you want to delete all state"
print_warning "  3. You have backups if needed"
print_warning "=========================================="

# Get AWS account ID and construct bucket/table names
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ORG="datashift"
REGION="eu-west-1"

BUCKET_NAME="${ACCOUNT_ID}-${ORG}-${ENVIRONMENT}-tfstate-${REGION}"
TABLE_NAME="${ACCOUNT_ID}-${ORG}-${ENVIRONMENT}-tf-locks"

print_status "Environment: $ENVIRONMENT"
print_status "S3 bucket: $BUCKET_NAME"
print_status "DynamoDB table: $TABLE_NAME"
print_status "Region: $REGION"

# Check if bucket exists
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    print_warning "S3 bucket does not exist: $BUCKET_NAME"
    print_warning "It may have already been destroyed."
else
    # List objects in bucket
    OBJECT_COUNT=$(aws s3 ls "s3://${BUCKET_NAME}" --recursive 2>/dev/null | wc -l | tr -d ' ')
    if [ "$OBJECT_COUNT" -gt 0 ]; then
        print_warning "Bucket contains $OBJECT_COUNT object(s)"
        print_warning "These will be deleted!"
    fi
fi

# Check if table exists
if ! aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" 2>/dev/null; then
    print_warning "DynamoDB table does not exist: $TABLE_NAME"
    print_warning "It may have already been destroyed."
fi

# Final confirmation
print_warning ""
read -p "Type 'DESTROY BOOTSTRAP' to confirm destruction: " -r

if [[ ! $REPLY =~ ^DESTROY\ BOOTSTRAP$ ]]; then
    print_status "Bootstrap destruction cancelled"
    exit 0
fi

# Set base directory
BASE_DIR="env/$ENVIRONMENT/eu-west-1"
cd "$BASE_DIR" || {
    print_error "Environment directory not found: $BASE_DIR"
    exit 1
}

print_status "Working directory: $(pwd)"

# Enable bootstrap for destruction
print_status "Enabling bootstrap for destruction..."
cd bootstrap || {
    print_error "Bootstrap directory not found"
    exit 1
}

# Check if skip is false, if not, enable it
if grep -q "skip = true" terragrunt.hcl; then
    print_status "Enabling bootstrap (setting skip = false)..."
    sed -i.bak 's/skip = true/skip = false/' terragrunt.hcl
    ENABLED_BY_SCRIPT=true
else
    print_status "Bootstrap already enabled (skip = false)"
    ENABLED_BY_SCRIPT=false
fi

# Destroy bootstrap resources
print_status "Destroying bootstrap resources..."
print_warning "This will delete the S3 bucket and DynamoDB table!"
terragrunt destroy --auto-approve

# Disable bootstrap again (if we enabled it)
if [ "$ENABLED_BY_SCRIPT" = true ]; then
    print_status "Disabling bootstrap (setting skip = true)..."
    sed -i.bak 's/skip = false/skip = true/' terragrunt.hcl
    # Clean up backup files
    rm -f terragrunt.hcl.bak
else
    print_status "Leaving skip = false (bootstrap was already enabled)"
fi

print_success "Bootstrap destruction completed successfully!"
print_success "Environment: $ENVIRONMENT"
print_success "S3 bucket destroyed: $BUCKET_NAME"
print_success "DynamoDB table destroyed: $TABLE_NAME"
print_warning "All Terraform state has been deleted!"
print_status "Current directory: $(pwd)"
