#!/bin/bash

# Soda Infrastructure Bootstrap Script
# This script safely bootstraps a new environment by creating the S3 bucket and DynamoDB table
# It should be run ONLY ONCE per environment

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
    print_error "Example: $0 prod"
    exit 1
fi

ENVIRONMENT=$1

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|prod)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT"
    print_error "Valid environments: dev, prod"
    exit 1
fi

print_status "Bootstrapping environment: $ENVIRONMENT"
print_warning "This script should be run ONLY ONCE per environment!"

# Set base directory
BASE_DIR="env/$ENVIRONMENT/eu-west-1"
cd "$BASE_DIR" || {
    print_error "Environment directory not found: $BASE_DIR"
    exit 1
}

print_status "Working directory: $(pwd)"

# Check if bootstrap is already enabled
if grep -q "skip = false" bootstrap/terragrunt.hcl; then
    print_warning "Bootstrap is already enabled for this environment!"
    print_warning "If you're sure you need to re-bootstrap, manually set 'skip = false' in bootstrap/terragrunt.hcl"
    exit 0
fi

# Check if S3 bucket already exists
BUCKET_NAME="datashift-$ENVIRONMENT-tfstate-$(aws sts get-caller-identity --query Account --output text)-eu-west-1"
print_status "Checking if S3 bucket already exists: $BUCKET_NAME"

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    print_warning "S3 bucket already exists: $BUCKET_NAME"
    print_warning "This environment may already be bootstrapped!"
    read -p "Do you want to continue anyway? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Bootstrap cancelled"
        exit 0
    fi
fi

# Check if DynamoDB table already exists
TABLE_NAME="datashift-$ENVIRONMENT-tf-locks"
print_status "Checking if DynamoDB table already exists: $TABLE_NAME"

if aws dynamodb describe-table --table-name "$TABLE_NAME" --region eu-west-1 2>/dev/null; then
    print_warning "DynamoDB table already exists: $TABLE_NAME"
    print_warning "This environment may already be bootstrapped!"
    read -p "Do you want to continue anyway? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Bootstrap cancelled"
        exit 0
    fi
fi

# Final confirmation
print_warning "You are about to bootstrap the $ENVIRONMENT environment!"
print_warning "This will create:"
print_warning "  - S3 bucket: $BUCKET_NAME"
print_warning "  - DynamoDB table: $TABLE_NAME"
print_warning "  - All necessary IAM policies and configurations"
read -p "Are you absolutely sure? Type 'BOOTSTRAP' to confirm: " -r

if [[ ! $REPLY =~ ^BOOTSTRAP$ ]]; then
    print_status "Bootstrap cancelled"
    exit 0
fi

# Enable bootstrap
print_status "Enabling bootstrap..."
cd bootstrap || {
    print_error "Bootstrap directory not found"
    exit 1
}

# Temporarily enable bootstrap
sed -i.bak 's/skip = true/skip = false/' terragrunt.hcl

# Run bootstrap
print_status "Running bootstrap..."
terragrunt apply --auto-approve

# Disable bootstrap again
print_status "Disabling bootstrap..."
sed -i.bak 's/skip = false/skip = true/' terragrunt.hcl

# Clean up backup files
rm -f terragrunt.hcl.bak

print_success "Bootstrap completed successfully!"
print_success "Environment: $ENVIRONMENT"
print_success "S3 bucket: $BUCKET_NAME"
print_success "DynamoDB table: $TABLE_NAME"
print_status "Bootstrap is now disabled. You can proceed with normal deployment."
print_status "Current directory: $(pwd)"
