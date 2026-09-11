import { describe, expect, it } from 'vitest';
import { createLoggerOptions } from '../../src/common/logging/logger-options.js';

describe('logger redaction', () => {
  it('covers credentials, uploaded contents, and extracted text', () => {
    const options = createLoggerOptions('info') as {
      readonly redact: { readonly paths: readonly string[]; readonly censor: string };
    };

    expect(options.redact.censor).toBe('[REDACTED]');
    expect(options.redact.paths).toEqual(
      expect.arrayContaining([
        'req.headers.authorization',
        'request.headers.authorization',
        '*.authorization',
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
        'config.smtp.pass',
        'config.smtp.user',
      ]),
    );
  });
});
