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
<<<<<<< HEAD
Usage: $0 <stack> [--destroy-bootstrap] [--skip-addons]
=======
Usage: $0 <stack> [--destroy-bootstrap]
>>>>>>> origin/main

Stack Options:
  soda-agent    Destroy soda-agent stack (EKS)
  collibra-dq   Destroy collibra-dq stack (EC2+ALB+RDS)

Options:
  --destroy-bootstrap   Also destroy the bootstrap (S3 bucket and DynamoDB table)
                        WARNING: This will delete all Terraform state!
<<<<<<< HEAD
  --skip-addons         Destroy core infrastructure only (no Soda Agent Helm / no Collibra DQ app).
                        Safety: this will refuse to run if add-on modules still exist.
=======
>>>>>>> origin/main

Environment Variables (Required):
  TF_VAR_environment  - Environment (dev, prod)
  TF_VAR_region       - AWS region (eu-west-1, us-east-1, eu-central-1)

AWS Credentials (one of):
  AWS_PROFILE         - AWS profile name
  AWS_ACCESS_KEY_ID   - AWS access key ID
  AWS_SECRET_ACCESS_KEY - AWS secret access key

Examples:
<<<<<<< HEAD
  # Destroy soda-agent (keeps bootstrap)
  source scripts/set-env.sh
  echo "yes" | $0 soda-agent

  # Destroy collibra-dq and bootstrap
  $0 collibra-dq --destroy-bootstrap
  # (interactive) then type:
  #   - "yes" to confirm stack destruction
  #   - "DESTROY BOOTSTRAP" to confirm state backend deletion
=======
  # Destroy soda-agent (set env vars first)
  echo "yes" | $0 soda-agent

  # Destroy collibra-dq and bootstrap
  echo "yes" | $0 collibra-dq --destroy-bootstrap
>>>>>>> origin/main
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

<<<<<<< HEAD
=======
    if [ -z "$AWS_PROFILE" ] && [ -z "$AWS_ACCESS_KEY_ID" ]; then
        missing+=("AWS_PROFILE or AWS_ACCESS_KEY_ID")
    fi

>>>>>>> origin/main
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
<<<<<<< HEAD
SKIP_ADDONS="no"
=======
>>>>>>> origin/main

# Parse optional flags
shift
while [ $# -gt 0 ]; do
    case $1 in
        --destroy-bootstrap)
            DESTROY_BOOTSTRAP="yes"
            ;;
<<<<<<< HEAD
        --skip-addons)
            SKIP_ADDONS="yes"
            ;;
=======
>>>>>>> origin/main
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
    shift
done
<<<<<<< HEAD

export SKIP_ADDONS
=======
>>>>>>> origin/main

if [[ ! "$STACK" =~ ^(soda-agent|collibra-dq)$ ]]; then
    print_error "Invalid stack: $STACK"
    print_error "Valid stacks: soda-agent, collibra-dq"
    exit 1
fi

# Validate environment
validate_env
<<<<<<< HEAD

ENVIRONMENT="$TF_VAR_environment"
REGION="$TF_VAR_region"

# Get script directory (project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR/env/stack"

# Export environment variables for Terragrunt
export TF_VAR_environment="$ENVIRONMENT"
export TF_VAR_region="$REGION"
# Non-interactive: avoid "Are you sure? (y/n) ERROR EOF" when not a TTY (CI, pipes)
export TF_INPUT=0
export TG_INPUT=0

# Get AWS account information (required for bootstrap naming / safety checks)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [ -z "$AWS_ACCOUNT_ID" ] || [ "$AWS_ACCOUNT_ID" = "unknown" ]; then
    print_error "Unable to determine AWS account id (check AWS credentials / AWS CLI access)"
    exit 1
fi

=======

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

>>>>>>> origin/main
print_status "=================================================="
print_status "Destruction Configuration"
print_status "=================================================="
print_status "Stack:       $STACK"
print_status "Environment: $ENVIRONMENT"
print_status "Region:      $REGION"
print_status "AWS Account: $AWS_ACCOUNT_ID"
print_status "Base Dir:    $BASE_DIR"
print_status "=================================================="
<<<<<<< HEAD

