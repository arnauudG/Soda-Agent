#!/bin/bash

# Quick script to check Collibra DQ deployment status

ENVIRONMENT=${1:-dev}

echo "=== Collibra DQ Deployment Status ==="
echo ""

cd "env/$ENVIRONMENT/eu-west-1/addons/collibra-dq-standalone" || exit 1

echo "1. EC2 Instance:"
INSTANCE_ID=$(terragrunt output -raw instance_id 2>/dev/null)
if [ -n "$INSTANCE_ID" ]; then
    echo "   Instance ID: $INSTANCE_ID"
    echo "   Status:"
    aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region eu-west-1 \
        --query 'Reservations[0].Instances[0].[State.Name,LaunchTime]' \
        --output text 2>/dev/null || echo "   (Unable to fetch status)"
else
    echo "   Not deployed yet"
fi

echo ""
echo "2. ALB:"
cd alb
ALB_DNS=$(terragrunt output -raw alb_dns_name 2>/dev/null)
if [ -n "$ALB_DNS" ]; then
    echo "   DNS Name: $ALB_DNS"
    echo "   URL: http://$ALB_DNS"
    
    TARGET_GROUP_ARN=$(terragrunt output -json target_group_arns 2>/dev/null | jq -r '.["collibra-dq"]' 2>/dev/null)
    if [ -n "$TARGET_GROUP_ARN" ] && [ "$TARGET_GROUP_ARN" != "null" ]; then
        echo ""
        echo "3. Target Health:"
        aws elbv2 describe-target-health \
            --target-group-arn "$TARGET_GROUP_ARN" \
            --region eu-west-1 \
            --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
            --output table 2>/dev/null || echo "   (Unable to fetch health)"
    fi
else
    echo "   Not deployed yet"
fi

echo ""
echo "4. Installation Logs (if instance exists):"
if [ -n "$INSTANCE_ID" ]; then
    echo "   To view logs, connect via SSM:"
    echo "   aws ssm start-session --target $INSTANCE_ID --region eu-west-1"
    echo ""
    echo "   Then run: sudo tail -f /var/log/collibra-dq-install.log"
fi
