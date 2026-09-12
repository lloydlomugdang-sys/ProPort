import { describe, expect, it } from 'vitest';
import type { BrevoConfig } from '../../src/config/env.types.js';
import {
  BrevoEmailSender,
  type BrevoProviderMessage,
  type BrevoTransport,
} from '../../src/infrastructure/email/brevo-email-sender.js';
import { EmailDeliveryError } from '../../src/infrastructure/email/email-sender.js';

const BREVO_CONFIG: BrevoConfig = {
  apiKey: 'test-only-brevo-api-key',
  fromEmail: 'no-reply@example.test',
  fromName: 'GradPort',
};

class FakeBrevoTransport implements BrevoTransport {
  readonly messages: BrevoProviderMessage[] = [];
  sendError: Error | undefined;
  verifyError: Error | undefined;

  async send(message: BrevoProviderMessage): Promise<{ readonly messageId: string }> {
    this.messages.push(message);
    if (this.sendError !== undefined) throw this.sendError;
    return { messageId: 'brevo-test-message' };
  }

  async verify(): Promise<void> {
    if (this.verifyError !== undefined) throw this.verifyError;
  }
}

describe('BrevoEmailSender', () => {
  it('sends the existing OTP message as text and HTML through a fake transport', async () => {
    const transport = new FakeBrevoTransport();
    const sender = new BrevoEmailSender(BREVO_CONFIG, transport);

    await expect(
      sender.send({
        to: 'student@gmail.com',
        template: 'emailVerification',
        subject: 'Verify your GradPort email',
        text: 'Your verification code is 123456. It expires in 10 minutes.',
        html: '<p>Your verification code is <strong>123456</strong>.</p>',
      }),
    ).resolves.toEqual({ messageId: 'brevo-test-message' });

    expect(transport.messages).toEqual([
      {
        sender: { email: BREVO_CONFIG.fromEmail, name: BREVO_CONFIG.fromName },
        to: [{ email: 'student@gmail.com' }],
        subject: 'Verify your GradPort email',
        textContent: expect.stringContaining('123456'),
        htmlContent: expect.stringContaining('123456'),
      },
    ]);
    expect(JSON.stringify(transport.messages)).not.toContain(BREVO_CONFIG.apiKey);
  });

  it('maps provider failures to the existing sanitized delivery error', async () => {
    const providerDetail = 'private provider response and credential detail';
    const transport = new FakeBrevoTransport();
    transport.sendError = new Error(providerDetail);
    const sender = new BrevoEmailSender(BREVO_CONFIG, transport);

    let thrown: unknown;
    try {
      await sender.send({
        to: 'student@gmail.com',
        template: 'passwordReset',
        subject: 'Reset your GradPort password',
        text: 'Reset code: 654321. It expires in 10 minutes.',
      });
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeInstanceOf(EmailDeliveryError);
    expect(String(thrown)).not.toContain(providerDetail);
    expect(String(thrown)).not.toContain(BREVO_CONFIG.apiKey);
  });

  it('checks readiness without sending a message or exposing provider errors', async () => {
    const transport = new FakeBrevoTransport();
    const sender = new BrevoEmailSender(BREVO_CONFIG, transport);
    await expect(sender.healthCheck()).resolves.toEqual({
      status: 'up',
      detail: 'Brevo email delivery is available.',
    });
    expect(transport.messages).toHaveLength(0);

    transport.verifyError = new Error('private provider failure');
    await expect(sender.healthCheck()).resolves.toEqual({
      status: 'down',
      detail: 'Brevo email delivery is unavailable.',
    });
  });
});
