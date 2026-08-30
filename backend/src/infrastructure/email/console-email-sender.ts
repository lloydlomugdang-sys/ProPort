import { randomUUID } from 'node:crypto';
import type { FastifyBaseLogger } from 'fastify';
import type { ServiceHealth } from '../../common/types/service-health.js';
import type { EmailMessage, EmailSender, EmailSendResult } from './email-sender.js';

export class ConsoleEmailSender implements EmailSender {
  constructor(private readonly logger: FastifyBaseLogger) {}

  async send(message: EmailMessage): Promise<EmailSendResult> {
    const messageId = `local-${randomUUID()}`;
    this.logger.info(
      { messageId, recipient: message.to, template: message.template },
      'Local email accepted; no message was delivered',
    );
    return { messageId };
  }

  async healthCheck(): Promise<ServiceHealth> {
    return { status: 'console', detail: 'Email delivery is disabled; console adapter is active.' };
  }
}
