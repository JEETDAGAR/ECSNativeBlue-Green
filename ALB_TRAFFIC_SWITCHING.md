# 🔄 ALB Traffic Switching in ECS Native Blue/Green Deployments

## 🎯 **The Key Question: How does ALB redirect traffic to new target group?**

The traffic switching is **automatically handled by ECS** using the `advancedConfiguration` in the service definition. Here's exactly how it works:

## 🔧 **Configuration Location: ECS Service Definition**

```json
{
  "serviceName": "my-service",
  "cluster": "my-cluster",
  "loadBalancers": [
    {
      "targetGroupArn": "arn:aws:elasticloadbalancing:us-east-2:123456789:targetgroup/blue-tg/abc123",
      "containerName": "demo-app",
      "containerPort": 80,
      "advancedConfiguration": {
        "alternateTargetGroupArn": "arn:aws:elasticloadbalancing:us-east-2:123456789:targetgroup/green-tg/def456",
        "productionListenerRule": "arn:aws:elasticloadbalancing:us-east-2:123456789:listener-rule/app/my-alb/xyz789",
        "roleArn": "arn:aws:iam::123456789:role/ECSBlueGreenRole"
      }
    }
  ]
}
```

## 📊 **Step-by-Step Traffic Switch Process:**

### **Phase 1: Initial State**
```
ALB Listener (Port 80)
└── Listener Rule (Priority 1)
    └── Action: Forward to Blue Target Group
        ├── Task 1 (Blue v1.0) ✅ Healthy
        └── Task 2 (Blue v1.0) ✅ Healthy

ALB Listener (Port 8080)  
└── Listener Rule (Priority 1)
    └── Action: Forward to Green Target Group
        └── (Empty - no tasks)
```

### **Phase 2: Deployment Starts**
```
ECS Service receives update-service command with new task definition

ECS Service thinks: 
"I need to deploy new tasks to the GREEN target group 
and eventually switch production traffic from BLUE to GREEN"
```

### **Phase 3: New Tasks Deployed**
```
ALB Listener (Port 80) - PRODUCTION TRAFFIC
└── Listener Rule (Priority 1)
    └── Action: Forward to Blue Target Group
        ├── Task 1 (Blue v1.0) ✅ Healthy  ← Production traffic
        └── Task 2 (Blue v1.0) ✅ Healthy  ← Production traffic

ALB Listener (Port 8080) - TEST TRAFFIC
└── Listener Rule (Priority 1)
    └── Action: Forward to Green Target Group
        ├── Task 3 (Green v2.0) ✅ Healthy  ← Test traffic
        └── Task 4 (Green v2.0) ✅ Healthy  ← Test traffic
```

### **Phase 4: Lifecycle Hooks Execute**
```
Lambda function tests Green environment via port 8080:
- Health checks: ✅ PASS
- Business logic validation: ✅ PASS
- Returns: {"hookStatus": "SUCCEEDED"}
```

### **Phase 5: ECS Modifies ALB (The Magic!)**
```
ECS Service makes AWS API call:

aws elbv2 modify-rule \
  --rule-arn "arn:aws:elasticloadbalancing:us-east-2:123456789:listener-rule/app/my-alb/xyz789" \
  --actions Type=forward,TargetGroupArn="arn:aws:elasticloadbalancing:us-east-2:123456789:targetgroup/green-tg/def456"
```

### **Phase 6: Traffic Switched**
```
ALB Listener (Port 80) - PRODUCTION TRAFFIC
└── Listener Rule (Priority 1)
    └── Action: Forward to Green Target Group  ← SWITCHED!
        ├── Task 3 (Green v2.0) ✅ Healthy  ← Production traffic
        └── Task 4 (Green v2.0) ✅ Healthy  ← Production traffic

ALB Listener (Port 8080) - TEST TRAFFIC
└── Listener Rule (Priority 1)
    └── Action: Forward to Green Target Group
        ├── Task 3 (Green v2.0) ✅ Healthy
        └── Task 4 (Green v2.0) ✅ Healthy
```

### **Phase 7: Cleanup**
```
ECS Service drains and stops old Blue tasks:
- Task 1 (Blue v1.0) → Draining → Stopped
- Task 2 (Blue v1.0) → Draining → Stopped
```

## 🔑 **Key Points:**

### **1. ECS Service Orchestrates Everything**
- You don't manually modify ALB rules
- ECS service has the intelligence to switch traffic
- All configured in the service definition

### **2. IAM Role Permissions**
The `ECSBlueGreenRole` needs these permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:ModifyRule",
        "elasticloadbalancing:DescribeRules",
        "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:DescribeListeners"
      ],
      "Resource": "*"
    }
  ]
}
```

### **3. Automatic vs Manual**
- **ECS Native Blue/Green**: ECS automatically switches ALB rules
- **CodeDeploy Blue/Green**: CodeDeploy switches ALB rules
- **Manual Blue/Green**: You manually switch ALB rules

## 🧪 **Real-World Example:**

```bash
# Before deployment
curl http://my-alb.amazonaws.com
# Returns: "Blue Environment v1.0"

# Start deployment
aws ecs update-service --service my-service --task-definition my-task:2

# During deployment (both environments running)
curl http://my-alb.amazonaws.com      # Blue v1.0 (production)
curl http://my-alb.amazonaws.com:8080 # Green v2.0 (test)

# After successful deployment (ECS switched the rule)
curl http://my-alb.amazonaws.com
# Returns: "Green Environment v2.0"
```

## 🔍 **How to Verify the Switch:**

```bash
# Check current listener rule target
aws elbv2 describe-rules \
  --listener-arn "arn:aws:elasticloadbalancing:us-east-2:123456789:listener/app/my-alb/abc123" \
  --query 'Rules[0].Actions[0].TargetGroupArn'

# Before: "arn:aws:elasticloadbalancing:us-east-2:123456789:targetgroup/blue-tg/abc123"
# After:  "arn:aws:elasticloadbalancing:us-east-2:123456789:targetgroup/green-tg/def456"
```

## 🎯 **Summary:**

**The ALB traffic switching is configured in the ECS Service definition and automatically executed by ECS during Blue/Green deployments. You don't set it up in ALB directly - ECS handles all the ALB rule modifications for you!**

This is what makes ECS Native Blue/Green deployments so powerful - the orchestration is built into the ECS service itself.
