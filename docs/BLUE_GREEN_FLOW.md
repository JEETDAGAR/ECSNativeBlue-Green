# ECS Native Blue/Green Deployment Flow

## How It Should Work (Fixed Implementation)

### Initial State
- **Blue Target Group**: Contains running tasks serving production traffic (100%)
- **Green Target Group**: Empty (0% traffic)
- **Production ALB (Port 80)**: Routes to Blue Target Group
- **Test ALB (Port 8080)**: Routes to Green Target Group

### During Deployment

#### Phase 1: Deploy to Green
1. **ECS starts new tasks** with updated task definition
2. **New tasks register in Green Target Group**
3. **Production traffic continues** flowing to Blue Target Group (zero downtime)
4. **Test traffic (port 8080)** can validate Green Target Group

#### Phase 2: Validation
1. **Lifecycle hooks trigger** to validate Green environment
2. **Lambda function tests** Green Target Group via port 8080
3. **Health checks pass** on Green Target Group
4. **Validation succeeds** → proceed to traffic switch

#### Phase 3: Traffic Switch
1. **ECS modifies ALB listener rule** using Blue/Green role
2. **Production listener (port 80)** switches from Blue → Green Target Group
3. **Traffic instantly switches** to new version (Green)
4. **Blue Target Group** stops receiving production traffic

#### Phase 4: Cleanup
1. **Old tasks in Blue Target Group** are drained
2. **Blue tasks are terminated** after connection draining
3. **Blue Target Group becomes empty**
4. **Green Target Group** now serves 100% of production traffic

### Post-Deployment State
- **Blue Target Group**: Empty (ready for next deployment)
- **Green Target Group**: Contains current production tasks (100% traffic)
- **Next deployment**: Will deploy to Blue Target Group and switch back

## Key Components

### ALB Configuration
```yaml
# Production Listener (Port 80)
- Initially routes to Blue Target Group
- ECS switches this to Green during deployment
- Handles 100% of production traffic

# Test Listener (Port 8080)  
- Always routes to Green Target Group
- Used for validation during deployment
- Allows testing before traffic switch
```

### ECS Service Configuration
```json
{
  "deploymentConfiguration": {
    "strategy": "BLUE_GREEN",
    "bakeTimeInMinutes": 2,
    "lifecycleHooks": [...]
  },
  "loadBalancers": [
    {
      "targetGroupArn": "BLUE_TARGET_GROUP_ARN",
      "advancedConfiguration": {
        "alternateTargetGroupArn": "GREEN_TARGET_GROUP_ARN",
        "productionListenerRule": "PRODUCTION_LISTENER_RULE_ARN",
        "testListenerRule": "TEST_LISTENER_RULE_ARN",
        "roleArn": "ECS_BLUE_GREEN_ROLE_ARN"
      }
    }
  ]
}
```

### IAM Role Permissions
The ECS Blue/Green role needs permissions to:
- Modify ALB listener rules
- Register/deregister targets from target groups
- Invoke lifecycle hook Lambda functions

## Benefits of This Approach

1. **Zero Downtime**: Production traffic never stops flowing
2. **Instant Rollback**: Can immediately switch back to previous version
3. **Safe Validation**: Test new version before switching production traffic
4. **Atomic Switch**: Traffic switches instantly, not gradually
5. **Clean Separation**: Blue and Green environments are completely separate

## Monitoring the Deployment

### During Deployment
- **Blue Target Group**: Should show healthy targets serving production
- **Green Target Group**: Should show new targets being deployed and validated
- **ALB Listeners**: Production should route to Blue, Test should route to Green

### After Traffic Switch
- **Blue Target Group**: Should show targets being drained and removed
- **Green Target Group**: Should show healthy targets serving production
- **ALB Listeners**: Production should now route to Green

### Post-Deployment
- **Blue Target Group**: Should be empty
- **Green Target Group**: Should contain all production targets
- **Ready for next deployment**: Next deployment will use Blue as the alternate

## Troubleshooting

### If Traffic Doesn't Switch
1. Check ECS Blue/Green role permissions
2. Verify ALB listener rule configuration
3. Check lifecycle hook Lambda function logs
4. Ensure target groups are properly configured

### If Deployment Rolls Back
1. Check lifecycle hook validation logic
2. Verify Green target group health checks
3. Review Lambda function logs for errors
4. Check application startup issues in Green environment
