import type { AppConfig } from '../../config/env.types.js';

export function createLoggerOptions(logLevel: AppConfig['logLevel']): Record<string, unknown> | false {
  if (logLevel === 'silent') {
    return false;
  }

  return {
    level: logLevel,
    redact: {
      paths: [
        'req.headers.authorization',
        'req.headers.cookie',
        'request.headers.authorization',
        'request.headers.cookie',
        '*.password',
        '*.passwordHash',
        '*.token',
        '*.refreshToken',
        '*.code',
        '*.codeHash',
        '*.mongodbUri',
        '*.MONGODB_URI',
      ],
      censor: '[REDACTED]',
    },
  };
}
