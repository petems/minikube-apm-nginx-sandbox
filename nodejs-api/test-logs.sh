#!/bin/bash

# Set Datadog environment variables for local testing
export DD_SERVICE="nodejs-api"
export DD_ENV="dev"
export DD_VERSION="0.1.0"
export DD_LOGS_INJECTION="true"
export DD_TRACE_STARTUP_LOGS="true"

echo "Starting Node.js API with Datadog tracing..."
echo "Environment variables set:"
echo "DD_SERVICE=$DD_SERVICE"
echo "DD_ENV=$DD_ENV"
echo "DD_VERSION=$DD_VERSION"
echo "DD_LOGS_INJECTION=$DD_LOGS_INJECTION"
echo "DD_TRACE_STARTUP_LOGS=$DD_TRACE_STARTUP_LOGS"
echo ""

# Run the Node.js application
node server.js
