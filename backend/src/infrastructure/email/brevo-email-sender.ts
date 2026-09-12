import type { ServiceHealth } from '../../common/types/service-health.js';
import type { BrevoConfig } from '../../config/env.types.js';
import {
  EmailDeliveryError,
  type EmailMessage,
  type EmailSender,
  type EmailSendResult,
} from './email-sender.js';

const BREVO_API_URL = 'https://api.brevo.com/v3';

export interface BrevoProviderMessage {
  readonly sender: { readonly email: string; readonly name: string };
  readonly to: readonly { readonly email: string }[];
  readonly subject: string;
  readonly textContent?: string;
  readonly htmlContent?: string;
}

export interface BrevoTransport {
  send(message: BrevoProviderMessage): Promise<{ readonly messageId: string }>;
  verify(): Promise<void>;
}

function createBrevoTransport(config: BrevoConfig): BrevoTransport {
  async function request(path: string, init: RequestInit): Promise<Response> {
    return fetch(`${BREVO_API_URL}${path}`, {
      ...init,
      headers: {
        accept: 'application/json',
        'api-key': config.apiKey,
        ...(init.body === undefined ? {} : { 'content-type': 'application/json' }),
      },
      signal: AbortSignal.timeout(5_000),
    });
  }

  return {
    async send(message) {
      const response = await request('/smtp/email', {
        method: 'POST',
        body: JSON.stringify(message),
      });
      if (!response.ok) throw new Error('Email provider rejected the request.');
      const result = (await response.json()) as { readonly messageId?: unknown };
      if (typeof result.messageId !== 'string' || result.messageId.length === 0) {
        throw new Error('Email provider returned an invalid response.');
      }
      return { messageId: result.messageId };
    },
    async verify() {
      const response = await request('/account', { method: 'GET' });
      if (!response.ok) throw new Error('Email provider is unavailable.');
    },
  };
}

export class BrevoEmailSender implements EmailSender {
  private readonly transport: BrevoTransport;

  constructor(
    private readonly config: BrevoConfig,
    transport?: BrevoTransport,
  ) {
    this.transport = transport ?? createBrevoTransport(config);
  }

  async send(message: EmailMessage): Promise<EmailSendResult> {
    try {
      const result = await this.transport.send({
        sender: { email: this.config.fromEmail, name: this.config.fromName },
        to: [{ email: message.to }],
        subject: message.subject,
        ...(message.text === undefined ? {} : { textContent: message.text }),
        ...(message.html === undefined ? {} : { htmlContent: message.html }),
      });
      if (result.messageId.length === 0) throw new EmailDeliveryError();
      return result;
    } catch {
      throw new EmailDeliveryError();
    }
  }

  async healthCheck(): Promise<ServiceHealth> {
    try {
      await this.transport.verify();
      return { status: 'up', detail: 'Brevo email delivery is available.' };
    } catch {
      return { status: 'down', detail: 'Brevo email delivery is unavailable.' };
    }
  }
}
