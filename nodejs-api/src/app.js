// This line must come before importing any instrumented module.
import tracer from 'dd-trace';

// Initialize tracer with logInjection for automatic trace correlation
tracer.init({ logInjection: true });

import express from 'express';
import logger from './logger.js';

const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(express.json());

// Middleware to log Datadog headers when present
app.use((req, res, next) => {
  const datadogHeaders = {};
  if (req.headers['x-datadog-trace-id']) {
    datadogHeaders['X-Datadog-Trace-Id'] = req.headers['x-datadog-trace-id'];
  }
  if (req.headers['x-datadog-parent-id']) {
    datadogHeaders['X-Datadog-Parent-Id'] = req.headers['x-datadog-parent-id'];
  }
  
  if (Object.keys(datadogHeaders).length > 0) {
    logger.info('Incoming Datadog headers', datadogHeaders);
  }
  
  next();
});


// Error scenarios for realistic simulation (matching Go API)
const errorScenarios = [
  { statusCode: 400, errorCode: 'INVALID_REQUEST', message: 'Invalid request format', reason: 'Missing required parameter \'user_id\'' },
  { statusCode: 400, errorCode: 'VALIDATION_ERROR', message: 'Request validation failed', reason: 'Email format is invalid' },
  { statusCode: 400, errorCode: 'MISSING_AUTH', message: 'Authentication required', reason: 'Authorization header is missing or malformed' },
  { statusCode: 500, errorCode: 'DATABASE_ERROR', message: 'Internal database error', reason: 'Connection to user database failed' },
  { statusCode: 500, errorCode: 'SERVICE_UNAVAILABLE', message: 'External service error', reason: 'Payment service is temporarily unavailable' },
  { statusCode: 500, errorCode: 'TIMEOUT_ERROR', message: 'Request timeout', reason: 'Upstream service did not respond within 30 seconds' }
];

// Random status handler (matching Go API behavior)
app.get('/', (req, res) => {
  const timestamp = new Date().toISOString();

  // Set content type for JSON responses
  res.setHeader('Content-Type', 'application/json');

  // Simulate different outcomes: 50% success, 30% client error, 20% server error
  const outcome = Math.random();

  if (outcome < 0.5) {
    // Success case
    const response = {
      status: 'success',
      message: 'Request processed successfully',
      timestamp: timestamp
    };
    
    logger.info('Request processed successfully');
    res.status(200).json(response);
    
  } else if (outcome < 0.8) {
    // Client error (400)
    const scenario = errorScenarios[Math.floor(Math.random() * 3)]; // First 3 are 400 errors
    
    const response = {
      error: scenario.errorCode,
      message: scenario.message,
      code: scenario.reason,
      timestamp: timestamp
    };
    
    logger.error('Client error occurred');
    res.status(scenario.statusCode).json(response);
    
  } else {
    // Server error (500)
    const scenario = errorScenarios[3 + Math.floor(Math.random() * 3)]; // Last 3 are 500 errors
    
    const response = {
      error: scenario.errorCode,
      message: scenario.message,
      code: scenario.reason,
      timestamp: timestamp
    };
    
    logger.error('Server error occurred');
    res.status(scenario.statusCode).json(response);
  }
});

// Health check handler
app.get('/health', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  
  const response = {
    status: 'healthy',
    message: 'Service is healthy',
    timestamp: new Date().toISOString()
  };
  
  res.status(200).json(response);
});

// Error handling middleware
app.use((err, req, res, next) => {
  logger.error({ err }, 'Unhandled error occurred');
  
  res.status(500).json({
    error: 'INTERNAL_ERROR',
    message: 'An internal error occurred',
    timestamp: new Date().toISOString()
  });
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully');
  process.exit(0);
});

process.on('SIGINT', () => {
  logger.info('SIGINT received, shutting down gracefully');
  process.exit(0);
});

export default app;
