import type { FastifyBaseLogger } from 'fastify';
import { describe, expect, it } from 'vitest';
import { loadConfig } from '../../src/config/env.js';
import { createServices } from '../../src/infrastructure/create-services.js';
import { ConsoleEmailSender } from '../../src/infrastructure/email/console-email-sender.js';
import { SmtpEmailSender } from '../../src/infrastructure/email/smtp-email-sender.js';

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
});
