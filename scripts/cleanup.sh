#!/bin/bash

# Cleanup Script for ECS Native Blue/Green Deployment
# Usage: ./cleanup.sh <stack-name> <region>

set -e

STACK_NAME=${1:-ecs-bluegreen-demo}
REGION=${2:-us-east-2}

# Get AWS account ID from current AWS credentials
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [ -z "$ACCOUNT_ID" ]; then
    echo "❌ Error: Unable to get AWS Account ID. Please check your AWS credentials."
    echo "Run: aws configure"
    echo "Or set: AWS_PROFILE=your-profile"
    exit 1
fi

echo "🧹 Cleaning up ECS Native Blue/Green Deployment"
echo "Stack Name: $STACK_NAME"
echo "Region: $REGION"
echo "Account ID: $ACCOUNT_ID"

# Step 1: Get cluster and service names
CLUSTER_NAME=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`ClusterName`].OutputValue' --output text 2>/dev/null || echo "")
SERVICE_NAME="$STACK_NAME-service"

if [ ! -z "$CLUSTER_NAME" ]; then
    echo "📋 Found cluster: $CLUSTER_NAME"
    
    # Step 2: Delete ECS service
    echo "🗑️ Deleting ECS service..."
    aws ecs delete-service \
        --region $REGION \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --force 2>/dev/null || echo "Service not found or already deleted"
    
    echo "⏳ Waiting for service deletion..."
    aws ecs wait services-inactive \
        --region $REGION \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME 2>/dev/null || echo "Service deletion completed"
fi

# Step 3: Delete CloudFormation stack
echo "☁️ Deleting CloudFormation stack..."
aws cloudformation delete-stack \
    --region $REGION \
    --stack-name $STACK_NAME

echo "⏳ Waiting for stack deletion..."
aws cloudformation wait stack-delete-complete \
    --region $REGION \
    --stack-name $STACK_NAME

# Step 4: Delete ECR repository (optional)
read -p "Do you want to delete the ECR repository? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🐳 Deleting ECR repository..."
    aws ecr delete-repository \
        --region $REGION \
        --repository-name ecs-bluegreen-demo \
        --force 2>/dev/null || echo "ECR repository not found or already deleted"
fi

# Step 5: Clean up local files
echo "📁 Cleaning up local files..."
rm -f lifecycle-hooks/service-definition.json
rm -f examples/test-task-definition.json
rm -f cloudformation/parameters.json

echo "✅ Cleanup completed successfully!"
echo ""
echo "🔍 Verify cleanup:"
echo "aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME"
echo "aws ecr describe-repositories --region $REGION --repository-names ecs-bluegreen-demo"
