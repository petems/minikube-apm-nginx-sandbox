// Initialize Datadog tracer with log injection enabled BEFORE importing other modules
import tracer from 'dd-trace';
tracer.init({
  logInjection: true, // Enables automatic trace ID injection
  service: process.env.DD_SERVICE || 'nodejs-api',
  env: process.env.DD_ENV || 'dev',
  version: process.env.DD_VERSION || '0.1.0'
});

import './src/logger.js'
import app from './src/app.js'

const port = process.env.PORT || 3000
app.listen(port, '0.0.0.0', () => {
  console.log(`Node.js API server started on port ${port}`)
})