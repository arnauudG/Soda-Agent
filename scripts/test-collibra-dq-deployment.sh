#!/bin/bash

# Comprehensive test script for Collibra DQ deployment
# Tests all components: EC2, RDS, ALB, services, connectivity

set -e

ENVIRONMENT="${1:-dev}"
REGION="${2:-eu-west-1}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR/../env/$ENVIRONMENT/$REGION"

echo "=========================================="
echo "Collibra DQ Deployment Test"
echo "=========================================="
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo ""

# Test 1: Get Instance ID
print_info "Test 1: Retrieving EC2 Instance ID..."
cd "$BASE_DIR/addons/collibra-dq-standalone" || {
    print_error "Directory not found: $BASE_DIR/addons/collibra-dq-standalone"
    exit 1
}

INSTANCE_ID=$(terragrunt output -raw instance_id 2>/dev/null)
if [ -z "$INSTANCE_ID" ]; then
    print_error "Could not retrieve instance ID"
    exit 1
fi
print_success "Instance ID: $INSTANCE_ID"

# Test 2: Check EC2 Instance Status
print_info "Test 2: Checking EC2 Instance Status..."
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || echo "unknown")

if [ "$INSTANCE_STATE" = "running" ]; then
    print_success "Instance is running"
    INSTANCE_IP=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text 2>/dev/null || echo "")
    print_info "Private IP: $INSTANCE_IP"
else
    print_error "Instance state: $INSTANCE_STATE"
fi

# Test 3: Check Collibra DQ Service Status
print_info "Test 3: Checking Collibra DQ Service Status..."
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo systemctl status collibra-dq.service --no-pager -l 2>&1"]' \
    --query 'Command.CommandId' \
    --output text 2>/dev/null || echo "")

if [ -n "$COMMAND_ID" ]; then
    sleep 3
    SERVICE_OUTPUT=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null || echo "")
    
    if echo "$SERVICE_OUTPUT" | grep -q "active (running)"; then
        print_success "Collibra DQ service is running"
    elif echo "$SERVICE_OUTPUT" | grep -q "inactive"; then
        print_warning "Collibra DQ service is not running"
        print_info "Service output:"
        echo "$SERVICE_OUTPUT" | head -20 | sed 's/^/  /'
    else
        print_info "Service status check completed"
        echo "$SERVICE_OUTPUT" | head -10 | sed 's/^/  /'
    fi
else
    print_warning "Could not check service status via SSM"
fi

# Test 4: Check Health Endpoint
print_info "Test 4: Checking Health Endpoint (port 9101)..."
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["curl -s -o /dev/null -w \"%{http_code}\" http://localhost:9101/health || echo \"FAILED\""]' \
    --query 'Command.CommandId' \
    --output text 2>/dev/null || echo "")

if [ -n "$COMMAND_ID" ]; then
    sleep 3
    HEALTH_CODE=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null | tr -d '\n' || echo "")
    
    if [ "$HEALTH_CODE" = "200" ]; then
        print_success "Health endpoint is responding (HTTP 200)"
    else
        print_warning "Health endpoint returned: $HEALTH_CODE"
    fi
fi

# Test 5: Check Web Port (9000)
print_info "Test 5: Checking Web Port (9000)..."
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["curl -s -o /dev/null -w \"%{http_code}\" http://localhost:9000 || echo \"FAILED\""]' \
    --query 'Command.CommandId' \
    --output text 2>/dev/null || echo "")

if [ -n "$COMMAND_ID" ]; then
    sleep 3
    WEB_CODE=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null | tr -d '\n' || echo "")
    
    if [ "$WEB_CODE" = "200" ] || [ "$WEB_CODE" = "302" ] || [ "$WEB_CODE" = "301" ]; then
        print_success "Web port is responding (HTTP $WEB_CODE)"
    else
        print_warning "Web port returned: $WEB_CODE"
    fi
fi

