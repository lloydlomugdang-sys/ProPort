import nodemailer, { type SendMailOptions } from 'nodemailer';
import type { ServiceHealth } from '../../common/types/service-health.js';
import type { SmtpConfig } from '../../config/env.types.js';
import {
  EmailDeliveryError,
  type EmailMessage,
  type EmailSender,
  type EmailSendResult,
} from './email-sender.js';

export interface SmtpMailTransport {
  sendMail(message: SendMailOptions): Promise<{
    readonly messageId: string;
    readonly accepted?: readonly unknown[];
    readonly rejected?: readonly unknown[];
  }>;
  verify(): Promise<true>;
}

function createSmtpMailTransport(config: SmtpConfig): SmtpMailTransport {
  const transport = nodemailer.createTransport({
    host: config.host,
    port: config.port,
    secure: config.secure,
    requireTLS: !config.secure,
    auth: { user: config.user, pass: config.pass },
    tls: { minVersion: 'TLSv1.2' },
    logger: false,
    debug: false,
  });

  return {
    sendMail: (message) => transport.sendMail(message),
    verify: () => transport.verify(),
  };
}

export class SmtpEmailSender implements EmailSender {
  private readonly transport: SmtpMailTransport;

  constructor(
    private readonly config: SmtpConfig,
    transport?: SmtpMailTransport,
  ) {
    this.transport = transport ?? createSmtpMailTransport(config);
  }

  async send(message: EmailMessage): Promise<EmailSendResult> {
    try {
      const result = await this.transport.sendMail({
        from: this.config.from,
        to: message.to,
        subject: message.subject,
        text: message.text,
        html: message.html,
        disableFileAccess: true,
        disableUrlAccess: true,
      });
      if (
        result.messageId.length === 0 ||
        result.accepted === undefined ||
        result.accepted.length === 0
      ) {
        throw new EmailDeliveryError();
      }
      return { messageId: result.messageId };
    } catch {
      throw new EmailDeliveryError();
    }
  }

  async healthCheck(): Promise<ServiceHealth> {
    try {
      await this.transport.verify();
      return { status: 'up', detail: 'SMTP email delivery is available.' };
    } catch {
      return { status: 'down', detail: 'SMTP email delivery is unavailable.' };
    }
  }
}
