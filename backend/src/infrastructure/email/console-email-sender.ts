import { randomUUID } from 'node:crypto';
import type { FastifyBaseLogger } from 'fastify';
import type { ServiceHealth } from '../../common/types/service-health.js';
import type { EmailMessage, EmailSender, EmailSendResult } from './email-sender.js';

export class ConsoleEmailSender implements EmailSender {
  constructor(
    private readonly logger: FastifyBaseLogger,
    private readonly previewContents = false,
  ) {}

  async send(message: EmailMessage): Promise<EmailSendResult> {
    const messageId = `local-${randomUUID()}`;
    this.logger.info(
      { messageId, recipient: message.to, template: message.template },
      'Local email accepted; no message was delivered',
    );
    if (this.previewContents) {
      this.logger.warn(
        {
          messageId,
          recipient: message.to,
          subject: message.subject,
          developmentEmailPreview: message.text ?? message.html ?? '',
        },
        'Development-only console email preview',
      );
    }
    return { messageId };
  }

  async healthCheck(): Promise<ServiceHealth> {
    return { status: 'console', detail: 'Email delivery is disabled; console adapter is active.' };
  }
}