# Validate environment variables (stack-aware). Destroy does not need add-on secrets.
if [ -f "$SCRIPT_DIR/scripts/validate-env.sh" ]; then
    print_status "Validating stack-specific environment variables..."
    if ! "$SCRIPT_DIR/scripts/validate-env.sh" "$STACK" "$ENVIRONMENT" "yes"; then
        print_error "Environment validation failed. Please fix the issues above and try again."
        exit 1
    fi
fi
=======
>>>>>>> origin/main

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
            check_module_exists "soda-agent/addons/soda-agent"
            ;;
        collibra-dq)
            check_module_exists "collibra-dq/addons/collibra-dq-standalone"
            ;;
    esac
}

# Check if RDS instance exists in AWS (by searching for collibra-dq instances)
check_rds_instance_exists() {
    local region="${TF_VAR_region:-eu-west-1}"
    
    # Try to get RDS identifier from terragrunt outputs if module exists
    local db_identifier=""
    local rds_module_path="$BASE_DIR/collibra-dq/database/rds-collibra-dq/rds"
    if [ -d "$rds_module_path" ]; then
        cd "$rds_module_path" || return 1
        # Terraform output name is db_instance_id (maps to AWS DBInstanceIdentifier)
        db_identifier=$(terragrunt output -raw db_instance_id 2>/dev/null || echo "")
        cd "$SCRIPT_DIR" || true
    fi
    
    # If we have an identifier from state, check that specific instance
    if [ -n "$db_identifier" ]; then
        if aws rds describe-db-instances --db-instance-identifier "$db_identifier" --region "$region" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null | grep -q "available\|deleting\|modifying"; then
            echo "$db_identifier"  # Return identifier for error message
            return 0  # RDS instance exists
        fi
    fi
    
    # Fallback: search for any RDS instance with "collibra-dq" / "dqMetastore" in the identifier
    local found_instance
    found_instance=$(aws rds describe-db-instances --region "$region" --query 'DBInstances[?contains(DBInstanceIdentifier, `collibra-dq`) || contains(DBInstanceIdentifier, `dqMetastore`) || contains(DBInstanceIdentifier, `dqmetastore`)].DBInstanceIdentifier' --output text 2>/dev/null | head -n1)
    
    if [ -n "$found_instance" ] && [ "$found_instance" != "None" ]; then
        echo "$found_instance"  # Return identifier for error message
        return 0  # RDS instance exists
    fi
    
    return 1  # RDS instance doesn't exist
}

# Check for lingering ENIs in a VPC that might prevent VPC deletion
check_vpc_lingering_resources() {
    local vpc_id=$1
    local region="${TF_VAR_region:-eu-west-1}"
    local issues=0
    
    # Check for ENIs that are not in "available" state (attached to deleted resources)
    local eni_count
    eni_count=$(aws ec2 describe-network-interfaces \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --region "$region" \
        --query 'length(NetworkInterfaces[?Status!=`available`])' \
        --output text 2>/dev/null || echo "0")
    
    if [ "$eni_count" != "0" ] && [ "$eni_count" != "None" ]; then
        print_warning "Found $eni_count network interface(s) in non-available state in VPC $vpc_id"
        print_warning "These may be lingering from deleted resources and could prevent VPC deletion"
        issues=$((issues + 1))
    fi
    
    # Check for VPC endpoints
    local vpc_endpoint_count
    vpc_endpoint_count=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --region "$region" \
        --query 'length(VpcEndpoints[?State!=`deleted`])' \
        --output text 2>/dev/null || echo "0")
    
    if [ "$vpc_endpoint_count" != "0" ] && [ "$vpc_endpoint_count" != "None" ]; then
        print_warning "Found $vpc_endpoint_count VPC endpoint(s) still in VPC $vpc_id"
        issues=$((issues + 1))
    fi
    
    # Check for security groups (excluding default)
    local sg_count
    sg_count=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=!default" \
        --region "$region" \
        --query 'length(SecurityGroups)' \
        --output text 2>/dev/null || echo "0")
    
    if [ "$sg_count" != "0" ] && [ "$sg_count" != "None" ]; then
        print_warning "Found $sg_count non-default security group(s) still in VPC $vpc_id"
        issues=$((issues + 1))
    fi
    
    if [ $issues -gt 0 ]; then
        print_warning "VPC $vpc_id may have lingering resources. VPC deletion may take longer or fail."
        print_warning "To diagnose, run:"
        print_warning "  aws ec2 describe-network-interfaces --filters \"Name=vpc-id,Values=$vpc_id\" --region $region"
        print_warning "  aws ec2 describe-vpc-endpoints --filters \"Name=vpc-id,Values=$vpc_id\" --region $region"
        return 1
    fi
    
    return 0
}

