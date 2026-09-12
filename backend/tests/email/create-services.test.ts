import type { FastifyBaseLogger } from 'fastify';
import { describe, expect, it } from 'vitest';
import { loadConfig } from '../../src/config/env.js';
import { createServices } from '../../src/infrastructure/create-services.js';
import { BrevoEmailSender } from '../../src/infrastructure/email/brevo-email-sender.js';
import { ConsoleEmailSender } from '../../src/infrastructure/email/console-email-sender.js';
import { SmtpEmailSender } from '../../src/infrastructure/email/smtp-email-sender.js';
import { R2ObjectStorage } from '../../src/infrastructure/storage/r2-object-storage.js';

const LOGGER = {
  info: () => undefined,
  warn: () => undefined,
} as unknown as FastifyBaseLogger;

describe('email service construction', () => {
  it('preserves the console adapter by default', () => {
    const services = createServices(loadConfig({ NODE_ENV: 'test' }), LOGGER);

    expect(services.email).toBeInstanceOf(ConsoleEmailSender);
  });

  it('selects the SMTP adapter only when SMTP configuration is complete', () => {
    const config = loadConfig({
      NODE_ENV: 'test',
      EMAIL_DRIVER: 'smtp',
      SMTP_HOST: 'smtp.example.test',
      SMTP_PORT: '465',
      SMTP_SECURE: 'true',
      SMTP_USER: 'transport-user@example.test',
      SMTP_PASS: 'test-only-transport-password',
      EMAIL_FROM: 'GradPort <no-reply@example.test>',
    });

    expect(createServices(config, LOGGER).email).toBeInstanceOf(SmtpEmailSender);
  });

  it('selects Brevo and R2 only when their validated drivers are enabled', () => {
    const config = loadConfig({
      NODE_ENV: 'test',
      STORAGE_DRIVER: 'r2',
      R2_ENDPOINT: 'https://test-account.r2.cloudflarestorage.com',
      R2_ACCESS_KEY_ID: 'test-only-access-key',
      R2_SECRET_ACCESS_KEY: 'test-only-secret-key',
      R2_BUCKET: 'gradport-test',
      EMAIL_DRIVER: 'brevo',
      BREVO_API_KEY: 'test-only-api-key',
      BREVO_FROM_EMAIL: 'no-reply@example.test',
      BREVO_FROM_NAME: 'GradPort',
    });
    const services = createServices(config, LOGGER);

    expect(services.storage).toBeInstanceOf(R2ObjectStorage);
    expect(services.email).toBeInstanceOf(BrevoEmailSender);
  });
});