# Test 6: Check ALB and Target Group
print_info "Test 6: Checking ALB and Target Group Health..."
cd "$BASE_DIR/addons/collibra-dq-standalone/alb" || {
    print_warning "ALB directory not found, skipping ALB tests"
} && {
    ALB_DNS=$(terragrunt output -raw load_balancer_dns_name 2>/dev/null || echo "")
    if [ -n "$ALB_DNS" ]; then
        print_success "ALB DNS: $ALB_DNS"
        
        TARGET_GROUP_ARN=$(terragrunt output -json target_group_arns 2>/dev/null | jq -r '.["collibra-dq"]' 2>/dev/null || echo "")
        if [ -n "$TARGET_GROUP_ARN" ] && [ "$TARGET_GROUP_ARN" != "null" ]; then
            print_info "Checking target group health..."
            HEALTH_STATE=$(aws elbv2 describe-target-health \
                --target-group-arn "$TARGET_GROUP_ARN" \
                --region "$REGION" \
                --query 'TargetHealthDescriptions[0].TargetHealth.State' \
                --output text 2>/dev/null || echo "unknown")
            
            if [ "$HEALTH_STATE" = "healthy" ]; then
                print_success "Target is HEALTHY"
                print_info "Collibra DQ is accessible at: http://$ALB_DNS"
            elif [ "$HEALTH_STATE" = "unhealthy" ]; then
                print_error "Target is UNHEALTHY"
                REASON=$(aws elbv2 describe-target-health \
                    --target-group-arn "$TARGET_GROUP_ARN" \
                    --region "$REGION" \
                    --query 'TargetHealthDescriptions[0].TargetHealth.Reason' \
                    --output text 2>/dev/null || echo "")
                print_info "Reason: $REASON"
            else
                print_warning "Target health: $HEALTH_STATE (may be initializing)"
            fi
        fi
        
        # Test ALB HTTP access
        print_info "Testing ALB HTTP access..."
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$ALB_DNS" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            print_success "ALB is responding (HTTP $HTTP_CODE)"
        else
            print_warning "ALB returned HTTP $HTTP_CODE"
        fi
    fi
}

# Test 7: Check RDS Connectivity
print_info "Test 7: Checking RDS Database Status..."
cd "$BASE_DIR/database/rds-collibra-dq/rds" || {
    print_warning "RDS directory not found, skipping RDS tests"
} && {
    RDS_ENDPOINT=$(terragrunt output -raw db_instance_endpoint 2>/dev/null || echo "")
    if [ -n "$RDS_ENDPOINT" ]; then
        print_success "RDS Endpoint: $RDS_ENDPOINT"
        
        RDS_STATUS=$(aws rds describe-db-instances \
            --db-instance-identifier "$(terragrunt output -raw db_instance_id 2>/dev/null || echo "")" \
            --region "$REGION" \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text 2>/dev/null || echo "unknown")
        
        if [ "$RDS_STATUS" = "available" ]; then
            print_success "RDS is available"
            
            # Test connectivity from EC2 instance
            print_info "Testing RDS connectivity from EC2 instance..."
            COMMAND_ID=$(aws ssm send-command \
                --instance-ids "$INSTANCE_ID" \
                --region "$REGION" \
                --document-name "AWS-RunShellScript" \
                --parameters "commands=[\"timeout 5 bash -c 'echo > /dev/tcp/${RDS_ENDPOINT%:*} 5432' && echo 'SUCCESS' || echo 'FAILED'\"]" \
                --query 'Command.CommandId' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$COMMAND_ID" ]; then
                sleep 3
                CONNECT_RESULT=$(aws ssm get-command-invocation \
                    --command-id "$COMMAND_ID" \
                    --instance-id "$INSTANCE_ID" \
                    --region "$REGION" \
                    --query 'StandardOutputContent' \
                    --output text 2>/dev/null | tr -d '\n' || echo "")
                
                if echo "$CONNECT_RESULT" | grep -q "SUCCESS"; then
                    print_success "RDS port 5432 is reachable from EC2 instance"
                else
                    print_warning "RDS port 5432 connectivity test failed"
                fi
            fi
        else
            print_warning "RDS status: $RDS_STATUS"
        fi
    fi
}

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo ""
echo "To view detailed logs:"
echo "  aws ssm start-session --target $INSTANCE_ID --region $REGION"
echo "  sudo tail -f /var/log/collibra-dq-install.log"
echo ""
echo "To check service logs:"
echo "  sudo journalctl -u collibra-dq.service -f"
echo ""
echo "To access Collibra DQ web interface:"
if [ -n "$ALB_DNS" ]; then
    echo "  http://$ALB_DNS"
else
    echo "  (ALB DNS not available)"
fi
echo ""
