import { describe, expect, it } from 'vitest';
import Fastify from 'fastify';
import { createLoggerOptions } from '../../src/common/logging/logger-options.js';

describe('logger redaction', () => {
  it('redacts Gemini credentials and authorization in serialized logs', async () => {
    const messages: string[] = [];
    const options = createLoggerOptions('info');
    if (options === false) throw new Error('Test logger must be enabled.');
    const app = Fastify({ logger: { ...options, stream: { write: (message: string) => { messages.push(message); } } } });
    app.log.info({ GEMINI_API_KEY: 'test-secret-sentinel', config: { gemini: { apiKey: 'test-secret-sentinel' } },
      credentials: { geminiApiKey: 'test-secret-sentinel', authorization: 'test-secret-sentinel' } });
    app.log.warn({ apiKey: 'test-secret-sentinel', geminiApiKey: 'test-secret-sentinel',
      currentPassword: 'current-password-sentinel', body: { currentPassword: 'current-password-sentinel' },
      authorization: 'test-secret-sentinel', accessToken: 'test-secret-sentinel', refreshToken: 'test-secret-sentinel',
      rawText: 'private-document-sentinel', reviewedText: 'private-document-sentinel', ocrText: 'private-document-sentinel',
      contents: [{ text: 'private-document-sentinel' }], candidates: [{ text: 'private-document-sentinel' }],
      payload: { ocrText: 'private-document-sentinel', candidates: [{ text: 'private-document-sentinel' }] } });
    await app.close();
    expect(messages.join('')).not.toContain('test-secret-sentinel');
    expect(messages.join('')).not.toContain('current-password-sentinel');
    expect(messages.join('')).not.toContain('private-document-sentinel');
    expect(messages.join('')).toContain('[REDACTED]');
  });

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
        '*.brevoApiKey',
        '*.BREVO_API_KEY',
        'GEMINI_API_KEY',
        '*.GEMINI_API_KEY',
        '*.geminiApiKey',
        '*.apiKey',
        'config.gemini.apiKey',
        'req.headers["x-goog-api-key"]',
        '*.r2AccessKeyId',
        '*.r2SecretAccessKey',
        '*.R2_ACCESS_KEY_ID',
        '*.R2_SECRET_ACCESS_KEY',
        '*.objectKey',
        '*.rawText',
        '*.reviewedText',
        '*.contents',
        '*.fileBytes',
        '*.auth.pass',
        '*.auth.user',
        'config.smtp.pass',
        'config.smtp.user',
        'config.brevo.apiKey',
        'config.r2.accessKeyId',
        'config.r2.secretAccessKey',
      ]),
    );
  });
});
