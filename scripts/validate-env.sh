#!/bin/bash

# Environment Variable Validation Script
# Validates required environment variables before deployment
# Called by deploy-stack.sh before running Terragrunt

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Track validation results
ERRORS=0
WARNINGS=0

# Validate a required environment variable
validate_required() {
    local var_name=$1
    local description=$2
    local value="${!var_name}"

    if [ -z "$value" ]; then
        print_error "$var_name is not set - $description"
        ((ERRORS++))
        return 1
    fi
    print_success "$var_name is set"
    return 0
}

# Validate an optional environment variable (warn if not set)
validate_optional() {
    local var_name=$1
    local description=$2
    local default=$3
    local value="${!var_name}"

    if [ -z "$value" ]; then
        if [ -n "$default" ]; then
            print_status "$var_name not set, using default: $default"
        else
            print_warning "$var_name is not set - $description"
            ((WARNINGS++))
        fi
        return 0
    fi
    print_success "$var_name is set"
    return 0
}

# Validate CIDR format
validate_cidr() {
    local var_name=$1
    local value="${!var_name}"

    if [ -z "$value" ]; then
        return 0  # Empty is OK, will use default
    fi

    # Check if it's 0.0.0.0/0 (security warning)
    if [ "$value" = "0.0.0.0/0" ]; then
        print_warning "$var_name is set to 0.0.0.0/0 - This opens access from the internet!"
        ((WARNINGS++))
        return 0
    fi

    # Basic CIDR format validation
    if [[ ! "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        print_error "$var_name has invalid CIDR format: $value"
        ((ERRORS++))
        return 1
    fi

    print_success "$var_name is valid: $value"
    return 0
}

# Check AWS credentials
validate_aws() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        ((ERRORS++))
        return 1
    fi

    # Show what we have (so user sees what's missing)
    if [ -z "$AWS_ACCESS_KEY_ID" ]; then
        print_status "AWS_ACCESS_KEY_ID: not set"
    else
        print_status "AWS_ACCESS_KEY_ID: set (length ${#AWS_ACCESS_KEY_ID})"
    fi
    if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        print_status "AWS_SECRET_ACCESS_KEY: not set"
    else
        print_status "AWS_SECRET_ACCESS_KEY: set (length ${#AWS_SECRET_ACCESS_KEY})"
    fi
    if [ -z "$AWS_PROFILE" ]; then
        print_status "AWS_PROFILE: not set"
    else
        print_status "AWS_PROFILE: $AWS_PROFILE"
    fi

    # Use inherited env; only unset AWS_PROFILE so env keys are used (no secret on command line)
    local aws_err aws_rc
    aws_err=$(unset AWS_PROFILE; aws sts get-caller-identity 2>&1)
    aws_rc=$?
    if [ $aws_rc -ne 0 ]; then
        print_error "AWS credentials rejected (using env keys, not profile)"
        if [ -n "$aws_err" ]; then
            print_error "AWS CLI: $aws_err"
        else
            print_status "Run in your shell: aws sts get-caller-identity"
        fi
        if [ -z "$AWS_ACCESS_KEY_ID" ]; then
            print_error "Missing: export AWS_ACCESS_KEY_ID=your_key"
        fi
        if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
            print_error "Missing: export AWS_SECRET_ACCESS_KEY=your_secret"
        fi
        if [ -z "$AWS_ACCESS_KEY_ID" ] && [ -z "$AWS_SECRET_ACCESS_KEY" ] && [ -z "$AWS_PROFILE" ]; then
            print_error "Provide either (AWS_PROFILE) or (AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY) in this shell, then run the script again."
        fi
        ((ERRORS++))
        return 1
    fi

    local account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    print_success "AWS credentials valid (Account: $account_id)"
    return 0
}

# Main validation logic
main() {
    local stack=${1:-""}
    local environment=${2:-""}
    local skip_addons=${3:-"no"}

    echo ""
    echo "============================================"
    echo "Environment Variable Validation"
    echo "============================================"
    echo ""

    # Validate AWS credentials first
    print_status "Checking AWS credentials..."
    validate_aws
    echo ""

    # Common validations
    print_status "Checking common environment variables..."
    validate_optional "TF_VAR_region" "AWS region for deployment" "eu-west-1"
    echo ""

    # Stack-specific validations
    case "$stack" in
        soda-agent)
            print_status "Validating Soda Agent stack requirements..."
            echo ""

            if [ "$skip_addons" = "yes" ]; then
                print_warning "skip_addons=yes: Skipping Soda Agent add-on secret validation"
            else
                # Required for Soda Agent
                validate_required "SODA_API_KEY_ID" "Soda Cloud API Key ID for agent authentication"
                validate_required "SODA_API_KEY_SECRET" "Soda Cloud API Key Secret for agent authentication"

                # Optional Soda settings
                validate_optional "SODA_CLOUD_REGION" "Soda Cloud region (eu or us)" "eu"
                validate_optional "SODA_LOG_LEVEL" "Log level for Soda Agent" "INFO"
                validate_optional "SODA_LOG_FORMAT" "Log format (raw or json)" "raw"

                # Optional: Separate image registry credentials (defaults to API keys)
                validate_optional "SODA_IMAGE_APIKEY_ID" "Image registry API key ID (defaults to SODA_API_KEY_ID)"
                validate_optional "SODA_IMAGE_APIKEY_SECRET" "Image registry API key secret (defaults to SODA_API_KEY_SECRET)"
            fi
            ;;

        collibra-dq)
            print_status "Validating Collibra DQ stack requirements..."
            echo ""

            if [ "$skip_addons" = "yes" ]; then
                print_warning "skip_addons=yes: Skipping Collibra DQ add-on secret validation"
            else
                # Required for Collibra DQ
                validate_required "COLLIBRA_DQ_ADMIN_PASSWORD" "Admin password for Collibra DQ web interface"
                validate_required "COLLIBRA_DQ_LICENSE_KEY" "Collibra DQ license key"

                # Optional Collibra DQ settings
                validate_optional "COLLIBRA_DQ_VERSION" "Collibra DQ version to install" "2024.11.0"
                validate_optional "COLLIBRA_DQ_ALLOWED_CIDR" "CIDR block for security group access" "VPC CIDR"

                # Validate CIDR if set
                validate_cidr "COLLIBRA_DQ_ALLOWED_CIDR"

                # RDS settings
                validate_optional "COLLIBRA_DQ_RDS_USERNAME" "RDS database username" "collibradq"
                validate_optional "COLLIBRA_DQ_RDS_PASSWORD" "RDS database password" "(auto-generated)"

                # Security warning for production
                if [ "$environment" = "prod" ]; then
                    echo ""
                    print_status "Production environment checks..."

                    # Check for HTTPS certificate
                    if [ -z "$COLLIBRA_DQ_CERTIFICATE_ARN" ]; then
                        print_warning "COLLIBRA_DQ_CERTIFICATE_ARN not set - ALB will use HTTP only (not recommended for production)"
                        ((WARNINGS++))
                    else
                        print_success "HTTPS certificate configured"
                    fi
                fi
            fi
            ;;

        *)
            # Validate all possible variables if no stack specified
            print_status "Validating all environment variables..."
            echo ""

            print_status "Soda Agent variables:"
            validate_optional "SODA_API_KEY_ID" "Soda Cloud API Key ID"
            validate_optional "SODA_API_KEY_SECRET" "Soda Cloud API Key Secret"
            validate_optional "SODA_CLOUD_REGION" "Soda Cloud region" "eu"
            echo ""

            print_status "Collibra DQ variables:"
            validate_optional "COLLIBRA_DQ_ADMIN_PASSWORD" "Admin password for Collibra DQ"
            validate_optional "COLLIBRA_DQ_LICENSE_KEY" "Collibra DQ license key"
            validate_optional "COLLIBRA_DQ_VERSION" "Collibra DQ version" "2024.11.0"
            validate_cidr "COLLIBRA_DQ_ALLOWED_CIDR"
            ;;
    esac

    # Summary
    echo ""
    echo "============================================"
    echo "Validation Summary"
    echo "============================================"

    if [ $ERRORS -gt 0 ]; then
        print_error "Validation failed with $ERRORS error(s) and $WARNINGS warning(s)"
        echo ""
        echo "Please set the required environment variables and try again."
        echo "See .env.example for a complete list of environment variables."
        exit 1
    fi

    if [ $WARNINGS -gt 0 ]; then
        print_warning "Validation passed with $WARNINGS warning(s)"
    else
        print_success "All validations passed!"
    fi

    echo ""
    return 0
}

# Run main with provided arguments
main "$@"
