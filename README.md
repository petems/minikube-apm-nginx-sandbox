# Nginx + Go API with End-to-End Datadog APM Tracing on Minikube

This project demonstrates a complete end-to-end distributed tracing setup using:

* **Nginx**: Reverse proxy with Datadog tracing module for request tracing
* **Go API**: Application with native Datadog Go tracer integration  
* **Datadog Agent**: Deployed via Helm chart for trace collection and forwarding
* **Minikube**: Local Kubernetes environment

## Architecture Overview

```
External Request → Nginx (traced) → Go API (traced) → Datadog Agent → Datadog UI
```

**Trace Correlation**: Nginx creates root spans with full 128-bit trace IDs and forwards trace context headers to the Go API, which continues the same trace as child spans. Enhanced logging shows both decimal and hexadecimal formats for easy correlation.

## Prerequisites

* Minikube installed and running
* Docker for building images
* Helm 3.x
* kubectl configured for your minikube cluster  
* Datadog account with API key

## Quick Start

### Automated Deployment (Recommended)

The fastest way to deploy everything with proper security:

```bash
# Use envchain for secure API key management (recommended)
envchain datadog env ./deploy.sh
```

**Or set API key manually:**
```bash
export DD_API_KEY="your_datadog_api_key_here"
./deploy.sh
```

**Verify everything is working:**
```bash
./verify-setup.sh
```

The automated deployment script will:
- Check prerequisites (minikube, kubectl, helm, docker)
- Start minikube (if not running)
- Build and load Docker images with latest enhancements
- Deploy Datadog Agent via Helm with proper configuration
- Deploy all applications with health check endpoints
- Set up port forwarding for immediate testing
- Show verification commands and next steps

### Manual Setup (Alternative)

If you prefer step-by-step manual deployment:

### 1. Start Minikube

```bash
minikube start
```

### 2. Build Application Images

Build the Go API image:
```bash
cd api
docker build -t api .
# Load image into minikube
minikube image load api
```

Build the Nginx image with Datadog module:
```bash
cd nginx  
docker build -t sample-nginx .
# Load image into minikube
minikube image load sample-nginx
```

### 3. Deploy Datadog Agent

Create secret with your Datadog API key:
```bash
kubectl create secret generic datadog-secret --from-literal api-key=YOUR_DD_API_KEY_HERE
```

Add Datadog Helm repository and install:
```bash
helm repo add datadog https://helm.datadoghq.com
helm repo update
helm install datadog-agent -f datadog-values.yaml datadog/datadog
```

### 4. Wait for Datadog Agent to be Ready

```bash
kubectl get pods -l app.kubernetes.io/name=datadog -w
```

Wait until all Datadog pods show `Running` status:
```
NAME                                                READY   STATUS    RESTARTS   AGE
datadog-agent-2bgmt                                 3/3     Running   0          2m
datadog-agent-cluster-agent-6f446955b4-zjl55        1/1     Running   0          2m
```

### 5. Deploy Applications

Deploy the Go API:
```bash
kubectl apply -f api-deployment.yaml
kubectl apply -f api-service.yaml
```

Deploy Nginx:
```bash
kubectl apply -f nginx-cm0-configmap.yaml
kubectl apply -f nginx-deployment.yaml
kubectl apply -f nginx-service.yaml
```

### 6. Verify Deployments

Check that all pods are running:
```bash
kubectl get pods
```

You should see output similar to:
```
NAME                                                READY   STATUS    RESTARTS   AGE
api-7d4b8c8f4d-x9z2m                               1/1     Running   0          30s
datadog-agent-2bgmt                                 3/3     Running   0          5m
datadog-agent-cluster-agent-6f446955b4-zjl55        1/1     Running   0          5m
nginx-6b8d4c5f7d-k8p9n                             1/1     Running   0          30s
```

### 7. Access the Application

Get the nginx service URL:
```bash
minikube service nginx --url
```

This will output a URL like `http://192.168.49.2:30080`. Open this in your browser or use curl:

```bash
# Test the application
curl $(minikube service nginx --url)

# Generate multiple requests to create traces
for i in {1..10}; do 
  curl $(minikube service nginx --url)
  sleep 1
done
```