# Delete any unattached (available) ENIs in the VPC to avoid blocking VPC deletion
# Orphan ENIs left by VPC endpoints can be deleted explicitly; in-use ENIs must wait for AWS
delete_available_enis_in_vpc() {
    local vpc_id=$1
    local region="${TF_VAR_region:-eu-west-1}"
    local deleted=0
    
    local eni_ids
    eni_ids=$(aws ec2 describe-network-interfaces \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=status,Values=available" \
        --region "$region" \
        --query 'NetworkInterfaces[].NetworkInterfaceId' \
        --output text 2>/dev/null || true)
    
    for eni_id in $eni_ids; do
        [ -z "$eni_id" ] && continue
        if aws ec2 delete-network-interface --network-interface-id "$eni_id" --region "$region" 2>/dev/null; then
            deleted=$((deleted + 1))
            print_status "Deleted orphan ENI $eni_id"
        fi
    done
    
    [ $deleted -gt 0 ] && print_status "Deleted $deleted unattached ENI(s) in VPC $vpc_id"
    return 0
}

# Wait for ENIs to be released after VPC endpoints are destroyed
# Actively deletes any "available" (unattached) ENIs so only in-use ENIs block; we wait up to 10 min for those
wait_for_eni_cleanup() {
    local vpc_id=$1
    local region="${TF_VAR_region:-eu-west-1}"
    local max_wait=600   # 10 minutes max (AWS ENI release can be slow)
    local wait_interval=10  # Check every 10 seconds
    local elapsed=0
    
    print_status "Waiting for network interfaces to be released in VPC $vpc_id (max ${max_wait}s)..."
    
    while [ $elapsed -lt $max_wait ]; do
        # Delete any orphan (available) ENIs so they don't block VPC deletion
        delete_available_enis_in_vpc "$vpc_id" 2>/dev/null || true
        
        local eni_count
        eni_count=$(aws ec2 describe-network-interfaces \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --region "$region" \
            --query 'length(NetworkInterfaces)' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$eni_count" = "0" ] || [ "$eni_count" = "None" ]; then
            print_success "All network interfaces released"
            return 0
        fi
        
        print_status "Still waiting... ($eni_count ENI(s) remaining, ${elapsed}s elapsed)"
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    # Final attempt: delete any available ENIs that may have been released during the last wait
    delete_available_enis_in_vpc "$vpc_id" 2>/dev/null || true
    
    local eni_count
    eni_count=$(aws ec2 describe-network-interfaces \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --region "$region" \
        --query 'length(NetworkInterfaces)' \
        --output text 2>/dev/null || echo "0")
    if [ "$eni_count" = "0" ] || [ "$eni_count" = "None" ]; then
        print_success "All network interfaces released after final cleanup"
        return 0
    fi
    
    print_warning "Timeout (${max_wait}s) waiting for ENI cleanup. Proceeding with VPC destruction anyway (VPC destroy may retry or fail; check AWS Console for lingering ENIs)."
    return 1
}

# Unlock stale Terraform state lock
unlock_stale_lock() {
    local module_path=$1
    local lock_id=$2
    
    if [ -z "$lock_id" ]; then
        return 1
    fi
    
    print_warning "Attempting to unlock stale lock: $lock_id"
    cd "$BASE_DIR/$module_path" || return 1
    
    # Try to unlock the lock
    if terragrunt force-unlock -force "$lock_id" 2>/dev/null; then
        print_success "Successfully unlocked stale lock: $lock_id"
        cd "$SCRIPT_DIR" || true
        return 0
    else
        print_error "Failed to unlock lock: $lock_id"
        print_error "You may need to manually unlock it:"
        print_error "  cd $BASE_DIR/$module_path"
        print_error "  terragrunt force-unlock -force $lock_id"
        cd "$SCRIPT_DIR" || true
        return 1
    fi
}

# Extract lock ID from Terraform error output
extract_lock_id() {
    local error_output="$1"
    echo "$error_output" | grep -oP 'ID:\s+\K[a-f0-9-]+' | head -1 || echo ""
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

<<<<<<< HEAD
    # Special handling for VPC destruction - check for lingering resources first
    if [[ "$module_path" == *"/network/vpc" ]]; then
        local vpc_id
        vpc_id=$(terragrunt output -raw vpc_id 2>/dev/null || echo "")
        if [ -n "$vpc_id" ] && [ "$vpc_id" != "null" ]; then
            print_status "Checking for lingering resources in VPC $vpc_id..."
            check_vpc_lingering_resources "$vpc_id" || true
            print_warning "VPC destruction may take 5-10 minutes. Please be patient..."
        fi
    fi

    # Run destroy with timeout for VPC (15 minutes) and ALB (10 minutes)
    # ALB destruction can hang if listeners/target groups aren't properly cleaned up
    if [[ "$module_path" == *"/network/vpc" ]]; then
        timeout 900 terragrunt destroy --auto-approve || {
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                print_error "$module_name destruction timed out after 15 minutes"
                print_error "This usually means there are lingering resources preventing VPC deletion"
                print_error ""
                print_error "To diagnose, check for:"
                print_error "  1. Network interfaces: aws ec2 describe-network-interfaces --filters \"Name=vpc-id,Values=$vpc_id\" --region ${TF_VAR_region:-eu-west-1}"
                print_error "  2. VPC endpoints: aws ec2 describe-vpc-endpoints --filters \"Name=vpc-id,Values=$vpc_id\" --region ${TF_VAR_region:-eu-west-1}"
                print_error "  3. Security groups: aws ec2 describe-security-groups --filters \"Name=vpc-id,Values=$vpc_id\" --region ${TF_VAR_region:-eu-west-1}"
                print_error ""
                print_error "You may need to manually clean up lingering resources or wait for AWS to clean them up automatically"
            else
                print_error "$module_name destruction failed with exit code $exit_code"
            fi
            cd "$SCRIPT_DIR" || true
            exit $exit_code
        }
    elif [[ "$module_path" == *"/alb" ]] && [[ "$module_path" != *"/sg-alb" ]] && [[ "$module_path" != *"/target-group-attachment" ]]; then
        # ALB destruction timeout (10 minutes) - ALBs can hang if resources aren't properly detached
        print_status "Destroying $module_name (this may take 2-5 minutes, timeout: 10 minutes)..."
        timeout 600 terragrunt destroy --auto-approve || {
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                print_error "$module_name destruction timed out after 10 minutes"
                print_error "ALB destruction may be stuck. Common causes:"
                print_error "  1. Listeners still attached"
                print_error "  2. Target groups still referenced"
                print_error "  3. Network interfaces not released"
                print_error ""
                print_error "To diagnose:"
                print_error "  cd $BASE_DIR/$module_path"
                print_error "  terragrunt output -json | jq '.load_balancer_arn'"
                print_error "  aws elbv2 describe-load-balancers --load-balancer-arns <arn> --region ${TF_VAR_region:-eu-west-1}"
                print_error ""
                print_error "You may need to manually delete the ALB or wait and retry"
            else
                print_error "$module_name destruction failed with exit code $exit_code"
            fi
            cd "$SCRIPT_DIR" || true
            exit $exit_code
        }
    elif [[ "$module_path" == *"/rds" ]] && [[ "$module_path" != *"/sg-rds" ]]; then
        # RDS destruction timeout (20 minutes) - RDS deletion can take 5-15 minutes
        print_status "Destroying $module_name (this may take 5-15 minutes, timeout: 20 minutes)..."
        timeout 1200 terragrunt destroy --auto-approve || {
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                print_error "$module_name destruction timed out after 20 minutes"
                print_error "RDS deletion can take a long time. Check AWS Console for status."
                print_error ""
                print_error "To check RDS status:"
                print_error "  cd $BASE_DIR/$module_path"
                print_error "  terragrunt output -raw db_instance_id"
                print_error "  aws rds describe-db-instances --db-instance-identifier <id> --region ${TF_VAR_region:-eu-west-1}"
                print_error ""
                print_error "You may need to wait for RDS deletion to complete, then retry"
            else
                print_error "$module_name destruction failed with exit code $exit_code"
            fi
            cd "$SCRIPT_DIR" || true
            exit $exit_code
        }
    else
        # Capture output to check for lock errors
        local destroy_output
        destroy_output=$(terragrunt destroy --auto-approve 2>&1) || {
            local exit_code=$?
            local lock_id
            
            # Check if error is due to stale lock
            if echo "$destroy_output" | grep -q "Error acquiring the state lock"; then
                lock_id=$(extract_lock_id "$destroy_output")
                if [ -n "$lock_id" ]; then
                    print_warning "Detected stale state lock. Attempting to unlock..."
                    if unlock_stale_lock "$module_path" "$lock_id"; then
                        print_status "Retrying destruction after unlocking stale lock..."
                        # Retry destroy after unlocking
                        terragrunt destroy --auto-approve || {
                            local retry_exit_code=$?
                            print_error "$module_name destruction failed after lock unlock (exit code $retry_exit_code)"
                            cd "$SCRIPT_DIR" || true
                            exit $retry_exit_code
                        }
                    else
                        print_error "$module_name destruction failed due to stale lock that could not be unlocked"
                        print_error "Lock ID: $lock_id"
                        print_error "Please unlock manually: cd $BASE_DIR/$module_path && terragrunt force-unlock -force $lock_id"
                        cd "$SCRIPT_DIR" || true
                        exit $exit_code
                    fi
                else
                    print_error "$module_name destruction failed with state lock error (could not extract lock ID)"
                    print_error "Output: $destroy_output"
                    cd "$SCRIPT_DIR" || true
                    exit $exit_code
                fi
            else
                print_error "$module_name destruction failed with exit code $exit_code"
                echo "$destroy_output" >&2
                cd "$SCRIPT_DIR" || true
                exit $exit_code
            fi
        }
    fi
    
=======
    terragrunt destroy --auto-approve
>>>>>>> origin/main
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
<<<<<<< HEAD
        if check_module_exists "soda-agent/addons/soda-agent"; then
=======
        if check_module_exists "addons/soda-agent"; then
>>>>>>> origin/main
            print_error "Refusing to run with --skip-addons: Soda Agent add-on still exists."
            print_error "Destroy the add-on first or rerun without --skip-addons."
            exit 1
        fi
        print_status "Core-only mode: skipping Soda Agent add-on"
    else
<<<<<<< HEAD
        destroy_module "soda-agent/addons/soda-agent" "Soda Agent"
    fi
    destroy_module "soda-agent/eks/ops-ec2-eks-access" "EKS Access Configuration"
    destroy_module "soda-agent/ops/ec2-ops" "EC2 Ops Instance"
    destroy_module "soda-agent/eks" "EKS Cluster"
    destroy_module "soda-agent/ops/sg-ops" "Security Groups (Ops)"

    # VPC resources (independent stack - no conditional logic needed)
    destroy_module "soda-agent/network/vpc-endpoints" "VPC Endpoints"
    destroy_module "soda-agent/network/vpc" "VPC"
=======
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
>>>>>>> origin/main

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
<<<<<<< HEAD
        # Ensure no add-on/database modules exist before destroying core infra.
        if check_module_exists "collibra-dq/addons/collibra-dq-standalone" || \
           check_module_exists "collibra-dq/addons/collibra-dq-standalone/alb" || \
           check_module_exists "collibra-dq/addons/collibra-dq-standalone/alb/sg-alb" || \
           check_module_exists "collibra-dq/addons/collibra-dq-standalone/alb/target-group-attachment" || \
           check_module_exists "collibra-dq/addons/collibra-dq-standalone/package-upload" || \
           check_module_exists "collibra-dq/addons/collibra-dq-standalone/sg-collibra-dq" || \
           check_module_exists "collibra-dq/database/rds-collibra-dq/rds" || \
           check_module_exists "collibra-dq/database/rds-collibra-dq/sg-rds"; then
=======
        # Ensure no add-on/database modules exist before destroying shared infra.
        if check_module_exists "addons/collibra-dq-standalone" || \
           check_module_exists "addons/collibra-dq-standalone/alb" || \
           check_module_exists "addons/collibra-dq-standalone/alb/sg-alb" || \
           check_module_exists "addons/collibra-dq-standalone/alb/target-group-attachment" || \
           check_module_exists "addons/collibra-dq-standalone/package-upload" || \
           check_module_exists "addons/collibra-dq-standalone/sg-collibra-dq" || \
           check_module_exists "database/rds-collibra-dq/rds" || \
           check_module_exists "database/rds-collibra-dq/sg-rds"; then
>>>>>>> origin/main
            print_error "Refusing to run with --skip-addons: Collibra DQ add-on/database modules still exist."
            print_error "Destroy the add-on layers first or rerun without --skip-addons."
            exit 1
        fi

<<<<<<< HEAD
        # Only core infrastructure (network)
        # VPC endpoints create ENIs that must be released before VPC deletion
        destroy_module "collibra-dq/network/vpc-endpoints" "VPC Endpoints"
        
        # Get VPC ID before waiting for cleanup
        # Only wait if VPC module still exists and has outputs
        local vpc_id=""
        local vpc_module_path="$BASE_DIR/collibra-dq/network/vpc"
        if [ -d "$vpc_module_path" ]; then
            cd "$vpc_module_path" || true
            # Get VPC ID, suppressing warnings when outputs don't exist
            # Use raw output and filter out non-VPC-ID lines
            vpc_id=$(terragrunt output -raw vpc_id 2>&1 | grep -E "^vpc-[a-z0-9]+$" | head -1 || echo "")
            cd "$SCRIPT_DIR" || true
        fi
        
        # Wait for ENIs to be released after VPC endpoints are destroyed
        # Only if we have a valid VPC ID (module exists and has state)
        if [ -n "$vpc_id" ] && [[ "$vpc_id" =~ ^vpc- ]]; then
            wait_for_eni_cleanup "$vpc_id" || true
        else
            print_status "VPC module not found or already destroyed, skipping ENI cleanup wait"
        fi
        
        destroy_module "collibra-dq/network/vpc" "VPC"
=======
        # Only shared/core infrastructure (network + bootstrap).
        # Collibra DQ minimal stack does not manage EKS or ops instances.
        if ! check_other_stack_exists "soda-agent"; then
            destroy_module "network/vpc-endpoints" "VPC Endpoints"
            destroy_module "network/vpc" "VPC"
        else
            print_warning "VPC resources still in use by Soda Agent, skipping..."
        fi
>>>>>>> origin/main

        print_success "Collibra DQ Standalone core infrastructure destroyed successfully!"
        return 0
    fi

    # Reverse order of deployment
<<<<<<< HEAD
    # Complete dependency order:
    # 1. Application resources (depend on VPC, security groups, RDS):
    #    - Target Group Attachment (depends on ALB, EC2)
    #    - ALB (depends on VPC, ALB SG)
    #    - EC2 Instance (depends on VPC, Collibra DQ SG, RDS, package)
    #    - Package Upload (S3, no VPC dependency)
    #    - RDS Instance (depends on VPC, RDS SG)
    # 2. Security groups (must respect cross-references):
    #    - RDS SG references Collibra DQ SG -> RDS SG destroyed BEFORE Collibra DQ SG
    #    - Collibra DQ SG references ALB SG -> Collibra DQ SG destroyed BEFORE ALB SG
    #    - All SGs depend on VPC but are destroyed before VPC
    # 3. Network resources (VPC must be destroyed last):
    #    - VPC Endpoints (depends on VPC, creates ENIs that must be released)
    #    - Wait for ENI cleanup (VPC endpoints create ENIs that take time to release)
    #    - VPC (all resources depend on it, must be destroyed last)
    destroy_module "collibra-dq/addons/collibra-dq-standalone/alb/target-group-attachment" "Target Group Attachment"
    destroy_module "collibra-dq/addons/collibra-dq-standalone/alb" "Application Load Balancer"
    destroy_module "collibra-dq/addons/collibra-dq-standalone" "Collibra DQ EC2 Instance"
    destroy_module "collibra-dq/addons/collibra-dq-standalone/package-upload" "Package Upload (S3)"
    destroy_module "collibra-dq/database/rds-collibra-dq/rds" "RDS PostgreSQL Database"
    
    # Check if RDS instance still exists in AWS before destroying security group
    # RDS security group cannot be deleted while RDS instance exists (ENI attachment issue)
    local rds_identifier
    if rds_identifier=$(check_rds_instance_exists); then
        print_error "RDS instance still exists in AWS: $rds_identifier"
        print_error "The RDS security group cannot be deleted while the RDS instance exists."
        print_error ""
        print_error "Please delete the RDS instance manually first:"
        print_error "  aws rds delete-db-instance --db-instance-identifier $rds_identifier --skip-final-snapshot --region ${TF_VAR_region:-eu-west-1}"
        print_error "  OR with final snapshot:"
        print_error "  aws rds delete-db-instance --db-instance-identifier $rds_identifier --final-db-snapshot-identifier ${rds_identifier}-final-snapshot-$(date +%Y%m%d-%H%M%S) --region ${TF_VAR_region:-eu-west-1}"
        print_error ""
        print_error "Then re-run this script to continue with security group destruction."
        exit 1
    fi
    
    # Destroy RDS security group BEFORE Collibra DQ security group
    # because RDS SG has ingress rules referencing Collibra DQ SG
    destroy_module "collibra-dq/database/rds-collibra-dq/sg-rds" "RDS Security Group"
    
    # Destroy Collibra DQ security group BEFORE ALB security group
    # because Collibra DQ SG has ingress rules referencing ALB SG
    destroy_module "collibra-dq/addons/collibra-dq-standalone/sg-collibra-dq" "Collibra DQ Security Group"
    destroy_module "collibra-dq/addons/collibra-dq-standalone/alb/sg-alb" "ALB Security Group"

    # VPC resources - must be destroyed last
    # VPC endpoints create ENIs and security groups, so they must be destroyed before VPC
    # VPC itself must be destroyed last as all other resources depend on it
    destroy_module "collibra-dq/network/vpc-endpoints" "VPC Endpoints"
    
    # Get VPC ID before waiting for cleanup
    # Only wait if VPC module still exists and has outputs
    local vpc_id=""
    local vpc_module_path="$BASE_DIR/collibra-dq/network/vpc"
    if [ -d "$vpc_module_path" ]; then
        cd "$vpc_module_path" || true
        # Get VPC ID, suppressing warnings when outputs don't exist
        # Use raw output and filter out non-VPC-ID lines
        vpc_id=$(terragrunt output -raw vpc_id 2>&1 | grep -E "^vpc-[a-z0-9]+$" | head -1 || echo "")
        cd "$SCRIPT_DIR" || true
    fi
    
    # Wait for ENIs to be released after VPC endpoints are destroyed
    # VPC endpoints create ENIs that can take time to be fully released by AWS
    # Only if we have a valid VPC ID (module exists and has state)
    if [ -n "$vpc_id" ] && [[ "$vpc_id" =~ ^vpc- ]]; then
        wait_for_eni_cleanup "$vpc_id" || true
    else
        print_status "VPC module not found or already destroyed, skipping ENI cleanup wait"
    fi
    
    destroy_module "collibra-dq/network/vpc" "VPC"
=======
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
>>>>>>> origin/main

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

<<<<<<< HEAD
    # Check if VPCs still exist in either stack
    if check_module_exists "soda-agent/network/vpc" || check_module_exists "collibra-dq/network/vpc"; then
        print_error "Cannot destroy bootstrap: VPC still exists in one or both stacks!"
        print_error "Destroy all stacks first"
=======
    # Check if VPC still exists
    if check_module_exists "network/vpc"; then
        print_error "Cannot destroy bootstrap: VPC still exists!"
        print_error "Destroy VPC first"
>>>>>>> origin/main
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
