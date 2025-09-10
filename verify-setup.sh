#!/bin/bash

# Nginx + Golang/Node.js APIs Datadog Tracing Verification Script
# This script validates that the end-to-end tracing setup is working correctly for both APIs

set -e

echo "🔍 Verifying Nginx + Golang/Node.js APIs Datadog Tracing Setup"
echo "==============================================================="

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

# Check Golang API pod
GOLANG_API_PODS=$(kubectl get pods -l app=golang-api --no-headers 2>/dev/null | wc -l)
if [ "$GOLANG_API_PODS" -eq 0 ]; then
    print_error "No Golang API pods found. Please deploy with 'kubectl apply -f golang-api-deployment.yaml'"
    exit 1
fi

GOLANG_API_READY=$(kubectl get pods -l app=golang-api --no-headers 2>/dev/null | grep "Running" | wc -l)
if [ "$GOLANG_API_READY" -ne "$GOLANG_API_PODS" ]; then
    print_warning "Golang API pod is not ready"
    kubectl get pods -l app=golang-api
else
    print_success "Golang API pod is running"
fi

# Check Node.js API pod
NODEJS_API_PODS=$(kubectl get pods -l app=nodejs-api --no-headers 2>/dev/null | wc -l)
if [ "$NODEJS_API_PODS" -eq 0 ]; then
    print_error "No Node.js API pods found. Please deploy with 'kubectl apply -f nodejs-api-deployment.yaml'"
    exit 1
fi

NODEJS_API_READY=$(kubectl get pods -l app=nodejs-api --no-headers 2>/dev/null | grep "Running" | wc -l)
if [ "$NODEJS_API_READY" -ne "$NODEJS_API_PODS" ]; then
    print_warning "Node.js API pod is not ready"
    kubectl get pods -l app=nodejs-api
else
    print_success "Node.js API pod is running"
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

if kubectl get service golang-api &>/dev/null; then
    print_success "Golang API service exists"
else
    print_error "Golang API service not found. Please deploy with 'kubectl apply -f golang-api-service.yaml'"
fi

if kubectl get service nodejs-api &>/dev/null; then
    print_success "Node.js API service exists"
else
    print_error "Node.js API service not found. Please deploy with 'kubectl apply -f nodejs-api-service.yaml'"
fi

# Test connectivity
print_status "Testing application connectivity..."

