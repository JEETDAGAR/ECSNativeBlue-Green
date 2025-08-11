# ECS Native Blue/Green Deployments with Lifecycle Hooks

[![AWS](https://img.shields.io/badge/AWS-ECS-orange)](https://aws.amazon.com/ecs/)
[![CloudFormation](https://img.shields.io/badge/Infrastructure-CloudFormation-blue)](https://aws.amazon.com/cloudformation/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

A complete implementation of AWS ECS Native Blue/Green deployments with automated lifecycle hooks for zero-downtime deployments.

## 🚀 Quick Start

```bash
# Clone repository
git clone https://github.com/JEETDAGAR/ECSNativeBlue-Green.git
cd ECSNativeBlue-Green

# Deploy everything (replace with your account ID)
./scripts/deploy.sh ecs-bluegreen-demo us-east-2 YOUR_ACCOUNT_ID

# Test Blue/Green deployment
./scripts/test-deployment.sh ecs-bluegreen-demo us-east-2 YOUR_ACCOUNT_ID v2.0 Green
```

## 📁 Repository Structure

```
ECSNativeBlue-Green/
├── cloudformation/          # CloudFormation templates
├── application/             # Sample Flask application
├── lifecycle-hooks/         # Lambda validation function
├── scripts/                 # Deployment automation
├── examples/               # Task definition examples
└── README.md               # This file
```

## 🎯 What You'll Learn

- **ECS Native Blue/Green Deployments** (no CodeDeploy required)
- **Deployment Lifecycle Hooks** with Lambda validation
- **Zero-downtime deployment strategies**
- **Automatic rollback capabilities**
- **Production-ready monitoring and troubleshooting**

## 🔧 Key Features

### ✅ Zero-Downtime Deployments
- Production traffic never interrupted
- Gradual traffic shifting between environments
- Automatic rollback on failure

### ✅ Automated Validation
- Health check validation via lifecycle hooks
- Custom business logic validation
- Configurable validation timeouts

### ✅ Production Safety
- Circuit breaker protection
- Deployment lifecycle hooks at critical stages
- Comprehensive monitoring and logging

### ✅ Easy Monitoring
- AWS Console integration
- CloudWatch logs and metrics
- Real-time deployment tracking

## 🖥️ AWS Console Monitoring

### ECS Service Monitoring
1. **Navigate to:** ECS → Clusters → `ecs-bluegreen-demo-cluster` → Services → `ecs-bluegreen-demo-service`
2. **Monitor:**
   - **Deployments tab:** View deployment timeline and status
   - **Configuration tab:** See lifecycle hooks configuration (2 configured)
   - **Events tab:** Monitor deployment events

### Load Balancer Monitoring
1. **Navigate to:** EC2 → Load Balancers → `ecs-bluegreen-demo-alb`
2. **Check:**
   - **Blue Target Group:** Current production targets
   - **Green Target Group:** New deployment targets
   - **Health checks:** Monitor target health status

### Lambda Function Monitoring
1. **Navigate to:** Lambda → Functions → `ecs-bluegreen-demo-lifecycle-hook`
2. **Monitor:**
   - **Monitor tab:** View invocation metrics
   - **CloudWatch logs:** See validation details

## 🧪 Testing Commands

```bash
# Get load balancer DNS
LOAD_BALANCER_DNS=$(aws cloudformation describe-stacks --region us-east-2 --stack-name ecs-bluegreen-demo --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' --output text)

# Test production URL
curl http://$LOAD_BALANCER_DNS

# Test during deployment
curl http://$LOAD_BALANCER_DNS        # Production (old version)
curl http://$LOAD_BALANCER_DNS:8080   # Test (new version)

# Monitor deployment
aws ecs describe-services --region us-east-2 --cluster ecs-bluegreen-demo-cluster --services ecs-bluegreen-demo-service --query 'services[0].deployments'

# View Lambda logs
aws logs tail /aws/lambda/ecs-bluegreen-demo-lifecycle-hook --region us-east-2 --follow
```

## 🧹 Cleanup

```bash
# Automated cleanup
./scripts/cleanup.sh ecs-bluegreen-demo us-east-2
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

**Happy Deploying! 🚀**
