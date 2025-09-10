#!/bin/bash

# Set Datadog environment variables
export DD_SERVICE=nodejs-api
export DD_ENV=dev
export DD_VERSION=0.1.0
export DD_AGENT_HOST=localhost
export DD_TRACE_AGENT_URL=http://localhost:8126
export DD_LOGS_INJECTION=true
export DD_RUNTIME_METRICS_ENABLED=true
export DD_TRACE_STARTUP_LOGS=true
export DD_TRACE_ENABLED=true
export DD_PROFILING_ENABLED=true

echo "Starting Node.js API with automatic Datadog instrumentation..."
echo "Environment variables set:"
echo "DD_SERVICE=$DD_SERVICE"
echo "DD_ENV=$DD_ENV"
echo "DD_VERSION=$DD_VERSION"
echo "DD_LOGS_INJECTION=$DD_LOGS_INJECTION"
echo "DD_TRACE_STARTUP_LOGS=$DD_TRACE_STARTUP_LOGS"
echo ""

cd nodejs-api
node --import dd-trace/register.js server.js
