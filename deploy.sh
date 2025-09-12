#!/bin/bash

# Nginx + Go API Datadog Tracing Deployment Script
# This script deploys the complete setup in the correct order

set -e

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

echo "🚀 Deploying Nginx + Go API with Datadog Tracing"
echo "================================================="

# Check prerequisites
print_status "Checking prerequisites..."

if ! command -v minikube &> /dev/null; then
    print_error "minikube is not installed"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    print_error "helm is not installed"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    print_error "docker is not installed"
    exit 1
fi

print_success "All prerequisites are available"

# Check if minikube is running
print_status "Checking minikube status..."
if ! minikube status &>/dev/null; then
    print_status "Starting minikube..."
    minikube start
    sleep 10
fi
print_success "Minikube is running"

# Build and load images
print_status "Building and loading application images..."

print_status "Building Golang API image..."
if [ -d "golang-api" ]; then
    cd golang-api
    docker build -t golang-api .
    minikube image load golang-api
    cd ..
    print_success "Golang API image built and loaded"
else
    print_error "golang-api directory not found. Please run this script from the project root."
    exit 1
fi

print_status "Building Node.js API image..."
if [ -d "nodejs-api" ]; then
    cd nodejs-api
    docker build -t nodejs-api .
    minikube image load nodejs-api
    cd ..
    print_success "Node.js API image built and loaded"
else
    print_error "nodejs-api directory not found. Please run this script from the project root."
    exit 1
fi

print_status "Building Nginx image..."
if [ -d "nginx" ]; then
    cd nginx
    docker build -t sample-nginx .
    minikube image load sample-nginx
    cd ..
    print_success "Nginx image built and loaded"
else
    print_error "nginx directory not found. Please run this script from the project root."
    exit 1
fi

# Check for Datadog API key
if [ -z "$DD_API_KEY" ]; then
    print_warning "DD_API_KEY environment variable not set"
    read -p "Please enter your Datadog API key: " DD_API_KEY
    if [ -z "$DD_API_KEY" ]; then
        print_error "Datadog API key is required"
        exit 1
    fi
fi

# Create Datadog secret
print_status "Creating Datadog secret..."
kubectl delete secret datadog-secret --ignore-not-found=true
kubectl create secret generic datadog-secret --from-literal api-key="$DD_API_KEY"
print_success "Datadog secret created"

# Add Datadog Helm repository
print_status "Adding Datadog Helm repository..."
helm repo add datadog https://helm.datadoghq.com 2>/dev/null || true
helm repo update
print_success "Helm repository updated"

# Deploy Datadog Agent
print_status "Deploying Datadog Agent..."
if helm status datadog-agent &>/dev/null; then
    print_status "Datadog Agent already installed, upgrading..."
    helm upgrade datadog-agent -f datadog-values.yaml datadog/datadog
else
    helm install datadog-agent -f datadog-values.yaml datadog/datadog
fi
print_success "Datadog Agent deployed"

# Wait for Datadog Agent to be ready
print_status "Waiting for Datadog Agent to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment -l app.kubernetes.io/name=datadog-agent
print_success "Datadog Agent is ready"

# Deploy ConfigMap first
print_status "Deploying Nginx ConfigMap..."
kubectl apply -f nginx-cm0-configmap.yaml
print_success "Nginx ConfigMap deployed"

# Deploy applications
print_status "Deploying Golang API..."
kubectl apply -f golang-api-deployment.yaml
kubectl apply -f golang-api-service.yaml
print_success "Golang API deployed"

print_status "Deploying Node.js API..."
kubectl apply -f nodejs-api-deployment.yaml
kubectl apply -f nodejs-api-service.yaml
print_success "Node.js API deployed"

print_status "Deploying Nginx..."
kubectl apply -f nginx-deployment.yaml
kubectl apply -f nginx-service.yaml
print_success "Nginx deployed"

# Wait for applications to be ready
print_status "Waiting for applications to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment golang-api
if [ $? -ne 0 ]; then
    print_error "Golang API deployment failed to become ready within 5 minutes"
    print_status "Checking golang-api pod status..."
    kubectl describe pod -l app=golang-api
    exit 1
fi

kubectl wait --for=condition=available --timeout=300s deployment nodejs-api
if [ $? -ne 0 ]; then
    print_error "Node.js API deployment failed to become ready within 5 minutes"
    print_status "Checking nodejs-api pod status and logs..."
    kubectl describe pod -l app=nodejs-api
    kubectl logs -l app=nodejs-api --tail=50
    exit 1
fi

kubectl wait --for=condition=available --timeout=300s deployment nginx
if [ $? -ne 0 ]; then
    print_error "Nginx deployment failed to become ready within 5 minutes"
    print_status "Checking nginx pod status..."
    kubectl describe pod -l app=sample-nginx
    exit 1
fi
print_success "All applications are ready"

# Get service information
print_status "Getting service information..."

# Use port-forward as the most reliable method
print_status "Setting up port forwarding for testing..."
kubectl port-forward service/nginx 8080:80 &
PORT_FORWARD_PID=$!

# Give port-forward time to start
sleep 3

echo ""
echo "🎉 DEPLOYMENT SUCCESSFUL"
echo "========================"
echo ""
print_success "All components are deployed and running!"
echo ""
print_status "🔍 Service Status:"
kubectl get pods -o wide
echo ""
print_status "🌐 Access Options:"
echo "  • Port forward (recommended): http://localhost:8080"
echo "  • Alternative: minikube service nginx --url (may hang on some systems)"
echo ""
print_status "🧪 Testing Commands:"
echo "  • Test Golang API health: curl http://localhost:8080/golang-api/health"
echo "  • Test Node.js API health: curl http://localhost:8080/nodejs-api/health"
echo "  • Test Golang API: curl http://localhost:8080/golang-api/"
echo "  • Test Node.js API: curl http://localhost:8080/nodejs-api/"
echo "  • Test backward compatibility: curl http://localhost:8080/"
echo "  • Generate test traffic:"
echo "    for i in {1..5}; do curl http://localhost:8080/golang-api/; sleep 1; done"
echo "    for i in {1..5}; do curl http://localhost:8080/nodejs-api/; sleep 1; done"
echo ""
print_status "📊 Verification:"
echo "  1. Run verification script: ./verify-setup.sh"
echo "  2. Check Datadog APM UI for 'golang-api' and 'nodejs-api' services in 'dev' environment"
echo "  3. Look for traces with random success/error responses from both APIs"
echo "  4. Compare performance metrics between Go and Node.js implementations"
echo ""
print_status "🔧 Useful Commands:"
echo "  • View all pods: kubectl get pods"
echo "  • View Golang API logs: kubectl logs -l app=golang-api -f"
echo "  • View Node.js API logs: kubectl logs -l app=nodejs-api -f"
echo "  • View nginx logs: kubectl logs -l app=sample-nginx -f"
echo "  • View Datadog agent status: kubectl exec -it \$(kubectl get pods -l app.kubernetes.io/component=agent -o jsonpath='{.items[0].metadata.name}') -c agent -- agent status"
echo "  • Stop port forward: kill $PORT_FORWARD_PID"