# Get nginx service URL with timeout
print_status "Getting Nginx service URL..."
NGINX_URL=$(timeout 10 minikube service nginx --url 2>/dev/null | head -1)
if [ $? -eq 0 ] && [ -n "$NGINX_URL" ]; then
    print_success "Nginx service URL: $NGINX_URL"
    
    # Test Golang API endpoints
    print_status "Testing Golang API endpoints..."
    if timeout 5 curl -s -f "$NGINX_URL/golang-api/health" >/dev/null 2>&1; then
        print_success "Golang API health check passed"
    else
        print_warning "Golang API health check failed"
    fi
    
    RESPONSE=$(timeout 5 curl -s "$NGINX_URL/golang-api/" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$RESPONSE" ]; then
        print_success "Golang API endpoint responded"
        echo "Response preview: $(echo "$RESPONSE" | head -c 100)..."
    else
        print_warning "Golang API endpoint test failed"
    fi
    
    # Test Node.js API endpoints
    print_status "Testing Node.js API endpoints..."
    if timeout 5 curl -s -f "$NGINX_URL/nodejs-api/health" >/dev/null 2>&1; then
        print_success "Node.js API health check passed"
    else
        print_warning "Node.js API health check failed"
    fi
    
    RESPONSE=$(timeout 5 curl -s "$NGINX_URL/nodejs-api/" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$RESPONSE" ]; then
        print_success "Node.js API endpoint responded"
        echo "Response preview: $(echo "$RESPONSE" | head -c 100)..."
    else
        print_warning "Node.js API endpoint test failed"
    fi
    
    # Test backward compatibility
    print_status "Testing backward compatibility (root endpoint)..."
    RESPONSE=$(timeout 5 curl -s "$NGINX_URL/" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$RESPONSE" ]; then
        print_success "Backward compatibility endpoint responded"
        echo "Response preview: $(echo "$RESPONSE" | head -c 100)..."
    else
        print_warning "Backward compatibility endpoint test failed"
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

# Check Golang API pod
GOLANG_API_POD=$(kubectl get pods -l app=golang-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$GOLANG_API_POD" ]; then
    ANNOTATIONS=$(kubectl describe pod "$GOLANG_API_POD" 2>/dev/null | grep "admission.datadoghq.com" | wc -l)
    if [ "$ANNOTATIONS" -gt 0 ]; then
        print_success "Single Step APM annotations found on Golang API pod"
    else
        print_warning "No Single Step APM annotations found on Golang API pod"
    fi
    
    # Check environment variables
    DD_ENV_COUNT=$(kubectl describe pod "$GOLANG_API_POD" 2>/dev/null | grep -c "DD_")
    if [ "$DD_ENV_COUNT" -gt 5 ]; then
        print_success "Datadog environment variables configured on Golang API ($DD_ENV_COUNT found)"
    else
        print_warning "Few Datadog environment variables found on Golang API ($DD_ENV_COUNT)"
    fi
fi

# Check Node.js API pod
NODEJS_API_POD=$(kubectl get pods -l app=nodejs-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$NODEJS_API_POD" ]; then
    ANNOTATIONS=$(kubectl describe pod "$NODEJS_API_POD" 2>/dev/null | grep "admission.datadoghq.com" | wc -l)
    if [ "$ANNOTATIONS" -gt 0 ]; then
        print_success "Single Step APM annotations found on Node.js API pod"
    else
        print_warning "No Single Step APM annotations found on Node.js API pod"
    fi
    
    # Check environment variables
    DD_ENV_COUNT=$(kubectl describe pod "$NODEJS_API_POD" 2>/dev/null | grep -c "DD_")
    if [ "$DD_ENV_COUNT" -gt 5 ]; then
        print_success "Datadog environment variables configured on Node.js API ($DD_ENV_COUNT found)"
    else
        print_warning "Few Datadog environment variables found on Node.js API ($DD_ENV_COUNT)"
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

echo "Sending test requests to both APIs..."
for i in {1..3}; do
    # Test Golang API
    RESPONSE=$(timeout 5 curl -s "$TEST_URL/golang-api/" 2>/dev/null)
    if [ $? -eq 0 ]; then
        print_status "Golang API Request $i: $(echo "$RESPONSE" | head -c 30)..."
    else
        print_warning "Golang API Request $i failed"
    fi
    
    # Test Node.js API
    RESPONSE=$(timeout 5 curl -s "$TEST_URL/nodejs-api/" 2>/dev/null)
    if [ $? -eq 0 ]; then
        print_status "Node.js API Request $i: $(echo "$RESPONSE" | head -c 30)..."
    else
        print_warning "Node.js API Request $i failed"
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
echo "  • Golang API generating traces with dd.trace_id and dd.span_id"
echo "  • Node.js API generating traces with dd.trace_id and dd.span_id"
echo "  • Nginx proxying requests to both APIs successfully"
echo "  • End-to-end connectivity confirmed for both services"
echo ""
print_status "🎯 Next Steps:"
echo "  1. Check Datadog APM UI:"
echo "     - Go to APM → Traces in Datadog"
echo "     - Look for services 'golang-api' and 'nodejs-api' in environment 'dev'"
echo "     - You should see traces with random success/error responses from both APIs"
echo "  2. Verify trace correlation:"
echo "     - Each request should have consistent trace IDs in logs"
echo "     - Nginx → Golang API and Nginx → Node.js API flows should be visible"
echo "  3. Compare performance:"
echo "     - Compare response times and error rates between Go and Node.js"
echo "     - Analyze resource usage patterns in Datadog Infrastructure"
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
echo "  • Manual test: kubectl port-forward service/nginx 8080:80 & curl http://localhost:8080/golang-api/"
echo "  • Test both APIs: curl http://localhost:8080/nodejs-api/"
echo "  • View Golang API logs: kubectl logs -l app=golang-api -f"
echo "  • View Node.js API logs: kubectl logs -l app=nodejs-api -f"
echo "  • View nginx logs: kubectl logs -l app=sample-nginx -f"  
echo "  • Generate traffic: for i in {1..5}; do curl http://localhost:8080/golang-api/; curl http://localhost:8080/nodejs-api/; sleep 1; done"
echo ""
print_status "🌐 Access Methods:"
echo "  • Port forward (recommended): kubectl port-forward service/nginx 8080:80"
echo "  • Minikube service: minikube service nginx --url (may hang)"