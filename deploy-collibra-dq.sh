#!/bin/bash

# Collibra DQ Standalone Deployment Script
# This script deploys Collibra DQ infrastructure in the correct dependency order

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
    print_error "Usage: $0 <environment> [component]"
    print_error "Environment: dev, prod"
    print_error "Component: all|database|network|sg-collibra|package|instance|alb|target-group (optional)"
    print_error "Example: $0 dev                    # Deploy all components"
    print_error "Example: $0 dev package            # Deploy package upload only"
    print_error "Example: $0 dev instance           # Deploy EC2 instance only"
    exit 1
fi

ENVIRONMENT=$1
COMPONENT=${2:-all}

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|prod)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT"
    print_error "Valid environments: dev, prod"
    exit 1
fi

print_status "Deploying Collibra DQ to environment: $ENVIRONMENT"
if [ "$COMPONENT" != "all" ]; then
    print_status "Deploying component: $COMPONENT only"
fi

# Set base directory
BASE_DIR="env/$ENVIRONMENT/eu-west-1"
cd "$BASE_DIR" || {
    print_error "Environment directory not found: $BASE_DIR"
    exit 1
}

print_status "Working directory: $(pwd)"

# Function to deploy a module
deploy_module() {
    local module_path=$1
    local module_name=$2
    
    print_status "Deploying $module_name..."
    cd "$module_path" || {
        print_error "Module directory not found: $module_path"
        exit 1
    }
    
    # Check if terragrunt.hcl exists
    if [ ! -f "terragrunt.hcl" ]; then
        print_error "terragrunt.hcl not found in $module_path"
        exit 1
    fi
    
    # Initialize Terragrunt if needed (this resolves dependencies)
    print_status "Initializing $module_name..."
    terragrunt init -reconfigure >/dev/null 2>&1 || terragrunt init
    
    # Now apply
    terragrunt apply --auto-approve
    print_success "$module_name deployed successfully"
    
    cd - > /dev/null
}

# Function to check if package file exists
check_package_file() {
    local package_filename=${COLLIBRA_DQ_PACKAGE_FILENAME:-"dq-2025.11-SPARK356-JDK17-package-full.tar.gz"}
    # From env/dev/eu-west-1: go up 3 levels to project root, then packages/collibra-dq
    local package_dir="../../../packages/collibra-dq"
    
    # Check for exact filename first
    local package_path="$package_dir/$package_filename"
    if [ -f "$package_path" ]; then
        print_success "Package file found: $package_path"
        return 0
    fi
    
    # If exact match not found, try common variations (without .gz, with .tar, etc.)
    local base_name="${package_filename%.tar.gz}"
    base_name="${base_name%.tar}"
    base_name="${base_name%.tgz}"
    
    # Check for .tar, .tar.gz, .tgz variations
    for ext in ".tar" ".tar.gz" ".tgz" ".zip"; do
        local test_path="$package_dir/${base_name}${ext}"
        if [ -f "$test_path" ]; then
            print_success "Package file found: $test_path"
            print_status "Note: Using file '$test_path' instead of expected '$package_filename'"
            # Update the environment variable so terragrunt uses the correct filename
            export COLLIBRA_DQ_PACKAGE_FILENAME="$(basename "$test_path")"
            return 0
        fi
    done
    
    # If still not found, check for any .tar, .tar.gz, .tgz, .zip files in the directory
    local found_files=$(find "$package_dir" -maxdepth 1 -type f \( -name "*.tar" -o -name "*.tar.gz" -o -name "*.tgz" -o -name "*.zip" \) 2>/dev/null | head -1)
    if [ -n "$found_files" ]; then
        local found_file=$(basename "$found_files")
        print_success "Package file found: $found_files"
        print_status "Note: Using file '$found_file' instead of expected '$package_filename'"
        export COLLIBRA_DQ_PACKAGE_FILENAME="$found_file"
        return 0
    fi
    
    print_warning "Package file not found at: $package_path"
    print_warning "Also checked variations: ${base_name}.tar, ${base_name}.tar.gz, ${base_name}.tgz, ${base_name}.zip"
    print_warning "Package upload will be skipped. Ensure package is uploaded manually or set COLLIBRA_DQ_PACKAGE_URL environment variable."
    return 1
}

