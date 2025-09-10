# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Kubernetes-based end-to-end distributed tracing demonstration** using Nginx + Go API with Datadog APM. The project showcases how to implement complete request tracing from a reverse proxy through to a backend application in a Minikube environment.

### Architecture

```
External Request → Nginx (traced) → Go API (traced) → Datadog Agent → Datadog UI
```

**Core Components:**
- **Go API** (`api/`): Instrumented with dd-trace-go v1.52.0, generates structured JSON logs with trace correlation
- **Nginx Reverse Proxy** (`nginx/`): Custom image with Datadog module for request proxying and monitoring
- **Datadog Agent**: Deployed via Helm chart with Single Step APM instrumentation enabled
- **Kubernetes Manifests**: Complete deployment configurations for Minikube

## Development Commands

### Core Operations

**Build and deploy everything:**
```bash
# Use envchain for secure API key management
envchain datadog env ./deploy.sh
```

**Verify deployment:**
```bash
./verify-setup.sh
```

**Manual deployment steps:**
```bash
# 1. Start minikube
minikube start

# 2. Build images
cd api && docker build -t api . && cd ..
cd nginx && docker build -t sample-nginx . && cd ..

# 3. Load images into minikube
minikube image load api:latest
minikube image load sample-nginx:latest

# 4. Deploy Datadog Agent
kubectl create secret generic datadog-secret --from-literal api-key=YOUR_KEY
helm repo add datadog https://helm.datadoghq.com
helm install datadog-agent -f datadog-values.yaml datadog/datadog

# 5. Deploy applications
kubectl apply -f nginx-cm0-configmap.yaml
kubectl apply -f api-deployment.yaml -f api-service.yaml
kubectl apply -f nginx-deployment.yaml -f nginx-service.yaml
```

**Testing and debugging:**
```bash
# Access application (most reliable)
kubectl port-forward service/nginx 8080:80 &
curl http://localhost:8080/health

# Alternative access method (may hang on some systems)
minikube service nginx --url

# Check logs
kubectl logs -l app=sample-api -f          # Go API logs with trace IDs
kubectl logs -l app=sample-nginx -f        # Nginx access logs
kubectl logs -l app.kubernetes.io/name=datadog-agent -c trace-agent # Datadog trace agent

# Check APM agent status and trace statistics
kubectl exec $(kubectl get pods -l app.kubernetes.io/component=agent -o jsonpath='{.items[0].metadata.name}') -c agent -- agent status | grep -A 20 "APM Agent"
```

**Load testing:**
```bash
make stress  # Uses vegeta for load testing (requires vegeta installed)
```

## Code Architecture

### Go Application (`api/`)

**Key Files:**
- `main.go`: HTTP server with Datadog tracing using gorilla/mux and dd-trace-go
- `logger.go`: Custom logger wrapper with Datadog trace correlation hooks
- `Dockerfile`: Multi-stage Alpine-based build for minimal container size

**Tracing Implementation:**
- Uses `muxtrace.NewRouter()` for automatic HTTP span creation
- Implements custom span tagging with request IDs, HTTP details, and error classification
- Structured JSON logging with `dd.trace_id` and `dd.span_id` injection via `ddtracelogrus.DDContextLogHook{}`
- Simulates realistic error scenarios (client errors, server errors, timeouts)

**Environment Configuration:**
The Go app expects these Datadog environment variables (set in Kubernetes deployment):
- `DD_AGENT_HOST=datadog-agent` (Kubernetes service name)
- `DD_TRACE_AGENT_URL=http://datadog-agent:8126`
- `DD_SERVICE=sample-api`, `DD_ENV=dev`, `DD_VERSION=0.1.0`

### Nginx Configuration (`nginx/`)

**Custom Image:**
- Based on nginx:1.28.0 with Datadog nginx module installed
- Downloads appropriate architecture-specific Datadog module from GitHub releases
- Supports both amd64 and arm64 architectures

**Configuration Features:**
- Upstream load balancing to `api:8080` service
- Health check endpoints on both main (`:80/health`) and status (`:81/health`) servers
- Nginx status endpoint (`:81/nginx_status`) for Datadog monitoring integration
- Enhanced logging format with timing information

### Kubernetes Deployment

**Service Discovery:**
- `nginx` service: LoadBalancer type, ports 80 (main) and 81 (status)
- `api` service: ClusterIP type, port 8080
- `datadog-agent` service: Created by Helm chart, port 8126 for traces

**Single Step APM Integration:**
The API deployment uses Datadog's Single Step APM with these key annotations:
```yaml
admission.datadoghq.com/enabled: "true"
admission.datadoghq.com/go-lib.version: "latest"
```

**Unified Service Tagging:**
All components use consistent labeling:
```yaml
tags.datadoghq.com/env: "dev"
tags.datadoghq.com/service: "sample-api" | "sample-nginx"  
tags.datadoghq.com/version: "0.1.0"
```

### Datadog Agent Configuration (`datadog-values.yaml`)

**Key Features Enabled:**
- APM with Single Step Instrumentation for Go applications
- Log collection from all containers with automatic trace correlation
- Cluster Agent with metrics provider and cluster checks
- Process monitoring and orchestrator explorer
- Optimized for Minikube environment (`kubelet.tlsVerify: false`)

## Important Technical Details

### Trace Correlation Flow
1. **Request Ingress**: External request hits nginx LoadBalancer service
2. **Nginx Proxy**: Nginx creates initial spans (when Datadog module is properly configured)
3. **API Processing**: Go API continues trace with same trace ID, logs include `dd.trace_id` and `dd.span_id`
4. **Agent Collection**: Traces sent to `datadog-agent:8126` service endpoint
5. **Datadog Upload**: Agent forwards traces to `https://trace.agent.datadoghq.com`

### Container Images
- **API Image**: Multi-stage build (golang:1.25-alpine → alpine:latest), runs as non-root user
- **Nginx Image**: nginx:1.28.0 + Datadog module, architecture detection for module download
- Both images use `imagePullPolicy: Never` for local Minikube development

### Common Issues and Solutions

**Image Pull Errors**: Images must be built locally and loaded with `minikube image load <image>:latest`

**Service Access Hanging**: Use `kubectl port-forward service/nginx 8080:80` instead of `minikube service nginx --url`

**No Traces in Datadog**: 
- Verify API key in secret: `kubectl get secret datadog-secret -o yaml`
- Check agent connectivity: Agent status should show "API Key valid"
- Confirm trace reception: APM Agent status should show "Traces received: X"

**Single Step APM Not Working**: Check pod description for init containers (`datadog-init-apm-inject`, `datadog-lib-java-init`)

## Security Notes

- Uses `envchain datadog` for secure API key management
- API runs as non-root user (appuser:appgroup, UID/GID 1001)  
- Nginx status endpoint has IP-based access restrictions
- All secrets managed via Kubernetes Secret objects, never in plain text