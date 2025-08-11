#!/bin/bash

# ECS Native Blue/Green Deployment Script
# Usage: ./deploy.sh <stack-name> <region> <account-id>

set -e

STACK_NAME=${1:-ecs-bluegreen-demo}
REGION=${2:-us-east-2}
ACCOUNT_ID=${3}

if [ -z "$ACCOUNT_ID" ]; then
    echo "Usage: $0 <stack-name> <region> <account-id>"
    echo "Example: $0 ecs-bluegreen-demo us-east-2 123456789012"
    exit 1
fi

echo "🚀 Starting ECS Native Blue/Green Deployment"
echo "Stack Name: $STACK_NAME"
echo "Region: $REGION"
echo "Account ID: $ACCOUNT_ID"

# Step 1: Create ECR repository
echo "📦 Creating ECR repository..."
aws ecr create-repository \
    --region $REGION \
    --repository-name ecs-bluegreen-demo \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 \
    2>/dev/null || echo "ECR repository already exists"

# Step 2: Build and push Docker image
echo "🐳 Building and pushing Docker image..."
cd application/
chmod +x build-and-push.sh
./build-and-push.sh v1.0 $ACCOUNT_ID $REGION
cd ..

# Step 3: Update parameters file
echo "⚙️ Updating CloudFormation parameters..."
cat > cloudformation/parameters.json << EOF
[
  {
    "ParameterKey": "VpcId",
    "ParameterValue": "$(aws ec2 describe-vpcs --region $REGION --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text)"
  },
  {
    "ParameterKey": "SubnetIds",
    "ParameterValue": "$(aws ec2 describe-subnets --region $REGION --filters "Name=default-for-az,Values=true" --query 'Subnets[0:2].SubnetId' --output text | tr '\t' ',')"
  },
  {
    "ParameterKey": "ImageUri",
    "ParameterValue": "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/ecs-bluegreen-demo:v1.0"
  }
]
EOF

# Step 4: Deploy CloudFormation stack
echo "☁️ Deploying CloudFormation stack..."
aws cloudformation create-stack \
    --region $REGION \
    --stack-name $STACK_NAME \
    --template-body file://cloudformation/infrastructure.yaml \
    --parameters file://cloudformation/parameters.json \
    --capabilities CAPABILITY_NAMED_IAM

echo "⏳ Waiting for stack creation to complete..."
aws cloudformation wait stack-create-complete \
    --region $REGION \
    --stack-name $STACK_NAME

# Step 5: Get stack outputs
echo "📋 Getting stack outputs..."
CLUSTER_NAME=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`ClusterName`].OutputValue' --output text)
BLUE_TG_ARN=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`BlueTargetGroupArn`].OutputValue' --output text)
GREEN_TG_ARN=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`GreenTargetGroupArn`].OutputValue' --output text)
PROD_RULE_ARN=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`ProductionListenerRuleArn`].OutputValue' --output text)
BG_ROLE_ARN=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`ECSBlueGreenRoleArn`].OutputValue' --output text)
LAMBDA_ARN=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionArn`].OutputValue' --output text)
TASK_DEF_ARN=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`TaskDefinitionArn`].OutputValue' --output text)
LOAD_BALANCER_DNS=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' --output text)

# Get security group ID
ECS_SG_ID=$(aws ec2 describe-security-groups --region $REGION --filters "Name=group-name,Values=$STACK_NAME-ECSSecurityGroup-*" --query 'SecurityGroups[0].GroupId' --output text)

# Get subnet IDs
SUBNET_IDS=$(aws ec2 describe-subnets --region $REGION --filters "Name=default-for-az,Values=true" --query 'Subnets[0:2].SubnetId' --output json | jq -r '.[]')
SUBNET_ARRAY=$(echo $SUBNET_IDS | tr ' ' '\n' | jq -R . | jq -s .)

# Step 6: Create service definition
echo "🔧 Creating service definition..."
cat > lifecycle-hooks/service-definition.json << EOF
{
  "serviceName": "$STACK_NAME-service",
  "cluster": "$CLUSTER_NAME",
  "taskDefinition": "$STACK_NAME-task:1",
  "desiredCount": 2,
  "launchType": "FARGATE",
  "networkConfiguration": {
    "awsvpcConfiguration": {
      "subnets": $(echo $SUBNET_ARRAY),
      "securityGroups": ["$ECS_SG_ID"],
      "assignPublicIp": "ENABLED"
    }
  },
  "deploymentController": {
    "type": "ECS"
  },
  "deploymentConfiguration": {
    "strategy": "BLUE_GREEN",
    "maximumPercent": 200,
    "minimumHealthyPercent": 100,
    "bakeTimeInMinutes": 2,
    "deploymentCircuitBreaker": {
      "enable": true,
      "rollback": true
    },
    "lifecycleHooks": [
      {
        "hookTargetArn": "$LAMBDA_ARN",
        "roleArn": "$BG_ROLE_ARN",
        "lifecycleStages": ["POST_TEST_TRAFFIC_SHIFT"]
      },
      {
        "hookTargetArn": "$LAMBDA_ARN",
        "roleArn": "$BG_ROLE_ARN",
        "lifecycleStages": ["PRODUCTION_TRAFFIC_SHIFT"]
      }
    ]
  },
  "loadBalancers": [
    {
      "targetGroupArn": "$BLUE_TG_ARN",
      "containerName": "demo-app",
      "containerPort": 80,
      "advancedConfiguration": {
        "alternateTargetGroupArn": "$GREEN_TG_ARN",
        "productionListenerRule": "$PROD_RULE_ARN",
        "roleArn": "$BG_ROLE_ARN"
      }
    }
  ]
}
EOF

# Step 7: Create ECS service with lifecycle hooks
echo "🎯 Creating ECS service with lifecycle hooks..."
aws ecs create-service \
    --region $REGION \
    --cli-input-json file://lifecycle-hooks/service-definition.json

echo "✅ Deployment completed successfully!"
echo ""
echo "🌐 Application URLs:"
echo "Production: http://$LOAD_BALANCER_DNS"
echo "Test: http://$LOAD_BALANCER_DNS:8080"
echo ""
echo "📊 Monitor deployment:"
echo "aws ecs describe-services --region $REGION --cluster $CLUSTER_NAME --services $STACK_NAME-service"
echo ""
echo "🔍 View Lambda logs:"
echo "aws logs tail /aws/lambda/$STACK_NAME-lifecycle-hook --region $REGION --follow"
