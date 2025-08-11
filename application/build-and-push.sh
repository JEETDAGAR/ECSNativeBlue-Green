#!/bin/bash

# ECS Blue-Green Demo - Build and Push Script
# Usage: ./build-and-push.sh <version> <account-id> <region>

set -e

VERSION=${1:-v1.0}
ACCOUNT_ID=${2}
REGION=${3:-us-east-1}
REPO_NAME="ecs-bluegreen-demo"

if [ -z "$ACCOUNT_ID" ]; then
    echo "Usage: $0 <version> <account-id> [region]"
    echo "Example: $0 v1.0 123456789012 us-east-1"
    exit 1
fi

ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}"

echo "Building Docker image for version: $VERSION"
docker build --platform linux/amd64 -t ${REPO_NAME}:${VERSION} .

echo "Tagging image for ECR..."
docker tag ${REPO_NAME}:${VERSION} ${ECR_URI}:${VERSION}
docker tag ${REPO_NAME}:${VERSION} ${ECR_URI}:latest

echo "Logging into ECR..."
aws ecr get-login-password --profile jeet --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URI}

echo "Pushing image to ECR..."
docker push ${ECR_URI}:${VERSION}
docker push ${ECR_URI}:latest

echo "✅ Successfully pushed ${ECR_URI}:${VERSION}"
echo "Image URI: ${ECR_URI}:${VERSION}"
