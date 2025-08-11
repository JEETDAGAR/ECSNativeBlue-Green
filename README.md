# ECS Native Blue/Green Deployments with Lifecycle Hooks

[![AWS](https://img.shields.io/badge/AWS-ECS-orange)](https://aws.amazon.com/ecs/)
[![CloudFormation](https://img.shields.io/badge/Infrastructure-CloudFormation-blue)](https://aws.amazon.com/cloudformation/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

Zero-downtime deployments with AWS ECS Native Blue/Green strategy and automated validation hooks.

## 🔧 Prerequisites

### AWS Credentials Setup
Before starting, configure your AWS credentials:

```bash
# Option 1: Configure default profile
aws configure

# Option 2: Use specific profile
export AWS_PROFILE=your-profile-name

# Option 3: Use environment variables
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
export AWS_DEFAULT_REGION=us-east-2
```

### Required Permissions
Your AWS user/role needs:
- ECS Full Access
- EC2 Full Access  
- IAM Role Creation
- Lambda Function Management
- CloudFormation Stack Management
- ECR Repository Management

## 🚀 Quick Start

```bash
# Clone and deploy
git clone https://github.com/JEETDAGAR/ECSNativeBlue-Green.git
cd ECSNativeBlue-Green
./scripts/deploy.sh ecs-bluegreen-demo us-east-2

# Test Blue/Green deployment
./scripts/test-deployment.sh ecs-bluegreen-demo us-east-2 v2.0 Green
```

## 📁 Repository Structure

```
ECSNativeBlue-Green/
├── cloudformation/          # Infrastructure templates
├── application/             # Sample Flask app
├── lifecycle-hooks/         # Lambda validation
├── scripts/                 # Deployment automation
└── examples/               # Task definitions
```

## 🎯 What This Does

- **Zero-downtime deployments** - Production never goes offline
- **Automatic validation** - Lambda hooks test new version before switching
- **Instant rollback** - Automatic rollback if validation fails
- **No CodeDeploy needed** - Uses ECS Native Blue/Green

## 🏗️ How It Works

### Simple Blue/Green Flow:
1. **Deploy new version** to alternate environment (Green)
2. **Test new version** automatically via lifecycle hooks
3. **Switch traffic** from old (Blue) to new (Green) environment
4. **Remove old version** after successful switch

### During Deployment:
- **Production traffic** continues on old version (zero downtime)
- **New version** gets tested in parallel
- **Traffic switches** only after validation passes

## 🖥️ Monitor in AWS Console

### ECS Service
- **ECS → Clusters → your-cluster → Services → your-service**
- Check **Deployments** tab for progress
- See **Configuration** tab for lifecycle hooks (2 configured)

### Load Balancer
- **EC2 → Load Balancers → your-alb**
- Monitor **Target Groups** health status
- Check **Listeners** for traffic routing

### Lambda Function
- **Lambda → Functions → your-lifecycle-hook**
- View **CloudWatch logs** for validation details

## 🧪 Test Your Deployment

```bash
# Get your load balancer URL
LOAD_BALANCER_DNS=$(aws cloudformation describe-stacks \
  --region us-east-2 --stack-name ecs-bluegreen-demo \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
  --output text)

# Test the application
curl http://$LOAD_BALANCER_DNS

# Monitor deployment
aws ecs describe-services \
  --region us-east-2 \
  --cluster ecs-bluegreen-demo-cluster \
  --services ecs-bluegreen-demo-service
```

## 🔧 Key Features

- ✅ **Zero downtime** - Production always available
- ✅ **Automated testing** - Lambda validates new version
- ✅ **Safe rollback** - Automatic rollback on failure
- ✅ **Easy monitoring** - AWS Console integration
- ✅ **Production ready** - Circuit breaker protection

## 🧹 Cleanup

```bash
./scripts/cleanup.sh ecs-bluegreen-demo us-east-2
```

## 📄 License

MIT License - see [LICENSE](LICENSE) file.

---

**Happy Deploying! 🚀**
