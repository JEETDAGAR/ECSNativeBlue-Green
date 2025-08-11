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

## 🏗️ Blue/Green Architecture

### **Traffic Flow During Deployment:**

```
Application Load Balancer
├── Port 80 (Production) → Blue Target Group → Old Version (v1.0)
└── Port 8080 (Test)     → Green Target Group → New Version (v2.0)
```

**Key Point:** During deployment, **both environments run simultaneously**:
- **Production traffic** continues on the old version (zero downtime)
- **Test traffic** routes to the new version for validation
- **After validation passes**, production traffic switches to the new version

## 🔧 Key Features

### ✅ Zero-Downtime Deployments
- Production traffic never interrupted during deployments
- New version tested in parallel on alternate port
- Gradual traffic shifting between Blue/Green environments
- Automatic rollback on failure

### ✅ Automated Validation
- Health check validation via lifecycle hooks
- Custom business logic validation through Lambda
- New version tested on port 8080 before production switch
- Configurable validation timeouts

### ✅ Production Safety
- Circuit breaker protection
- Deployment lifecycle hooks at critical stages
- Comprehensive monitoring and logging
- Safe rollback mechanism

### ✅ Easy Monitoring
- AWS Console integration
- CloudWatch logs and metrics
- Real-time deployment tracking
- Separate endpoints for production and test traffic

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
   - **Listeners:** Port 80 (production) and 8080 (test)
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

# Test production URL (always available)
curl http://$LOAD_BALANCER_DNS

# During deployment, test both environments:
curl http://$LOAD_BALANCER_DNS        # Production: Old version (no downtime!)
curl http://$LOAD_BALANCER_DNS:8080   # Test: New version (being validated)

# Monitor deployment progress
aws ecs describe-services --region us-east-2 --cluster ecs-bluegreen-demo-cluster --services ecs-bluegreen-demo-service --query 'services[0].deployments'

# View Lambda validation logs
aws logs tail /aws/lambda/ecs-bluegreen-demo-lifecycle-hook --region us-east-2 --follow
```

## 🔍 Why Port 8080 During Deployment?

### **The Magic of Blue/Green Deployments:**

1. **Before Deployment:**
   - Port 80: Blue environment (v1.0) ← All production traffic
   - Port 8080: Not used

2. **During Deployment:**
   - Port 80: Blue environment (v1.0) ← Production traffic continues (zero downtime!)
   - Port 8080: Green environment (v2.0) ← New version being tested

3. **After Successful Deployment:**
   - Port 80: Green environment (v2.0) ← Production traffic switched
   - Port 8080: Green environment (v2.0) ← Test port also updated

### **Real Example:**
```bash
# Start deployment of v2.0
./scripts/test-deployment.sh ecs-bluegreen-demo us-east-2 123456789 v2.0 Green

# During deployment, you can see both versions running:
curl http://my-alb.amazonaws.com      # Returns: "Blue Environment v1.0"
curl http://my-alb.amazonaws.com:8080 # Returns: "Green Environment v2.0"

# This proves zero-downtime: production never stops!
```

## 🔄 How Does ALB Switch Traffic?

### **The Key: ECS Service `advancedConfiguration`**

The traffic switching is **automatically handled by ECS** using this configuration:

```json
{
  "loadBalancers": [
    {
      "targetGroupArn": "BLUE_TARGET_GROUP_ARN",
      "containerName": "demo-app", 
      "containerPort": 80,
      "advancedConfiguration": {
        "alternateTargetGroupArn": "GREEN_TARGET_GROUP_ARN",
        "productionListenerRule": "PRODUCTION_LISTENER_RULE_ARN",
        "roleArn": "ECS_BLUE_GREEN_ROLE_ARN"
      }
    }
  ]
}
```

### **ECS Automatically:**
1. **Deploys new tasks** to alternate target group (Green)
2. **Tests via lifecycle hooks** on port 8080
3. **Modifies ALB listener rule** using weighted target groups
4. **Switches production traffic** from Blue (0% weight) to Green (100% weight)
5. **Drains old tasks** from Blue Target Group

### **How ALB Weighted Target Groups Work:**

```bash
# ECS modifies the listener rule to use weighted target groups:
aws elbv2 modify-rule \
  --rule-arn "PRODUCTION_LISTENER_RULE_ARN" \
  --actions Type=forward,ForwardConfig='{
    "TargetGroups": [
      {"TargetGroupArn": "BLUE_TARGET_GROUP_ARN", "Weight": 0},
      {"TargetGroupArn": "GREEN_TARGET_GROUP_ARN", "Weight": 100}
    ]
  }'
```

### **Important: AWS Console Display vs Reality**

**What AWS Console Shows:**
```
HTTP:80   → bluegreen-demo-blue (100%)    ← Default action (fallback)
HTTP:8080 → bluegreen-demo-green (100%)   ← Direct routing
```

**What Actually Happens (Priority Rule Overrides Default):**
```
HTTP:80 Priority Rule:
├── Blue Target Group: Weight 0%    ← No traffic
└── Green Target Group: Weight 100% ← All production traffic ✅

HTTP:8080 Default Rule:
└── Green Target Group: Weight 100% ← Test traffic ✅
```

### **Blue/Green Alternating Pattern:**

1. **First Deployment**: Blue → Green
   - Production traffic: Green (100%), Blue (0%)
   - Tasks running in: Green Target Group

2. **Second Deployment**: Green → Blue  
   - Production traffic: Blue (100%), Green (0%)
   - Tasks running in: Blue Target Group

3. **Third Deployment**: Blue → Green (cycle repeats)

**You don't manually configure ALB - ECS orchestrates everything using weighted target groups!**

## 🔍 Troubleshooting: Console Display vs Reality

### **Common Confusion: "My deployment looks wrong in the console!"**

**What you might see in AWS Console:**
```
Load Balancer Listeners:
├── HTTP:80   → bluegreen-demo-blue (100%)   ← Looks like Blue is active
└── HTTP:8080 → bluegreen-demo-green (100%)  ← Green has tasks
```

**But when you test the URLs:**
```bash
curl http://my-alb.amazonaws.com      # Returns: "Green Environment v2.0" ✅
curl http://my-alb.amazonaws.com:8080 # Returns: "Green Environment v2.0" ✅
```

### **Why This Happens:**

The AWS Console shows the **default listener action**, but ECS uses **weighted target group rules** that override the default:

```json
{
  "Priority": "1",
  "Actions": {
    "Type": "forward",
    "ForwardConfig": {
      "TargetGroups": [
        {"TargetGroupArn": "BLUE_TG", "Weight": 0},    ← No traffic
        {"TargetGroupArn": "GREEN_TG", "Weight": 100}  ← All traffic
      ]
    }
  }
}
```

### **How to Verify Actual Traffic Routing:**

```bash
# Check the weighted target group configuration
aws elbv2 describe-rules \
  --listener-arn "YOUR_LISTENER_ARN" \
  --query 'Rules[?Priority==`1`].Actions[0].ForwardConfig.TargetGroups'

# Test the actual traffic routing
curl http://your-alb-dns-name        # Should show the active environment
curl http://your-alb-dns-name:8080   # Should show the same environment after deployment
```

**Remember: The console display can be misleading - always test the actual URLs to verify traffic routing!**

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