# Function to deploy a specific component
deploy_component() {
    local component=$1
    
    case $component in
        database)
            print_status "Component: Deploying RDS Database..."
            deploy_module "database/rds-collibra-dq/rds" "RDS Database"
            ;;
        sg-rds)
            print_status "Component: Deploying RDS Security Group..."
            deploy_module "database/rds-collibra-dq/sg-rds" "RDS Security Group"
            ;;
        network)
            print_status "Component: Deploying Network (VPC)..."
            deploy_module "network/vpc" "VPC"
            deploy_module "network/vpc-endpoints" "VPC Endpoints"
            ;;
        sg-collibra)
            print_status "Component: Deploying Collibra DQ Security Group..."
            deploy_module "addons/collibra-dq-standalone/sg-collibra-dq" "Collibra DQ Security Group"
            ;;
        package)
            print_status "Component: Uploading package to S3..."
            if check_package_file; then
                deploy_module "addons/collibra-dq-standalone/package-upload" "Package Upload"
            else
                print_warning "Skipping package upload (file not found)"
            fi
            ;;
        instance)
            print_status "Component: Deploying Collibra DQ EC2 Instance..."
            deploy_module "addons/collibra-dq-standalone" "Collibra DQ EC2 Instance"
            ;;
        sg-alb)
            print_status "Component: Deploying ALB Security Group..."
            deploy_module "addons/collibra-dq-standalone/alb/sg-alb" "ALB Security Group"
            ;;
        alb)
            print_status "Component: Deploying Application Load Balancer..."
            deploy_module "addons/collibra-dq-standalone/alb" "Application Load Balancer"
            ;;
        target-group)
            print_status "Component: Attaching instance to ALB target group..."
            deploy_module "addons/collibra-dq-standalone/alb/target-group-attachment" "Target Group Attachment"
            ;;
        *)
            print_error "Invalid component: $component"
            print_error "Valid components: database, sg-rds, network, sg-collibra, package, instance, sg-alb, alb, target-group"
            exit 1
            ;;
    esac
}

# Main deployment logic
if [ "$COMPONENT" = "all" ]; then
    print_status "Deploying all Collibra DQ components in order..."
    
    # Step 1: Network (if not already deployed)
    print_status "Step 1: Checking/Deploying Network..."
    # Try to get VPC output - if it fails, network needs to be deployed
    if cd network/vpc && terragrunt output vpc_id >/dev/null 2>&1; then
        print_status "Network already deployed, skipping..."
        cd - > /dev/null
    else
        cd - > /dev/null
        deploy_component "network"
    fi
    
    # Step 2: RDS Security Group
    print_status "Step 2: Deploying RDS Security Group..."
    deploy_component "sg-rds"
    
    # Step 3: RDS Database
    print_status "Step 3: Deploying RDS Database..."
    deploy_component "database"
    
    # Step 4: Collibra DQ Security Group
    print_status "Step 4: Deploying Collibra DQ Security Group..."
    deploy_component "sg-collibra"
    
    # Step 5: Package Upload (if package file exists)
    print_status "Step 5: Uploading package to S3..."
    if check_package_file; then
        deploy_component "package"
    else
        print_warning "Skipping package upload. Ensure COLLIBRA_DQ_PACKAGE_URL is set or package is uploaded manually."
    fi
    
    # Step 6: Collibra DQ EC2 Instance
    print_status "Step 6: Deploying Collibra DQ EC2 Instance..."
    deploy_component "instance"
    
    # Step 7: ALB Security Group
    print_status "Step 7: Deploying ALB Security Group..."
    deploy_component "sg-alb"
    
    # Step 8: Application Load Balancer
    print_status "Step 8: Deploying Application Load Balancer..."
    deploy_component "alb"
    
    # Step 9: Target Group Attachment
    print_status "Step 9: Attaching instance to ALB target group..."
    deploy_component "target-group"
    
    print_success "All Collibra DQ components deployed successfully!"
else
    deploy_component "$COMPONENT"
fi

print_status "Deployment completed successfully!"
print_status "Environment: $ENVIRONMENT"
print_status "Component: $COMPONENT"
print_status "Current directory: $(pwd)"
