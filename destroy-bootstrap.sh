#!/bin/bash

# Soda Infrastructure Bootstrap Destruction Script (stack-first)
# Destroys the S3 state bucket and DynamoDB lock table.
# WARNING: This deletes Terraform state.

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
  cat << 'USAGE'
Usage: ./destroy-bootstrap.sh [environment] [region]

Environment variables (preferred):
  TF_VAR_environment
  TF_VAR_region

AWS credentials:
  AWS_PROFILE or AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY

Examples:
  export TF_VAR_environment=dev
  export TF_VAR_region=eu-west-1
  export AWS_PROFILE=dev-account
  ./destroy-bootstrap.sh

  # legacy positional convenience
  ./destroy-bootstrap.sh dev eu-west-1
USAGE
  exit 1
}

ENVIRONMENT=${1:-${TF_VAR_environment:-}}
REGION=${2:-${TF_VAR_region:-}}

if [ -z "$ENVIRONMENT" ] || [ -z "$REGION" ]; then
  usage
fi

export TF_VAR_environment="$ENVIRONMENT"
export TF_VAR_region="$REGION"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$SCRIPT_DIR/env/stack/bootstrap"

if [ ! -d "$BOOTSTRAP_DIR" ]; then
  print_error "Bootstrap directory not found: $BOOTSTRAP_DIR"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [ -z "$ACCOUNT_ID" ]; then
  print_error "Unable to determine AWS account id (check credentials)"
  exit 1
fi

ORG="datashift"
BUCKET_NAME="${ACCOUNT_ID}-${ORG}-${ENVIRONMENT}-tfstate-${REGION}"
TABLE_NAME="${ACCOUNT_ID}-${ORG}-${ENVIRONMENT}-tf-locks"

print_warning "=========================================="
print_warning "BOOTSTRAP DESTRUCTION WARNING"
print_warning "=========================================="
print_warning "This will destroy:"
print_warning "  - S3 bucket containing ALL Terraform state files"
print_warning "  - DynamoDB table for state locking"
print_warning ""
print_warning "Environment: $ENVIRONMENT"
print_warning "Region: $REGION"
print_warning "AWS Account: $ACCOUNT_ID"
print_warning "S3 bucket: $BUCKET_NAME"
print_warning "DynamoDB table: $TABLE_NAME"
print_warning "=========================================="

# Check if bucket exists
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  OBJECT_COUNT=$(aws s3 ls "s3://${BUCKET_NAME}" --recursive 2>/dev/null | wc -l | tr -d ' ')
  if [ "$OBJECT_COUNT" -gt 0 ]; then
    print_warning "Bucket contains $OBJECT_COUNT object(s) (they will be deleted)"
  fi
else
  print_warning "S3 bucket does not exist (it may have already been destroyed)"
fi

# Check if table exists
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" 2>/dev/null; then
  :
else
  print_warning "DynamoDB table does not exist (it may have already been destroyed)"
fi

print_warning ""
read -p "Type 'DESTROY BOOTSTRAP' to confirm destruction: " -r
if [[ ! $REPLY =~ ^DESTROY\ BOOTSTRAP$ ]]; then
  print_status "Bootstrap destruction cancelled"
  exit 0
fi

cd "$BOOTSTRAP_DIR"

# Import if needed (resources exist but state missing)
if ! terragrunt output -json state_bucket >/dev/null 2>&1; then
  if aws s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1 && \
     aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" >/dev/null 2>&1; then
    print_warning "Bootstrap resources exist but state is missing; importing..."
    terragrunt init -upgrade || true
    terragrunt import aws_s3_bucket.tfstate "$BUCKET_NAME"
    terragrunt import aws_dynamodb_table.locks "$TABLE_NAME"
  fi
fi

print_status "Destroying bootstrap resources..."
terragrunt destroy --auto-approve

print_success "Bootstrap destruction completed successfully!"
print_warning "All Terraform state for this environment/region has been deleted."
