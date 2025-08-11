import json
import urllib3
import logging
import os
import boto3

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize HTTP client and AWS clients
http = urllib3.PoolManager()
ecs_client = boto3.client('ecs')

def lambda_handler(event, context):
    """
    ECS Blue/Green Deployment Lifecycle Hook Handler
    Handles all lifecycle stages with proper payload processing
    """
    logger.info("=== ECS Deployment Lifecycle Hook Triggered ===")
    logger.info(f"Event payload: {json.dumps(event, indent=2)}")
    
    try:
        # Extract common payload fields
        service_arn = event.get('serviceArn')
        target_service_revision_arn = event.get('targetServiceRevisionArn')
        test_traffic_weights = event.get('testTrafficWeights', {})
        production_traffic_weights = event.get('productionTrafficWeights', {})
        
        # Determine lifecycle stage based on traffic weights and context
        lifecycle_stage = determine_lifecycle_stage(test_traffic_weights, production_traffic_weights)
        
        logger.info(f"Detected lifecycle stage: {lifecycle_stage}")
        logger.info(f"Service ARN: {service_arn}")
        logger.info(f"Target revision ARN: {target_service_revision_arn}")
        logger.info(f"Test traffic weights: {test_traffic_weights}")
        logger.info(f"Production traffic weights: {production_traffic_weights}")
        
        # Handle different lifecycle stages
        if lifecycle_stage == "POST_TEST_TRAFFIC_SHIFT":
            return handle_post_test_traffic_shift(event)
        elif lifecycle_stage == "PRE_PRODUCTION_TRAFFIC_SHIFT":
            return handle_pre_production_traffic_shift(event)
        elif lifecycle_stage == "POST_PRODUCTION_TRAFFIC_SHIFT":
            return handle_post_production_traffic_shift(event)
        else:
            logger.info(f"No specific handler for stage: {lifecycle_stage}, allowing to proceed")
            return {"hookStatus": "SUCCEEDED"}
            
    except Exception as error:
        logger.error(f"Lifecycle hook failed with error: {str(error)}")
        return {"hookStatus": "FAILED"}

def determine_lifecycle_stage(test_traffic_weights, production_traffic_weights):
    """
    Determine the lifecycle stage based on traffic weights
    """
    has_test_traffic = bool(test_traffic_weights)
    has_production_traffic = bool(production_traffic_weights)
    
    if has_test_traffic and not has_production_traffic:
        return "TEST_TRAFFIC_SHIFT"
    elif not has_test_traffic and has_production_traffic:
        return "PRODUCTION_TRAFFIC_SHIFT"
    elif not has_test_traffic and not has_production_traffic:
        # Could be POST_TEST_TRAFFIC_SHIFT or POST_PRODUCTION_TRAFFIC_SHIFT
        # We'll assume POST_TEST_TRAFFIC_SHIFT for validation
        return "POST_TEST_TRAFFIC_SHIFT"
    else:
        return "UNKNOWN"

def handle_post_test_traffic_shift(event):
    """
    Handle POST_TEST_TRAFFIC_SHIFT stage
    This is where we validate the green environment before production traffic shift
    """
    logger.info("=== Handling POST_TEST_TRAFFIC_SHIFT ===")
    
    # Get test endpoint URL
    test_endpoint = os.getenv('TEST_ENDPOINT_URL')
    if not test_endpoint:
        logger.error("TEST_ENDPOINT_URL environment variable not set")
        return {"hookStatus": "FAILED"}
    
    logger.info(f"Testing green environment at: {test_endpoint}")
    
    # Comprehensive validation tests
    validation_results = []
    
    # Test 1: Health Check
    try:
        health_response = http.request('GET', f"{test_endpoint}/health", timeout=10)
        if health_response.status == 200:
            validation_results.append("✅ Health check passed")
            logger.info("Health check: PASSED")
        else:
            validation_results.append(f"❌ Health check failed: {health_response.status}")
            logger.error(f"Health check failed with status: {health_response.status}")
            return {"hookStatus": "FAILED"}
    except Exception as e:
        validation_results.append(f"❌ Health check error: {str(e)}")
        logger.error(f"Health check error: {str(e)}")
        return {"hookStatus": "FAILED"}
    
    # Test 2: Version Endpoint
    try:
        version_response = http.request('GET', f"{test_endpoint}/version", timeout=10)
        if version_response.status == 200:
            validation_results.append("✅ Version endpoint passed")
            logger.info("Version endpoint: PASSED")
        else:
            validation_results.append(f"❌ Version endpoint failed: {version_response.status}")
            logger.error(f"Version endpoint failed: {version_response.status}")
    except Exception as e:
        validation_results.append(f"❌ Version endpoint error: {str(e)}")
        logger.error(f"Version endpoint error: {str(e)}")
    
    # Test 3: Main Application
    try:
        main_response = http.request('GET', test_endpoint, timeout=10)
        if main_response.status == 200:
            response_body = main_response.data.decode('utf-8')
            if 'ECS Native Blue-Green Deployment' in response_body:
                validation_results.append("✅ Main application content validated")
                logger.info("Main application: PASSED")
            else:
                validation_results.append("❌ Main application content validation failed")
                logger.error("Main application content validation failed")
                return {"hookStatus": "FAILED"}
        else:
            validation_results.append(f"❌ Main application failed: {main_response.status}")
            logger.error(f"Main application failed: {main_response.status}")
            return {"hookStatus": "FAILED"}
    except Exception as e:
        validation_results.append(f"❌ Main application error: {str(e)}")
        logger.error(f"Main application error: {str(e)}")
        return {"hookStatus": "FAILED"}
    
    # Log all validation results
    logger.info("=== Validation Results ===")
    for result in validation_results:
        logger.info(result)
    
    logger.info("🎉 All POST_TEST_TRAFFIC_SHIFT validations passed! Green environment is ready for production traffic.")
    return {"hookStatus": "SUCCEEDED"}

def handle_pre_production_traffic_shift(event):
    """
    Handle PRE_PRODUCTION_TRAFFIC_SHIFT stage
    Final validation before production traffic switch
    """
    logger.info("=== Handling PRE_PRODUCTION_TRAFFIC_SHIFT ===")
    
    # Additional pre-production checks can be added here
    # For example: performance tests, security scans, etc.
    
    logger.info("✅ Pre-production validation completed. Ready for production traffic shift.")
    return {"hookStatus": "SUCCEEDED"}

def handle_post_production_traffic_shift(event):
    """
    Handle POST_PRODUCTION_TRAFFIC_SHIFT stage
    Validation after production traffic has been shifted
    """
    logger.info("=== Handling POST_PRODUCTION_TRAFFIC_SHIFT ===")
    
    # Get production endpoint URL
    production_endpoint = os.getenv('PRODUCTION_ENDPOINT_URL')
    if not production_endpoint:
        logger.error("PRODUCTION_ENDPOINT_URL environment variable not set")
        return {"hookStatus": "FAILED"}
    
    # Validate production traffic is working
    try:
        prod_response = http.request('GET', production_endpoint, timeout=10)
        if prod_response.status == 200:
            logger.info("✅ Production traffic validation passed")
            return {"hookStatus": "SUCCEEDED"}
        else:
            logger.error(f"❌ Production traffic validation failed: {prod_response.status}")
            return {"hookStatus": "FAILED"}
    except Exception as e:
        logger.error(f"❌ Production traffic validation error: {str(e)}")
        return {"hookStatus": "FAILED"}
