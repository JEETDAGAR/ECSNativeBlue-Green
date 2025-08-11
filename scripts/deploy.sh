#!/bin/bash

# ECS Native Blue/Green Deployment Script
# Usage: ./deploy.sh <stack-name> <region>

set -e

STACK_NAME=${1:-ecs-bluegreen-demo}
REGION=${2:-us-east-2}

# Cleanup function for error handling
cleanup_on_error() {
    echo "❌ Deployment failed. Cleaning up resources..."
    
    # Check if stack exists and delete it
    if aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME >/dev/null 2>&1; then
        echo "🧹 Deleting failed CloudFormation stack..."
        aws cloudformation delete-stack --region $REGION --stack-name $STACK_NAME
        echo "⏳ Waiting for stack deletion..."
        aws cloudformation wait stack-delete-complete --region $REGION --stack-name $STACK_NAME
    fi
    
    # Clean up local files
    rm -f lifecycle-hooks/service-definition.json
    rm -f cloudformation/parameters.json
    
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Get AWS account ID from current AWS credentials
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [ -z "$ACCOUNT_ID" ]; then
    echo "❌ Error: Unable to get AWS Account ID. Please check your AWS credentials."
    echo "Run: aws configure"
    echo "Or set: AWS_PROFILE=your-profile"
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

# Verify stack creation was successful
STACK_STATUS=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].StackStatus' --output text)
if [ "$STACK_STATUS" != "CREATE_COMPLETE" ]; then
    echo "❌ Error: CloudFormation stack creation failed with status: $STACK_STATUS"
    echo "🔍 Checking stack events for errors..."
    aws cloudformation describe-stack-events --region $REGION --stack-name $STACK_NAME --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].{Resource:LogicalResourceId,Reason:ResourceStatusReason}' --output table
    exit 1
fi

echo "✅ CloudFormation stack created successfully"

# Step 5: Get stack outputs
echo "📋 Getting stack outputs..."
CLUSTER_NAME=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`ClusterName`].OutputValue' --output text)
BLUE_TG_ARN=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`BlueTargetGroupArn`].OutputValue' --output text)
GREEN_TG_ARN=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`GreenTargetGroupArn`].OutputValue' --output text)
PROD_RULE_ARN=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`ProductionListenerRuleArn`].OutputValue' --output text)
TEST_RULE_ARN=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`TestListenerRuleArn`].OutputValue' --output text)
BG_ROLE_ARN=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`ECSBlueGreenRoleArn`].OutputValue' --output text)
LAMBDA_ARN=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionArn`].OutputValue' --output text)
TASK_DEF_ARN=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`TaskDefinitionArn`].OutputValue' --output text)
LOAD_BALANCER_DNS=$(aws cloudformation describe-stacks --region $REGION --stack-name $STACK_NAME --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' --output text)

# Validate that all required outputs were retrieved
if [ -z "$CLUSTER_NAME" ] || [ -z "$TASK_DEF_ARN" ] || [ -z "$BLUE_TG_ARN" ] || [ -z "$GREEN_TG_ARN" ]; then
    echo "❌ Error: Failed to retrieve required CloudFormation outputs"
    echo "Cluster: $CLUSTER_NAME"
    echo "Task Definition: $TASK_DEF_ARN"
    echo "Blue Target Group: $BLUE_TG_ARN"
    echo "Green Target Group: $GREEN_TG_ARN"
    exit 1
fi

echo "✅ Retrieved all CloudFormation outputs successfully"
echo "Cluster: $CLUSTER_NAME"
echo "Task Definition: $TASK_DEF_ARN"

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
  "taskDefinition": "$TASK_DEF_ARN",
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
        "testListenerRule": "$TEST_RULE_ARN",
        "roleArn": "$BG_ROLE_ARN"
      }
    }
  ]
}
EOF

# Step 7: Create ECS service with lifecycle hooks
echo "🎯 Creating ECS service with lifecycle hooks..."

# Validate task definition exists and is active
echo "🔍 Validating task definition..."
TASK_DEF_STATUS=$(aws ecs describe-task-definition --region $REGION --task-definition $TASK_DEF_ARN --query 'taskDefinition.status' --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$TASK_DEF_STATUS" != "ACTIVE" ]; then
    echo "❌ Error: Task definition is not active (Status: $TASK_DEF_STATUS)"
    echo "Task Definition ARN: $TASK_DEF_ARN"
    
    # Try to get the latest revision
    echo "🔄 Attempting to get latest task definition revision..."
    LATEST_TASK_DEF=$(aws ecs describe-task-definition --region $REGION --task-definition $STACK_NAME-task --query 'taskDefinition.taskDefinitionArn' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$LATEST_TASK_DEF" != "NOT_FOUND" ]; then
        echo "✅ Found latest task definition: $LATEST_TASK_DEF"
        TASK_DEF_ARN=$LATEST_TASK_DEF
        
        # Update the service definition with the correct task definition
        sed -i.bak "s|\"taskDefinition\": \".*\"|\"taskDefinition\": \"$TASK_DEF_ARN\"|" lifecycle-hooks/service-definition.json
    else
        echo "❌ No active task definition found. Please check CloudFormation stack creation."
        exit 1
    fi
fi

echo "✅ Task definition is active: $TASK_DEF_ARN"

aws ecs create-service \
    --region $REGION \
    --cli-input-json file://lifecycle-hooks/service-definition.json

# Disable error trap since deployment succeeded
trap - ERR

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
echo ""
echo "🧪 Test Blue/Green deployment:"
echo "./scripts/test-deployment.sh $STACK_NAME $REGION v2.0 Green"
