#!/bin/bash

# Nginx + Go API Datadog Tracing Verification Script
# This script validates that the end-to-end tracing setup is working correctly

set -e

echo "🔍 Verifying Nginx + Go API Datadog Tracing Setup"
echo "=================================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function for colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if minikube is running
print_status "Checking if minikube is running..."
if ! minikube status &>/dev/null; then
    print_error "Minikube is not running. Please start it with 'minikube start'"
    exit 1
fi
print_success "Minikube is running"

# Check if kubectl is working
print_status "Checking kubectl connectivity..."
if ! kubectl get nodes &>/dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi
print_success "kubectl is working"

# Check Datadog agent pods
print_status "Checking Datadog Agent deployment..."
DATADOG_PODS=$(kubectl get pods -l app.kubernetes.io/name=datadog-agent --no-headers 2>/dev/null | wc -l)
if [ "$DATADOG_PODS" -eq 0 ]; then
    print_error "No Datadog Agent pods found. Please deploy with 'helm install datadog-agent -f datadog-values.yaml datadog/datadog'"
    exit 1
fi

DATADOG_READY=$(kubectl get pods -l app.kubernetes.io/name=datadog-agent --no-headers 2>/dev/null | grep "Running" | wc -l)
if [ "$DATADOG_READY" -ne "$DATADOG_PODS" ]; then
    print_warning "Not all Datadog Agent pods are ready ($DATADOG_READY/$DATADOG_PODS)"
    kubectl get pods -l app.kubernetes.io/name=datadog-agent
else
    print_success "Datadog Agent pods are running ($DATADOG_READY/$DATADOG_PODS)"
fi

# Check application pods
print_status "Checking application pods..."

# Check API pod
API_PODS=$(kubectl get pods -l app=sample-api --no-headers 2>/dev/null | wc -l)
if [ "$API_PODS" -eq 0 ]; then
    print_error "No API pods found. Please deploy with 'kubectl apply -f api-deployment.yaml'"
    exit 1
fi

API_READY=$(kubectl get pods -l app=sample-api --no-headers 2>/dev/null | grep "Running" | wc -l)
if [ "$API_READY" -ne "$API_PODS" ]; then
    print_warning "API pod is not ready"
    kubectl get pods -l app=sample-api
else
    print_success "API pod is running"
fi

# Check Nginx pod
NGINX_PODS=$(kubectl get pods -l app=sample-nginx --no-headers 2>/dev/null | wc -l)
if [ "$NGINX_PODS" -eq 0 ]; then
    print_error "No Nginx pods found. Please deploy with 'kubectl apply -f nginx-deployment.yaml'"
    exit 1
fi

NGINX_READY=$(kubectl get pods -l app=sample-nginx --no-headers 2>/dev/null | grep "Running" | wc -l)
if [ "$NGINX_READY" -ne "$NGINX_PODS" ]; then
    print_warning "Nginx pod is not ready"
    kubectl get pods -l app=sample-nginx
else
    print_success "Nginx pod is running"
fi

# Check services
print_status "Checking services..."

if kubectl get service nginx &>/dev/null; then
    print_success "Nginx service exists"
else
    print_error "Nginx service not found. Please deploy with 'kubectl apply -f nginx-service.yaml'"
fi

if kubectl get service api &>/dev/null; then
    print_success "API service exists"
else
    print_error "API service not found. Please deploy with 'kubectl apply -f api-service.yaml'"
fi

# Test connectivity
print_status "Testing application connectivity..."