## Application Details

### Go API (`api/main.go`)

The Go application:
* Uses `dd-trace-go` for native Datadog tracing with automatic trace context extraction
* Enhanced structured logging with dual-format trace/span IDs (decimal and hexadecimal)
* Dedicated `/health` endpoint for reliable Kubernetes health checks
* Generates realistic success/error responses on main endpoint for tracing demonstration
* Includes comprehensive trace tags, error handling, and request correlation

Key features:
- **Service**: `sample-api`
- **Environment**: `dev`  
- **Version**: `0.1.0`
- **Endpoints**: 
  - `/` (random responses for tracing demo - 50% success, 30% client errors, 20% server errors)
  - `/health` (always returns 200 OK for Kubernetes health checks)

### Nginx Configuration

The Nginx reverse proxy:
* Uses the official Datadog nginx module v1.7.0 for distributed tracing
* Automatically creates root spans and forwards trace context headers (`X-Datadog-Trace-Id`, `X-Datadog-Parent-Id`, `X-Datadog-Sampling-Priority`)
* Enhanced log formatting with `$datadog_trace_id` and `$datadog_span_id` variables
* Proper trace correlation with downstream Go API service
* Architecture-specific module installation (amd64/arm64 support)

**Reference Documentation:**
* [Official Datadog Nginx Tracing Guide](https://docs.datadoghq.com/tracing/trace_collection/proxy_setup/nginx/)

Key features:
- **Service**: `sample-nginx`
- **Module**: Datadog nginx-datadog v1.7.0 with dd-trace-cpp@v1.0.0
- **Trace correlation**: Forwards complete trace context to API service
- **Status endpoint**: `/nginx_status` on port 81 for Datadog integration
- **Health checks**: `/health` on both port 80 and 81

### Datadog Agent Configuration (`datadog-values.yaml`)

Optimized for Minikube with:
* **APM enabled** with Single Step Instrumentation
* **Log collection** from all containers  
* **Process monitoring** enabled
* **Cluster Agent** for Kubernetes metadata
* **Orchestrator Explorer** for cluster visibility

## Verification and Troubleshooting

### Check Single Step Instrumentation

For applications using Single Step APM (enabled for Go), verify the injection:

```bash
# Check for Datadog annotations on API pod
kubectl describe pod -l app=sample-api | grep -A 5 -B 5 admission.datadoghq.com

# Check environment variables
kubectl describe pod -l app=sample-api | grep -A 10 -B 5 "DD_"
```

### Check Trace Flow

1. **API Traces**: Verify the Go API is sending traces:
```bash
kubectl logs -l app=sample-api | grep -i trace
```

2. **Nginx Traces**: Check nginx trace correlation:
```bash
kubectl logs -l app=sample-nginx | grep "dd.trace_id"
```

3. **Datadog Agent**: Verify agent is receiving traces:
```bash
kubectl logs -l app.kubernetes.io/name=datadog | grep -i trace
```

### Health Checks

Check component health:
```bash
# Nginx health
curl $(minikube service nginx --url)/health

# API health (through nginx)
curl $(minikube service nginx --url)/

# Nginx status (for monitoring)
curl $(minikube service nginx --url):81/nginx_status
```

### Common Issues

**Pods not starting**: Check image availability in minikube:
```bash
minikube image ls | grep -E "(api|sample-nginx)"
```

**No traces in Datadog**: 
1. Verify API key is correct in the secret
2. Check Datadog agent logs for authentication errors
3. Ensure proper network connectivity from minikube

**Trace correlation not working**:
1. Check nginx configuration is properly mounted
2. Verify Datadog nginx module is loaded
3. Check trace headers are being passed between services

## Datadog Dashboard

Once traces are flowing, you can:

1. **View APM Traces**: Go to APM → Traces in Datadog UI
2. **Service Map**: See the relationship between nginx → api services
3. **Log Correlation**: Click on traces to see correlated logs
4. **Infrastructure**: Monitor Kubernetes cluster and pod metrics

## Trace Correlation Example

When a request flows through the system:

1. **Nginx** creates a root span with 128-bit trace ID `68c194b700000000414c17f0a72717c6`
2. **Nginx logs** include: `dd.trace_id="68c194b700000000414c17f0a72717c6" dd.span_id="414c17f0a72717c6"`
3. **Nginx forwards** trace headers: `X-Datadog-Trace-Id`, `X-Datadog-Parent-Id`, `X-Datadog-Sampling-Priority`  
4. **Go API** extracts trace context and continues the same trace as child span
5. **API logs** include correlated IDs: `"trace_id_hex":"414c17f0a72717c6" "span_id_hex":"65b0927be4a29005"`
6. **Datadog UI** shows the complete distributed trace with parent-child span relationships

**Result**: Complete end-to-end visibility from nginx proxy through Go API with matching trace correlation.

## Log-to-Trace Correlation in Datadog

**Important**: The trace correlation shown in logs above is primarily for **easier local debugging**. In the Datadog platform, proper log-to-trace correlation happens automatically through **log processing pipelines**:

### Automatic Correlation Process:
1. **Nginx logs** include `dd.trace_id` and `dd.span_id` in the log format
2. **Datadog log pipeline** parses these fields using a Grok parser:
   ```
   extract_correlation_ids %{data} dd.trace_id="%{notSpace:dd.trace_id:nullIf("-")}" dd.span_id="%{notSpace:dd.span_id:nullIf("-")}"
   ```
3. **Trace ID Remapper** associates the parsed trace ID with its corresponding APM trace
4. **Span ID Remapper** associates the parsed span ID with its corresponding APM span
5. **Result**: Automatic correlation between logs and traces in the Datadog UI

The dual hex/decimal format we added to the Go API logs is a debugging enhancement that makes it easier to visually match trace IDs when troubleshooting locally, but the actual platform correlation relies on Datadog's log processing pipeline.

## Configuration Files

- `datadog-values.yaml`: Helm values for Datadog agent deployment
- `api-deployment.yaml`: Go API Kubernetes deployment with Datadog configuration
- `nginx-deployment.yaml`: Nginx deployment with tracing enabled
- `nginx-cm0-configmap.yaml`: Nginx configuration with Datadog module setup
- Service files: Kubernetes services for networking

## Development

To modify the applications:

1. **Go API**: Edit `api/main.go`, rebuild with `docker build -t api .`
2. **Nginx**: Edit `nginx/Dockerfile` or nginx config, rebuild with `docker build -t sample-nginx .`  
3. **Reload images**: `minikube image load <image-name>`
4. **Restart deployments**: `kubectl rollout restart deployment/<deployment-name>`

## Automated Scripts

For convenience, this project includes automated deployment and verification scripts:

### Quick Deploy Script

Deploy everything automatically:
```bash
# Set your Datadog API key
export DD_API_KEY="your_datadog_api_key_here"

# Run the deployment script
./deploy.sh
```

This script will:
- Start minikube (if not running)
- Build and load Docker images  
- Deploy Datadog Agent via Helm
- Deploy all applications
- Wait for everything to be ready
- Provide service URLs and next steps

### Verification Script

Verify your deployment is working:
```bash
./verify-setup.sh
```

This script will:
- Check all pods are running
- Test service connectivity
- Verify Single Step APM configuration
- Generate test traffic
- Provide troubleshooting information

## Manual Setup

If you prefer manual deployment, follow the Quick Start section above.

## Cleanup

Remove all components:
```bash
# Remove applications
kubectl delete -f api-deployment.yaml -f api-service.yaml
kubectl delete -f nginx-deployment.yaml -f nginx-service.yaml -f nginx-cm0-configmap.yaml

# Remove Datadog agent
helm uninstall datadog-agent

# Remove secret  
kubectl delete secret datadog-secret

# Stop minikube (optional)
minikube stop
```

Or use the cleanup portion of the deploy script:
```bash
# Quick cleanup (add this to deploy.sh if needed)
kubectl delete deployment,service,configmap -l app=sample-api
kubectl delete deployment,service,configmap -l app=sample-nginx
helm uninstall datadog-agent
kubectl delete secret datadog-secret
```