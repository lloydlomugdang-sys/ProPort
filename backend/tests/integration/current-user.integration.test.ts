import type { FastifyInstance, LightMyRequestResponse } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config/env.js';
import { COLLECTION_NAMES } from '../../src/database/collection-names.js';
import { runMigrations } from '../../src/database/migrations/migration-runner.js';
import type { AppServices } from '../../src/infrastructure/create-services.js';
import type {
  EmailMessage,
  EmailSendResult,
  EmailSender,
} from '../../src/infrastructure/email/email-sender.js';
import { createTestServices } from '../helpers/build-test-app.js';
import {
  createDisposableMongoDatabase,
  type DisposableMongoDatabase,
} from '../helpers/disposable-mongodb.js';

interface ErrorEnvelope {
  readonly error: {
    readonly code: string;
    readonly message: string;
    readonly requestId: string;
    readonly fields?: Readonly<Record<string, readonly string[]>>;
  };
}

interface SessionCredentials {
  readonly userId: string;
  readonly accessToken: string;
  readonly refreshToken: string;
}

interface CurrentUserEnvelope {
  readonly data: {
    readonly user: {
      readonly id: string;
      readonly email: string;
      readonly firstName: string;
      readonly lastName: string;
      readonly program: string;
      readonly yearLevel: string;
      readonly school: string;
      readonly status: string;
      readonly emailVerifiedAt: string | null;
    };
  };
  readonly meta: { readonly requestId: string };
}

class CapturingEmailSender implements EmailSender {
  readonly messages: EmailMessage[] = [];

  async send(message: EmailMessage): Promise<EmailSendResult> {
    this.messages.push(message);
    return { messageId: `test-${this.messages.length}` };
  }

  async healthCheck() {
    return { status: 'console' as const };
  }

  latestCode(): string {
    const code = this.messages.at(-1)?.text?.match(/\b\d{6}\b/)?.[0];
    if (code === undefined) {
      throw new Error('The test email did not contain a six-digit code.');
    }
    return code;
  }
}

function bearer(accessToken: string): { readonly authorization: string } {
  return { authorization: `Bearer ${accessToken}` };
}

function expectError(
  response: LightMyRequestResponse,
  statusCode: number,
  code: string,
): ErrorEnvelope {
  expect(response.statusCode).toBe(statusCode);
  const body = response.json<ErrorEnvelope>();
  expect(body.error).toMatchObject({ code, requestId: response.headers['x-request-id'] });
  return body;
}

async function registerVerifiedUser(
  app: FastifyInstance,
  email: string,
  firstName: string,
): Promise<SessionCredentials> {
  const password = 'ProfilePassword8';
  const registration = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: { firstName, lastName: 'Student', email, password },
  });
  expect(registration.statusCode).toBe(201);

  const verification = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/email-verification/verify',
    payload: { email, code: emailSender.latestCode() },
  });
  expect(verification.statusCode).toBe(200);

  const login = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/login',
    payload: { email, password },
  });
  expect(login.statusCode).toBe(200);
  const session = login.json<{
    readonly data: {
      readonly user: { readonly id: string };
      readonly tokens: { readonly accessToken: string; readonly refreshToken: string };
    };
  }>();
  return {
    userId: session.data.user.id,
    accessToken: session.data.tokens.accessToken,
    refreshToken: session.data.tokens.refreshToken,
  };
}

let app: FastifyInstance | undefined;
let disposable: DisposableMongoDatabase | undefined;
let firstUser: SessionCredentials | undefined;
let secondUser: SessionCredentials | undefined;
const emailSender = new CapturingEmailSender();

