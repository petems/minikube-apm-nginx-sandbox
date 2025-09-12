import { createLogger, format, transports } from 'winston';

const logger = createLogger({
  level: 'info',
  format: format.json(),       // JSON required for auto-injection
  transports: [new transports.Console()]
});

export default logger;