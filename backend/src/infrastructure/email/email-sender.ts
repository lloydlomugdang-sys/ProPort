import type { ServiceHealth } from '../../common/types/service-health.js';

export interface EmailMessage {
  readonly to: string;
  readonly template: string;
  readonly subject: string;
  readonly text?: string;
  readonly html?: string;
}

export interface EmailSendResult {
  readonly messageId: string;
}

export interface EmailSender {
  send(message: EmailMessage): Promise<EmailSendResult>;
  healthCheck(): Promise<ServiceHealth>;
}