describe('authenticated current-user API with disposable MongoDB', () => {
  beforeAll(async () => {
    disposable = await createDisposableMongoDatabase();
    await runMigrations(disposable.connection.db!);
    const baseServices = createTestServices();
    const services: AppServices = {
      ...baseServices,
      database: disposable.database,
      email: emailSender,
    };
    app = await buildApp({
      config: loadConfig({ NODE_ENV: 'test', LOG_LEVEL: 'silent' }),
      services,
      connectDatabase: false,
    });
    firstUser = await registerVerifiedUser(app, 'profile.one@example.edu', 'Profile');
    secondUser = await registerVerifiedUser(app, 'profile.two@example.edu', 'Second');
  }, 120_000);

  afterAll(async () => {
    if (disposable !== undefined) {
      await disposable.stop();
    }
    if (app !== undefined) {
      await app.close();
    }
  }, 120_000);

  it('rejects unauthenticated GET and PATCH requests with the standard envelope', async () => {
    const getResponse = await app!.inject({ method: 'GET', url: '/api/v1/users/me' });
    expectError(getResponse, 401, 'UNAUTHORIZED');

    const patchResponse = await app!.inject({
      method: 'PATCH',
      url: '/api/v1/users/me',
      payload: { program: 'Not authorized' },
    });
    expectError(patchResponse, 401, 'UNAUTHORIZED');
  });

  it('returns only the authenticated user safe profile projection', async () => {
    const response = await app!.inject({
      method: 'GET',
      url: '/api/v1/users/me',
      headers: bearer(firstUser!.accessToken),
    });
    expect(response.statusCode).toBe(200);
    const body = response.json<CurrentUserEnvelope>();
    expect(body.data.user).toMatchObject({
      id: firstUser!.userId,
      email: 'profile.one@example.edu',
      firstName: 'Profile',
      lastName: 'Student',
      program: '',
      yearLevel: '',
      school: '',
      status: 'active',
    });
    expect(body.meta.requestId).toBe(response.headers['x-request-id']);

    const serialized = JSON.stringify(body);
    for (const forbidden of [
      'passwordHash',
      'refreshTokenHash',
      'codeHash',
      'avatarObjectKey',
      'avatarMimeType',
      'lastLoginAt',
      'createdAt',
      'updatedAt',
      'session',
    ]) {
      expect(serialized).not.toContain(forbidden);
    }
  });

  it('normalizes and persists allowed profile edits', async () => {
    const response = await app!.inject({
      method: 'PATCH',
      url: '/api/v1/users/me',
      headers: bearer(firstUser!.accessToken),
      payload: {
        firstName: '  Updated  ',
        lastName: '  Learner  ',
        program: '  Bachelor of Science in Information Technology  ',
        yearLevel: '  3rd Year  ',
        school: '  New Era University  ',
      },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json<CurrentUserEnvelope>().data.user).toMatchObject({
      id: firstUser!.userId,
      email: 'profile.one@example.edu',
      firstName: 'Updated',
      lastName: 'Learner',
      program: 'Bachelor of Science in Information Technology',
      yearLevel: '3rd Year',
      school: 'New Era University',
    });

    const persisted = await disposable!.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.users)
      .findOne({ email: 'profile.one@example.edu' });
    expect(persisted).toMatchObject({
      firstName: 'Updated',
      lastName: 'Learner',
      program: 'Bachelor of Science in Information Technology',
      yearLevel: '3rd Year',
      school: 'New Era University',
    });
  });

  it('rejects invalid and unsupported profile fields without changing ownership', async () => {
    const whitespaceName = await app!.inject({
      method: 'PATCH',
      url: '/api/v1/users/me',
      headers: bearer(firstUser!.accessToken),
      payload: { firstName: '   ' },
    });
    const nameError = expectError(whitespaceName, 400, 'VALIDATION_ERROR');
    expect(nameError.error.fields?.firstName).toBeDefined();

    for (const payload of [
      {},
      { email: 'changed@example.edu' },
      { userId: secondUser!.userId, program: 'Ownership violation' },
      { status: 'disabled' },
      { avatarObjectKey: 'users/other/avatar.png' },
    ]) {
      const response = await app!.inject({
        method: 'PATCH',
        url: '/api/v1/users/me',
        headers: bearer(firstUser!.accessToken),
        payload,
      });
      expectError(response, 400, 'VALIDATION_ERROR');
    }

    const clientSelectedOwner = await app!.inject({
      method: 'GET',
      url: `/api/v1/users/me?userId=${secondUser!.userId}`,
      headers: bearer(firstUser!.accessToken),
    });
    expectError(clientSelectedOwner, 400, 'VALIDATION_ERROR');

    const secondProfile = await app!.inject({
      method: 'GET',
      url: '/api/v1/users/me',
      headers: bearer(secondUser!.accessToken),
    });
    expect(secondProfile.statusCode).toBe(200);
    expect(secondProfile.json<CurrentUserEnvelope>().data.user).toMatchObject({
      id: secondUser!.userId,
      email: 'profile.two@example.edu',
      firstName: 'Second',
      program: '',
    });
  });

  it('rejects an otherwise valid access token after its session is revoked', async () => {
    const logout = await app!.inject({
      method: 'POST',
      url: '/api/v1/auth/logout',
      payload: { refreshToken: firstUser!.refreshToken },
    });
    expect(logout.statusCode).toBe(200);

    const response = await app!.inject({
      method: 'GET',
      url: '/api/v1/users/me',
      headers: bearer(firstUser!.accessToken),
    });
    expectError(response, 401, 'UNAUTHORIZED');
  });
});
