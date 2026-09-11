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
        '*.authorization',
        '*.password',
        '*.passwordHash',
        '*.newPassword',
        '*.token',
        '*.accessToken',
        '*.refreshToken',
        '*.refreshTokenHash',
        '*.resetToken',
        '*.resetTokenHash',
        '*.code',
        '*.codeHash',
        '*.otp',
        '*.mongodbUri',
        '*.MONGODB_URI',
        '*.smtpPass',
        '*.smtpUser',
        '*.SMTP_PASS',
        '*.SMTP_USER',
        '*.smtpCredentials',
        '*.emailProviderCredentials',
        '*.rawText',
        '*.reviewedText',
        '*.contents',
        '*.fileBytes',
        '*.auth.pass',
        '*.auth.user',
        '*.uri',
        '*.connectionString',
        'config.mongodbUri',
        'config.smtp.pass',
        'config.smtp.user',
      ],
      censor: '[REDACTED]',
    },
  };
}
