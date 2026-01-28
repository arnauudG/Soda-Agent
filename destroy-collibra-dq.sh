#!/bin/bash

# Collibra DQ Standalone Destruction Script
# This script destroys Collibra DQ infrastructure in reverse dependency order

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
    print_error "Component: all|target-group|alb|sg-alb|instance|package|sg-collibra|database|sg-rds|network (optional)"
    print_error "Example: $0 dev                    # Destroy all components"
    print_error "Example: $0 dev instance          # Destroy EC2 instance only"
    print_error ""
    print_warning "WARNING: This will destroy Collibra DQ infrastructure!"
    print_warning "Make sure you have backups if needed."
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

print_status "Destroying Collibra DQ from environment: $ENVIRONMENT"
if [ "$COMPONENT" != "all" ]; then
    print_status "Destroying component: $COMPONENT only"
else
    print_warning "WARNING: This will destroy ALL Collibra DQ components!"
    print_warning "Press Ctrl+C within 5 seconds to cancel..."
    sleep 5
fi

# Set base directory
BASE_DIR="env/$ENVIRONMENT/eu-west-1"
cd "$BASE_DIR" || {
    print_error "Environment directory not found: $BASE_DIR"
    exit 1
}

print_status "Working directory: $(pwd)"

# Function to destroy a module
destroy_module() {
    local module_path=$1
    local module_name=$2
    
    print_status "Destroying $module_name..."
    cd "$module_path" || {
        print_warning "Module directory not found: $module_path (may already be destroyed)"
        return 0
    }
    
    # Check if terragrunt.hcl exists
    if [ ! -f "terragrunt.hcl" ]; then
        print_warning "terragrunt.hcl not found in $module_path (may already be destroyed)"
        cd - > /dev/null
        return 0
    fi
    
    # Initialize Terragrunt if needed
    print_status "Initializing $module_name..."
    terragrunt init -reconfigure >/dev/null 2>&1 || terragrunt init
    
    # Destroy
    terragrunt destroy --auto-approve
    print_success "$module_name destroyed successfully"
    
    cd - > /dev/null
}

# Function to destroy a specific component
destroy_component() {
    local component=$1
    
    case $component in
        target-group)
            print_status "Component: Destroying Target Group Attachment..."
            destroy_module "addons/collibra-dq-standalone/alb/target-group-attachment" "Target Group Attachment"
            ;;
        alb)
            print_status "Component: Destroying Application Load Balancer..."
            destroy_module "addons/collibra-dq-standalone/alb" "Application Load Balancer"
            ;;
        sg-alb)
            print_status "Component: Destroying ALB Security Group..."
            destroy_module "addons/collibra-dq-standalone/alb/sg-alb" "ALB Security Group"
            ;;
        instance)
            print_status "Component: Destroying Collibra DQ EC2 Instance..."
            destroy_module "addons/collibra-dq-standalone" "Collibra DQ EC2 Instance"
            ;;
        package)
            print_status "Component: Destroying Package Upload (S3 bucket)..."
            print_warning "Note: This will delete the S3 bucket and all packages stored in it"
            destroy_module "addons/collibra-dq-standalone/package-upload" "Package Upload"
            ;;
        sg-collibra)
            print_status "Component: Destroying Collibra DQ Security Group..."
            destroy_module "addons/collibra-dq-standalone/sg-collibra-dq" "Collibra DQ Security Group"
            ;;
        database)
            print_status "Component: Destroying RDS Database..."
            print_warning "WARNING: This will delete the RDS database and all data!"
            destroy_module "database/rds-collibra-dq/rds" "RDS Database"
            ;;
        sg-rds)
            print_status "Component: Destroying RDS Security Group..."
            destroy_module "database/rds-collibra-dq/sg-rds" "RDS Security Group"
            ;;
        network)
            print_status "Component: Destroying Network..."
            print_warning "WARNING: This will destroy VPC and VPC endpoints!"
            print_warning "Only do this if you're sure no other resources depend on this network"
            destroy_module "network/vpc-endpoints" "VPC Endpoints"
            destroy_module "network/vpc" "VPC"
            ;;
        *)
            print_error "Invalid component: $component"
            print_error "Valid components: target-group, alb, sg-alb, instance, package, sg-collibra, database, sg-rds, network"
            exit 1
            ;;
    esac
}

# Main destruction logic
if [ "$COMPONENT" = "all" ]; then
    print_status "Destroying all Collibra DQ components in reverse order..."
    
    # Step 9: Target Group Attachment
    print_status "Step 9: Destroying Target Group Attachment..."
    destroy_component "target-group"
    
    # Step 8: Application Load Balancer
    print_status "Step 8: Destroying Application Load Balancer..."
    destroy_component "alb"
    
    # Step 7: ALB Security Group
    print_status "Step 7: Destroying ALB Security Group..."
    destroy_component "sg-alb"
    
    # Step 6: EC2 Instance
    print_status "Step 6: Destroying Collibra DQ EC2 Instance..."
    destroy_component "instance"
    
    # Step 5: Package Upload (S3 bucket)
    print_status "Step 5: Destroying Package Upload (S3 bucket)..."
    print_warning "Note: This will delete the S3 bucket and all packages"
    destroy_component "package"
    
    # Step 4: Collibra DQ Security Group
    print_status "Step 4: Destroying Collibra DQ Security Group..."
    destroy_component "sg-collibra"
    
    # Step 3: RDS Database
    print_status "Step 3: Destroying RDS Database..."
    print_warning "WARNING: This will delete the RDS database and all data!"
    destroy_component "database"
    
    # Step 2: RDS Security Group
    print_status "Step 2: Destroying RDS Security Group..."
    destroy_component "sg-rds"
    
    # Step 1: Network (optional - only if you want to destroy VPC)
    print_status "Step 1: Network..."
    print_warning "Skipping network destruction by default (VPC may be used by other resources)"
    print_warning "To destroy network, run: $0 $ENVIRONMENT network"
    
    print_success "All Collibra DQ components destroyed successfully!"
else
    destroy_component "$COMPONENT"
fi

print_status "Destruction completed!"
print_status "Environment: $ENVIRONMENT"
print_status "Component: $COMPONENT"
print_status "Current directory: $(pwd)"
