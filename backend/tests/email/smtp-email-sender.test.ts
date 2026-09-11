import type { SendMailOptions } from 'nodemailer';
import { describe, expect, it } from 'vitest';
import type { SmtpConfig } from '../../src/config/env.types.js';
import { EmailDeliveryError } from '../../src/infrastructure/email/email-sender.js';
import {
  SmtpEmailSender,
  type SmtpMailTransport,
} from '../../src/infrastructure/email/smtp-email-sender.js';

const SMTP_CONFIG: SmtpConfig = {
  host: 'smtp.example.test',
  port: 587,
  secure: false,
  user: 'transport-user@example.test',
  pass: 'test-only-transport-password',
  from: 'GradPort <no-reply@example.test>',
};

class FakeSmtpTransport implements SmtpMailTransport {
  readonly messages: SendMailOptions[] = [];
  sendError?: Error;
  verifyError?: Error;

  async sendMail(message: SendMailOptions): Promise<{
    readonly messageId: string;
    readonly accepted?: readonly unknown[];
    readonly rejected?: readonly unknown[];
  }> {
    this.messages.push(message);
    if (this.sendError !== undefined) {
      throw this.sendError;
    }
    return {
      messageId: 'smtp-test-message',
      accepted: [String(message.to)],
      rejected: [],
    };
  }

  async verify(): Promise<true> {
    if (this.verifyError !== undefined) {
      throw this.verifyError;
    }
    return true;
  }
}

describe('SmtpEmailSender', () => {
  it('sends the existing message shape through an injected transport', async () => {
    const transport = new FakeSmtpTransport();
    const sender = new SmtpEmailSender(SMTP_CONFIG, transport);

    await expect(
      sender.send({
        to: 'student@gmail.com',
        template: 'emailVerification',
        subject: 'Verify your GradPort email',
        text: 'Your verification code is 123456. It expires in 10 minutes.',
        html: '<p>Your verification code is <strong>123456</strong>.</p>',
      }),
    ).resolves.toEqual({ messageId: 'smtp-test-message' });

    expect(transport.messages).toHaveLength(1);
    expect(transport.messages[0]).toMatchObject({
      from: SMTP_CONFIG.from,
      to: 'student@gmail.com',
      subject: 'Verify your GradPort email',
      text: expect.stringContaining('123456'),
      html: expect.stringContaining('123456'),
      disableFileAccess: true,
      disableUrlAccess: true,
    });
    const serialized = JSON.stringify(transport.messages[0]);
    expect(serialized).not.toContain(SMTP_CONFIG.user);
    expect(serialized).not.toContain(SMTP_CONFIG.pass);
  });

  it('converts provider failures and rejected delivery into sanitized errors', async () => {
    const providerDetail = '535 authentication failed for a private credential';
    const transport = new FakeSmtpTransport();
    transport.sendError = new Error(providerDetail);
    const sender = new SmtpEmailSender(SMTP_CONFIG, transport);

    let thrown: unknown;
    try {
      await sender.send({
        to: 'student@gmail.com',
        template: 'passwordReset',
        subject: 'Reset your GradPort password',
        text: 'Reset code: 654321',
      });
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeInstanceOf(EmailDeliveryError);
    expect(String(thrown)).not.toContain(providerDetail);
    expect(String(thrown)).not.toContain(SMTP_CONFIG.user);
    expect(String(thrown)).not.toContain(SMTP_CONFIG.pass);

    const rejectedTransport = new FakeSmtpTransport();
    rejectedTransport.sendMail = async (message) => {
      rejectedTransport.messages.push(message);
      return { messageId: 'rejected-message', accepted: [], rejected: [String(message.to)] };
    };
    await expect(
      new SmtpEmailSender(SMTP_CONFIG, rejectedTransport).send({
        to: 'student@gmail.com',
        template: 'passwordReset',
        subject: 'Reset your GradPort password',
        text: 'Reset code: 654321',
      }),
    ).rejects.toBeInstanceOf(EmailDeliveryError);
  });

  it('reports SMTP readiness without exposing provider details', async () => {
    const transport = new FakeSmtpTransport();
    const sender = new SmtpEmailSender(SMTP_CONFIG, transport);
    await expect(sender.healthCheck()).resolves.toEqual({
      status: 'up',
      detail: 'SMTP email delivery is available.',
    });

    const providerDetail = 'private SMTP hostname and credential failure';
    transport.verifyError = new Error(providerDetail);
    const health = await sender.healthCheck();
    expect(health).toEqual({
      status: 'down',
      detail: 'SMTP email delivery is unavailable.',
    });
    expect(JSON.stringify(health)).not.toContain(providerDetail);
    expect(JSON.stringify(health)).not.toContain(SMTP_CONFIG.user);
    expect(JSON.stringify(health)).not.toContain(SMTP_CONFIG.pass);
  });
});
