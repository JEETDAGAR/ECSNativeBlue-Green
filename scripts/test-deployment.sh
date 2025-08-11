#!/bin/bash

# Test Blue/Green Deployment Script
# Usage: ./test-deployment.sh <stack-name> <region> <account-id> <new-version> <environment>

set -e

STACK_NAME=${1:-ecs-bluegreen-demo}
REGION=${2:-us-east-2}
ACCOUNT_ID=${3}
NEW_VERSION=${4:-v2.0}
ENVIRONMENT=${5:-Green}

if [ -z "$ACCOUNT_ID" ]; then
    echo "Usage: $0 <stack-name> <region> <account-id> [new-version] [environment]"
    echo "Example: $0 ecs-bluegreen-demo us-east-2 123456789012 v2.0 Green"
    exit 1
fi

echo "🧪 Testing Blue/Green Deployment"
echo "Stack Name: $STACK_NAME"
echo "Region: $REGION"
echo "New Version: $NEW_VERSION"
echo "Environment: $ENVIRONMENT"

# Get cluster name
CLUSTER_NAME=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`ClusterName`].OutputValue' --output text)
SERVICE_NAME="$STACK_NAME-service"

# Step 1: Build and push new version
echo "🐳 Building and pushing new version..."
cd application/
./build-and-push.sh $NEW_VERSION $ACCOUNT_ID $REGION
cd ..

# Step 2: Create new task definition
echo "📝 Creating new task definition..."
cat > examples/test-task-definition.json << EOF
{
  "family": "$STACK_NAME-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::$ACCOUNT_ID:role/$STACK_NAME-ECSExecutionRole",
  "containerDefinitions": [
    {
      "name": "demo-app",
      "image": "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/ecs-bluegreen-demo:$NEW_VERSION",
      "portMappings": [
        {
          "containerPort": 80,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "APP_VERSION",
          "value": "$NEW_VERSION"
        },
        {
          "name": "ENVIRONMENT",
          "value": "$ENVIRONMENT"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/$STACK_NAME",
          "awslogs-region": "$REGION",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
EOF

# Step 3: Register new task definition
echo "📋 Registering new task definition..."
NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
    --region $REGION \
    --cli-input-json file://examples/test-task-definition.json \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo "New task definition: $NEW_TASK_DEF_ARN"

# Step 4: Get current application state
LOAD_BALANCER_DNS=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' --output text)

echo "📊 Current application state:"
echo "Production URL: http://$LOAD_BALANCER_DNS"
echo "Test URL: http://$LOAD_BALANCER_DNS:8080"

# Test current state
echo "🔍 Testing current production state..."
curl -s "http://$LOAD_BALANCER_DNS" | grep -E "(Environment|v[0-9])" || echo "Could not retrieve current state"

# Step 5: Trigger Blue/Green deployment
echo "🚀 Triggering Blue/Green deployment..."
aws ecs update-service \
    --region $REGION \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --task-definition $NEW_TASK_DEF_ARN

echo "⏳ Deployment started. Monitor progress with:"
echo "aws ecs describe-services --region $REGION --cluster $CLUSTER_NAME --services $SERVICE_NAME --query 'services[0].deployments'"

# Step 6: Monitor deployment
echo "📈 Monitoring deployment progress..."
for i in {1..20}; do
    echo "Check $i/20..."
    
    DEPLOYMENT_STATUS=$(aws ecs describe-services \
        --region $REGION \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --query 'services[0].deployments[0].rolloutState' \
        --output text)
    
    echo "Deployment status: $DEPLOYMENT_STATUS"
    
    if [ "$DEPLOYMENT_STATUS" = "COMPLETED" ]; then
        echo "✅ Deployment completed successfully!"
        break
    elif [ "$DEPLOYMENT_STATUS" = "FAILED" ]; then
        echo "❌ Deployment failed!"
        break
    fi
    
    # Test URLs during deployment
    echo "Testing production URL (should show old version):"
    curl -s "http://$LOAD_BALANCER_DNS" | grep -E "(Environment|v[0-9])" || echo "No response"
    
    echo "Testing test URL (should show new version):"
    curl -s "http://$LOAD_BALANCER_DNS:8080" | grep -E "(Environment|v[0-9])" || echo "No response"
    
    sleep 30
done

# Step 7: Final state check
echo "🎯 Final application state:"
echo "Production URL:"
curl -s "http://$LOAD_BALANCER_DNS" | grep -E "(Environment|v[0-9])" || echo "Could not retrieve final state"

echo "Test URL:"
curl -s "http://$LOAD_BALANCER_DNS:8080" | grep -E "(Environment|v[0-9])" || echo "Could not retrieve final state"

echo ""
echo "🔍 View deployment events:"
echo "aws ecs describe-services --region $REGION --cluster $CLUSTER_NAME --services $SERVICE_NAME --query 'services[0].events[0:5]'"

echo ""
echo "📊 View Lambda logs:"
echo "aws logs tail /aws/lambda/$STACK_NAME-lifecycle-hook --region $REGION --follow"
