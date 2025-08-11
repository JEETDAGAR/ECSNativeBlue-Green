from flask import Flask, jsonify, render_template_string
import os
import datetime
import socket

app = Flask(__name__)

# Get version from environment variable (default to v1.0)
VERSION = os.environ.get('APP_VERSION', 'v1.0')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'Blue')

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>ECS Blue-Green Demo App</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            text-align: center;
            padding: 0;
            margin: 0;
            background: linear-gradient(135deg, {{ bg_gradient }});
            color: white;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            max-width: 700px;
            margin: 0 auto;
            background-color: rgba(255,255,255,0.15);
            padding: 50px;
            border-radius: 20px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255,255,255,0.2);
        }
        .title {
            font-size: 2.5em;
            margin-bottom: 30px;
            font-weight: 300;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .version {
            font-size: 4em;
            margin: 30px 0;
            font-weight: bold;
            text-shadow: 3px 3px 6px rgba(0,0,0,0.4);
            background: rgba(255,255,255,0.2);
            padding: 20px;
            border-radius: 15px;
            display: inline-block;
            min-width: 200px;
        }
        .environment {
            font-size: 2em;
            margin: 20px 0;
            font-weight: 500;
            padding: 15px 30px;
            background: rgba(255,255,255,0.2);
            border-radius: 25px;
            display: inline-block;
        }
        .description {
            font-size: 1.3em;
            margin: 30px 0;
            line-height: 1.6;
            opacity: 0.9;
        }
        .feature-list {
            text-align: left;
            margin: 30px auto;
            max-width: 500px;
            font-size: 1.1em;
        }
        .feature-list li {
            margin: 10px 0;
            padding: 5px 0;
        }
        .badge {
            display: inline-block;
            padding: 8px 16px;
            background: rgba(255,255,255,0.3);
            border-radius: 20px;
            font-size: 0.9em;
            margin: 5px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="title">ECS Native Blue-Green Deployment</h1>
        
        <div class="version">{{ version }}</div>
        
        <div class="environment">{{ environment }} Environment</div>
        
        <div class="description">
            Experience zero-downtime deployments with AWS ECS Native Blue-Green strategy
        </div>
        
        <div class="feature-list">
            <ul>
                <li>✅ Zero-downtime deployments</li>
                <li>✅ Automatic traffic switching</li>
                <li>✅ Built-in rollback capability</li>
                <li>✅ Health check validation</li>
                <li>✅ No CodeDeploy required</li>
            </ul>
        </div>
        
        <div>
            <span class="badge">AWS ECS</span>
            <span class="badge">Application Load Balancer</span>
            <span class="badge">Fargate</span>
        </div>
    </div>
</body>
</html>
"""

@app.route('/')
def home():
    # Set gradient colors based on environment
    if ENVIRONMENT.lower() == 'green':
        bg_gradient = '#4CAF50, #45a049, #2E7D32'
    else:
        bg_gradient = '#2196F3, #1976D2, #0D47A1'
    
    return render_template_string(
        HTML_TEMPLATE,
        version=VERSION,
        environment=ENVIRONMENT,
        bg_gradient=bg_gradient
    )

@app.route('/health')
def health_check():
    return jsonify({
        'status': 'healthy',
        'version': VERSION,
        'environment': ENVIRONMENT,
        'timestamp': datetime.datetime.now().isoformat()
    })

@app.route('/version')
def version():
    return jsonify({
        'version': VERSION,
        'environment': ENVIRONMENT
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80, debug=False)