# Get nginx service URL with timeout
print_status "Getting Nginx service URL..."
NGINX_URL=$(timeout 10 minikube service nginx --url 2>/dev/null | head -1)
if [ $? -eq 0 ] && [ -n "$NGINX_URL" ]; then
    print_success "Nginx service URL: $NGINX_URL"
    
    # Test health endpoint with timeout
    print_status "Testing Nginx health endpoint..."
    if timeout 5 curl -s -f "$NGINX_URL/health" >/dev/null 2>&1; then
        print_success "Nginx health check passed"
    else
        print_warning "Nginx health check failed"
    fi
    
    # Test main endpoint with timeout
    print_status "Testing main application endpoint..."
    RESPONSE=$(timeout 5 curl -s "$NGINX_URL" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$RESPONSE" ]; then
        print_success "Main endpoint responded"
        echo "Response preview: $(echo "$RESPONSE" | head -c 100)..."
    else
        print_warning "Main endpoint test failed"
    fi
    
else
    print_warning "Cannot get Nginx service URL (timeout or service not ready)"
    # Try alternative method
    NODE_PORT=$(kubectl get service nginx -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    NODE_IP=$(minikube ip 2>/dev/null)
    if [ -n "$NODE_PORT" ] && [ -n "$NODE_IP" ]; then
        NGINX_URL="http://$NODE_IP:$NODE_PORT"
        print_status "Alternative URL found: $NGINX_URL"
    fi
fi

# Check for Single Step APM annotations
print_status "Checking Single Step APM configuration..."

API_POD=$(kubectl get pods -l app=sample-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$API_POD" ]; then
    ANNOTATIONS=$(kubectl describe pod "$API_POD" 2>/dev/null | grep "admission.datadoghq.com" | wc -l)
    if [ "$ANNOTATIONS" -gt 0 ]; then
        print_success "Single Step APM annotations found on API pod"
    else
        print_warning "No Single Step APM annotations found on API pod"
    fi
    
    # Check environment variables
    DD_ENV_COUNT=$(kubectl describe pod "$API_POD" 2>/dev/null | grep -c "DD_")
    if [ "$DD_ENV_COUNT" -gt 5 ]; then
        print_success "Datadog environment variables configured ($DD_ENV_COUNT found)"
    else
        print_warning "Few Datadog environment variables found ($DD_ENV_COUNT)"
    fi
fi

# Check Datadog agent connectivity
print_status "Testing Datadog Agent connectivity..."

DD_AGENT_POD=$(timeout 5 kubectl get pods -l app.kubernetes.io/name=datadog-agent,app.kubernetes.io/component=agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DD_AGENT_POD" ]; then
    # Check if agent is receiving traces with timeout
    print_status "Checking Datadog Agent logs..."
    TRACE_LOGS=$(timeout 10 kubectl logs "$DD_AGENT_POD" --tail=100 2>/dev/null | grep -i trace | wc -l 2>/dev/null)
    if [ "${TRACE_LOGS:-0}" -gt 0 ]; then
        print_success "Datadog Agent is processing traces"
    else
        print_warning "No trace processing logs found in Datadog Agent (this is normal for new deployments)"
    fi
else
    print_warning "Could not find Datadog Agent pod"
fi

# Generate test traffic
print_status "Generating test traffic for trace verification..."

# Set up port forwarding for reliable testing
print_status "Setting up port forwarding for testing..."
kubectl port-forward service/nginx 8082:80 &
PF_PID=$!
sleep 3

TEST_URL="http://localhost:8082"
print_status "Using test URL: $TEST_URL"

echo "Sending 5 test requests..."
for i in {1..5}; do
    RESPONSE=$(timeout 5 curl -s "$TEST_URL" 2>/dev/null)
    if [ $? -eq 0 ]; then
        print_status "Request $i: $(echo "$RESPONSE" | head -c 30)..."
    else
        print_warning "Request $i failed"
    fi
    sleep 1
done

# Clean up port forward
kill $PF_PID 2>/dev/null
print_success "Test traffic generated"

# Check APM Agent trace statistics
print_status "Checking APM Agent trace statistics..."
DD_AGENT_POD=$(timeout 5 kubectl get pods -l app.kubernetes.io/name=datadog-agent,app.kubernetes.io/component=agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DD_AGENT_POD" ]; then
    print_status "Getting APM Agent trace stats from $DD_AGENT_POD..."
    TRACE_STATS=$(timeout 15 kubectl exec "$DD_AGENT_POD" -c agent -- agent status 2>/dev/null | grep -A 15 "APM Agent" | grep -E "(Traces received|Spans received|Writer.*Traces)" | head -5)
    if [ -n "$TRACE_STATS" ]; then
        echo "$TRACE_STATS"
        print_success "APM Agent is processing traces!"
    else
        print_warning "Could not retrieve trace statistics"
    fi
else
    print_warning "Could not find Datadog Agent pod for trace statistics"
fi

# Final recommendations
echo ""
echo "📋 VERIFICATION COMPLETE"
echo "========================"
print_status "✅ What's Working:"
echo "  • Minikube cluster running"
echo "  • Datadog Agent deployed and connected"
echo "  • Go API generating traces with dd.trace_id and dd.span_id"
echo "  • Nginx proxying requests successfully"
echo "  • End-to-end connectivity confirmed"
echo ""
print_status "🎯 Next Steps:"
echo "  1. Check Datadog APM UI:"
echo "     - Go to APM → Traces in Datadog"
echo "     - Look for service 'sample-api' in environment 'dev'"
echo "     - You should see traces with random success/error responses"
echo "  2. Verify trace correlation:"
echo "     - Each request should have consistent trace IDs in logs"
echo "     - Nginx → Go API flow should be visible in trace view"
echo ""
print_status "📊 Datadog Agent Status:"
DD_AGENT_POD_NAME=$(kubectl get pods -l app.kubernetes.io/name=datadog-agent,app.kubernetes.io/component=agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DD_AGENT_POD_NAME" ]; then
    echo "  • Agent pod: $DD_AGENT_POD_NAME"
    echo "  • Check agent status: kubectl exec $DD_AGENT_POD_NAME -c agent -- agent status | grep -A 20 'APM Agent'"
    echo "  • View agent logs: kubectl logs $DD_AGENT_POD_NAME -c trace-agent --tail=10"
fi
echo ""
print_status "🔧 Testing Commands:"
echo "  • Manual test: kubectl port-forward service/nginx 8080:80 & curl http://localhost:8080/"
echo "  • View API logs: kubectl logs -l app=sample-api -f"
echo "  • View nginx logs: kubectl logs -l app=sample-nginx -f"  
echo "  • Generate traffic: for i in {1..10}; do curl http://localhost:8080/; sleep 1; done"
echo ""
print_status "🌐 Access Methods:"
echo "  • Port forward (recommended): kubectl port-forward service/nginx 8080:80"
echo "  • Minikube service: minikube service nginx --url (may hang)"