#!/bin/bash

# Soda Infrastructure Bootstrap Script (stack-first)
# Creates/initializes the Terraform remote state backend:
# - S3 bucket for state
# - DynamoDB table for locking
#
# Notes:
# - deploy-stack.sh runs bootstrap automatically when needed.
# - This script is useful if you want to bootstrap only.

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
Usage: ./deploy-bootstrap.sh [environment] [region]

Environment variables (preferred):
  TF_VAR_environment
  TF_VAR_region

AWS credentials:
  AWS_PROFILE or AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY

Examples:
  export TF_VAR_environment=dev
  export TF_VAR_region=eu-west-1
  export AWS_PROFILE=dev-account
  ./deploy-bootstrap.sh

  # legacy positional convenience
  ./deploy-bootstrap.sh dev eu-west-1
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
# Keep naming aligned with env/root.hcl (org is currently 'datashift').
ORG="datashift"
BUCKET_NAME="${ACCOUNT_ID}-${ORG}-${ENVIRONMENT}-tfstate-${REGION}"
TABLE_NAME="${ACCOUNT_ID}-${ORG}-${ENVIRONMENT}-tf-locks"

print_status "Bootstrapping remote state backend"
print_status "Environment: $ENVIRONMENT"
print_status "Region: $REGION"
print_status "AWS Account: $ACCOUNT_ID"
print_status "S3 bucket: $BUCKET_NAME"
print_status "DynamoDB table: $TABLE_NAME"

cd "$BOOTSTRAP_DIR"

# If state exists, just apply.
if terragrunt output -json state_bucket >/dev/null 2>&1; then
  print_status "Bootstrap state detected; applying (should be no-op if already up to date)"
  terragrunt apply --auto-approve
  print_success "Bootstrap completed"
  exit 0
fi

# If resources exist but state is missing, import first.
if aws s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1 && \
   aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" >/dev/null 2>&1; then
  print_warning "Bootstrap resources exist but state is missing; importing..."
  terragrunt init -upgrade || true
  terragrunt import aws_s3_bucket.tfstate "$BUCKET_NAME"
  terragrunt import aws_dynamodb_table.locks "$TABLE_NAME"
  terragrunt apply --auto-approve
  print_success "Bootstrap imported and completed"
  exit 0
fi

print_status "Bootstrap resources not found; creating..."
terragrunt apply --auto-approve
print_success "Bootstrap created and completed"
