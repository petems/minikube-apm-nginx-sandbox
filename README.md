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

**Trace Correlation**: Both Nginx and the Go API generate trace spans that are correlated through distributed trace headers, providing complete visibility into request flow.

## Prerequisites

* Minikube installed and running
* Docker for building images
* Helm 3.x
* kubectl configured for your minikube cluster  
* Datadog account with API key

## Quick Start

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
* Uses `dd-trace-go` for native Datadog tracing
* Implements structured logging with trace correlation
* Generates random success/error responses for demonstration
* Includes comprehensive trace tags and error handling

Key features:
- **Service**: `sample-api`
- **Environment**: `dev`  
- **Version**: `0.1.0`
- **Endpoints**: `/` (random responses)

### Nginx Configuration

The Nginx reverse proxy:
* Uses the official Datadog nginx module for tracing
* Configured for trace correlation with downstream services
* Includes proper log formatting with trace IDs
* Provides health checks and status endpoints

Key features:
- **Service**: `sample-nginx`
- **Trace correlation**: Passes trace headers to upstream
- **Status endpoint**: `/nginx_status` on port 81
- **Health check**: `/health`

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

1. **Nginx** creates a root span with trace ID `123456789`
2. **Nginx logs** include: `dd.trace_id="123456789" dd.span_id="987654321"`  
3. **Go API** continues the trace with the same trace ID `123456789`
4. **API logs** include the same trace ID for correlation
5. **Datadog UI** shows the complete request journey across both services

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