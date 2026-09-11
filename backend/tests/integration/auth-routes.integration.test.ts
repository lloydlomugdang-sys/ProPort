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
import { hashOpaqueToken, verifyPassword } from '../../src/modules/auth/auth.crypto.js';
import { createTestServices } from '../helpers/build-test-app.js';
import {
  createDisposableMongoDatabase,
  type DisposableMongoDatabase,
} from '../helpers/disposable-mongodb.js';

const EMAIL = 'route.student@example.edu';
const ORIGINAL_PASSWORD = 'RoutePassword9';
const NEW_PASSWORD = 'UpdatedPassword8';

interface ErrorEnvelope {
  readonly error: {
    readonly code: string;
    readonly message: string;
    readonly requestId: string;
    readonly fields?: Readonly<Record<string, readonly string[]>>;
  };
}

interface AuthUserBody {
  readonly id: string;
  readonly email: string;
  readonly status: 'pendingVerification' | 'active' | 'disabled';
}

interface TokenBody {
  readonly accessToken: string;
  readonly refreshToken: string;
  readonly accessTokenExpiresAt: string;
  readonly refreshTokenExpiresAt: string;
  readonly tokenType: 'Bearer';
}

interface SessionEnvelope {
  readonly data: { readonly user: AuthUserBody; readonly tokens: TokenBody };
  readonly meta: { readonly requestId: string };
}

class CapturingEmailSender implements EmailSender {
  readonly messages: EmailMessage[] = [];
  failure: Error | undefined;

  async send(message: EmailMessage): Promise<EmailSendResult> {
    if (this.failure !== undefined) {
      throw this.failure;
    }
    this.messages.push(message);
    return { messageId: `captured-${this.messages.length}` };
  }

  async healthCheck() {
    return { status: 'console' as const };
  }

  latestCode(): string {
    const match = this.messages.at(-1)?.text?.match(/code is ([0-9]{6})\./);
    if (match?.[1] === undefined) {
      throw new Error('Captured email did not contain a six-digit code.');
    }
    return match[1];
  }
}

function expectError(response: LightMyRequestResponse, status: number, code: string): ErrorEnvelope {
  expect(response.statusCode).toBe(status);
  const body = response.json<ErrorEnvelope>();
  expect(body.error).toMatchObject({ code });
  expect(body.error.requestId).toBe(response.headers['x-request-id']);
  return body;
}

function requireContext(
  app: FastifyInstance | undefined,
  disposable: DisposableMongoDatabase | undefined,
  email: CapturingEmailSender | undefined,
): {
  app: FastifyInstance;
  disposable: DisposableMongoDatabase;
  email: CapturingEmailSender;
} {
  if (app === undefined || disposable === undefined || email === undefined) {
    throw new Error('Authentication route test context is unavailable.');
  }
  return { app, disposable, email };
}

describe.sequential('authentication API with disposable MongoDB', () => {
  let app: FastifyInstance | undefined;
  let disposable: DisposableMongoDatabase | undefined;
  let email: CapturingEmailSender | undefined;

  beforeAll(async () => {
    disposable = await createDisposableMongoDatabase();
    await runMigrations(disposable.connection.db!);
    email = new CapturingEmailSender();
    const baseServices = createTestServices();
    const services: AppServices = {
      ...baseServices,
      database: disposable.database,
      email,
    };
    app = await buildApp({
      config: loadConfig({
        NODE_ENV: 'test',
        LOG_LEVEL: 'silent',
        AUTH_CODE_RESEND_COOLDOWN_SECONDS: '1',
      }),
      services,
      connectDatabase: false,
    });
    await app.ready();
  });

  afterAll(async () => {
    if (disposable !== undefined) {
      await disposable.stop();
      disposable = undefined;
    }
    if (app !== undefined) {
      await app.close();
      app = undefined;
    }
  });

  it('registers, requires verification without auto-resending, and verifies an explicit resend', async () => {
    const context = requireContext(app, disposable, email);
    const invalid = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: {
        firstName: 'Route',
        lastName: 'Student',
        email: EMAIL,
        password: ORIGINAL_PASSWORD,
        confirmPassword: ORIGINAL_PASSWORD,
      },
    });
    expectError(invalid, 400, 'VALIDATION_ERROR');

    const weakPassword = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: {
        firstName: 'Route',
        lastName: 'Student',
        email: EMAIL,
        password: 'alllowercase',
      },
    });
    const weakPasswordError = expectError(weakPassword, 400, 'VALIDATION_ERROR');
    expect(weakPasswordError.error.fields?.password).toBeDefined();

    const registration = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: {
        firstName: 'Route',
        lastName: 'Student',
        email: `  ${EMAIL.toUpperCase()}  `,
        password: ORIGINAL_PASSWORD,
      },
    });
    expect(registration.statusCode).toBe(201);
    const registered = registration.json<{
      readonly data: {
        readonly user: AuthUserBody;
        readonly verification: { readonly required: true };
      };
    }>();
    expect(registered.data.user).toMatchObject({
      email: EMAIL,
      status: 'pendingVerification',
    });
    expect(registered.data.verification.required).toBe(true);
    const serializedRegistration = JSON.stringify(registered);
    expect(serializedRegistration).not.toContain(ORIGINAL_PASSWORD);
    expect(serializedRegistration).not.toMatch(/passwordHash|codeHash|refreshTokenHash/);
    expect(context.email.messages).toHaveLength(1);
    const issuedCode = context.email.latestCode();
    expect(context.email.messages[0]).toMatchObject({
      template: 'emailVerification',
      subject: 'Verify your GradPort email',
      text: expect.stringContaining(issuedCode),
      html: expect.stringContaining(issuedCode),
    });
    expect(context.email.messages[0]?.text).toContain('expires in 10 minutes');
    expect(context.email.messages[0]?.html).toContain('expires in 10 minutes');

    const firstCodeDocument = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.oneTimeCodes)
      .findOne({ type: 'emailVerification' });
    expect(firstCodeDocument).not.toBeNull();

    const beforeUnverifiedLogin = context.email.messages.length;
    const unverifiedLogin = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: EMAIL, password: ORIGINAL_PASSWORD },
    });
    expectError(unverifiedLogin, 403, 'EMAIL_NOT_VERIFIED');
    expect(context.email.messages).toHaveLength(beforeUnverifiedLogin);

    const wrongCode = issuedCode === '000000' ? '000001' : '000000';
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const invalidCode = await context.app.inject({
        method: 'POST',
        url: '/api/v1/auth/email-verification/verify',
        payload: { email: EMAIL, code: wrongCode },
      });
      expectError(invalidCode, 400, 'INVALID_OR_EXPIRED_CODE');
    }
    const exhaustedCode = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/email-verification/verify',
      payload: { email: EMAIL, code: issuedCode },
    });
    expectError(exhaustedCode, 400, 'INVALID_OR_EXPIRED_CODE');

    const cooldown = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/email-verification/resend',
      payload: { email: EMAIL },
    });
    expectError(cooldown, 429, 'RATE_LIMITED');
    expect(Number(cooldown.headers['retry-after'])).toBeGreaterThan(0);
    expect(context.email.messages).toHaveLength(beforeUnverifiedLogin);

    await context.disposable.connection.db!
      .collection(COLLECTION_NAMES.oneTimeCodes)
      .updateOne(
        { _id: firstCodeDocument!._id },
        { $set: { createdAt: new Date(Date.now() - 2_000) } },
      );
    const resend = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/email-verification/resend',
      payload: { email: EMAIL },
    });
    expect(resend.statusCode).toBe(202);
    expect(resend.json()).toMatchObject({ data: { status: 'accepted' } });
    expect(context.email.messages).toHaveLength(beforeUnverifiedLogin + 1);

    const invalidatedFirstCode = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.oneTimeCodes)
      .findOne({ _id: firstCodeDocument!._id });
    expect(invalidatedFirstCode?.consumedAt).toBeInstanceOf(Date);

    const verification = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/email-verification/verify',
      payload: { email: EMAIL, code: context.email.latestCode() },
    });
    expect(verification.statusCode).toBe(200);
    expect(verification.json()).toMatchObject({
      data: { user: { email: EMAIL, status: 'active' } },
    });

    const duplicate = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: {
        firstName: 'Other',
        lastName: 'Student',
        email: EMAIL.toUpperCase(),
        password: 'OtherPassword7',
      },
    });
    expectError(duplicate, 409, 'EMAIL_ALREADY_REGISTERED');
  });

  it('issues JWT access tokens and detects refresh-token replay across a rotation family', async () => {
    const context = requireContext(app, disposable, email);
    const login = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: EMAIL, password: ORIGINAL_PASSWORD },
    });
    expect(login.statusCode).toBe(200);
    const session = login.json<SessionEnvelope>();
    expect(session.data.tokens.tokenType).toBe('Bearer');

    const jwt = context.app.jwt.verify<{
      readonly sub: string;
      readonly sid: string;
      readonly iss: string;
      readonly aud: string;
      readonly iat: number;
      readonly exp: number;
    }>(session.data.tokens.accessToken);
    expect(jwt).toMatchObject({
      sub: session.data.user.id,
      iss: 'gradport-api',
      aud: 'gradport-mobile',
    });
    expect(jwt.exp - jwt.iat).toBe(900);
    const tokenParts = session.data.tokens.accessToken.split('.');
    const signature = tokenParts[2]!;
    const tamperedSignature = `${signature.startsWith('A') ? 'B' : 'A'}${signature.slice(1)}`;
    const tamperedToken = `${tokenParts[0]}.${tokenParts[1]}.${tamperedSignature}`;
    expect(() => context.app.jwt.verify(tamperedToken)).toThrow();

    const originalSession = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.sessions)
      .findOne({ refreshTokenHash: hashOpaqueToken(session.data.tokens.refreshToken) });
    expect(originalSession).not.toBeNull();
    expect(originalSession?.refreshTokenHash).not.toBe(session.data.tokens.refreshToken);
    expect(originalSession).not.toHaveProperty('refreshToken');
    expect(originalSession).not.toHaveProperty('accessToken');

    const refresh = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: session.data.tokens.refreshToken },
    });
    expect(refresh.statusCode).toBe(200);
    const rotated = refresh.json<SessionEnvelope>();
    expect(rotated.data.tokens.refreshToken).not.toBe(session.data.tokens.refreshToken);

    const replay = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: session.data.tokens.refreshToken },
    });
    expectError(replay, 401, 'INVALID_REFRESH_TOKEN');

    const replayedFamily = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.sessions)
      .find({ familyId: originalSession!.familyId })
      .toArray();
    expect(replayedFamily).toHaveLength(2);
    expect(replayedFamily.every((stored) => stored.revokedAt instanceof Date)).toBe(true);

    const revokedReplacement = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: rotated.data.tokens.refreshToken },
    });
    expectError(revokedReplacement, 401, 'INVALID_REFRESH_TOKEN');
  });

  it('revokes logout tokens idempotently', async () => {
    const context = requireContext(app, disposable, email);
    const login = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: EMAIL, password: ORIGINAL_PASSWORD },
    });
    const session = login.json<SessionEnvelope>();

    for (let attempt = 0; attempt < 2; attempt += 1) {
      const logout = await context.app.inject({
        method: 'POST',
        url: '/api/v1/auth/logout',
        payload: { refreshToken: session.data.tokens.refreshToken },
      });
      expect(logout.statusCode).toBe(200);
      expect(logout.json()).toMatchObject({ data: { status: 'loggedOut' } });
    }

    const rawSession = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.sessions)
      .findOne({ refreshTokenHash: hashOpaqueToken(session.data.tokens.refreshToken) });
    expect(rawSession).toMatchObject({ revokeReason: 'logout' });
    expect(rawSession?.revokedAt).toBeInstanceOf(Date);

    const refresh = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: session.data.tokens.refreshToken },
    });
    expectError(refresh, 401, 'INVALID_REFRESH_TOKEN');
  });

  it('keeps reset requests enumeration-safe and consumes reset grants once', async () => {
    const context = requireContext(app, disposable, email);
    const beforeUnknown = context.email.messages.length;
    const unknown = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/password-reset/request',
      payload: { email: 'missing.student@example.edu' },
    });
    expect(unknown.statusCode).toBe(202);
    expect(unknown.json()).toMatchObject({ data: { status: 'accepted' } });
    expect(context.email.messages).toHaveLength(beforeUnknown);

    const existing = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/password-reset/request',
      payload: { email: EMAIL },
    });
    expect(existing.statusCode).toBe(202);
    expect(existing.json()).toMatchObject({ data: { status: 'accepted' } });
    expect(context.email.messages).toHaveLength(beforeUnknown + 1);
    const resetCode = context.email.latestCode();
    expect(context.email.messages.at(-1)).toMatchObject({
      template: 'passwordReset',
      subject: 'Reset your GradPort password',
      text: expect.stringContaining(resetCode),
      html: expect.stringContaining(resetCode),
    });

    const verifyReset = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/password-reset/verify',
      payload: { email: EMAIL, code: resetCode },
    });
    expect(verifyReset.statusCode).toBe(200);
    const reset = verifyReset.json<{
      readonly data: { readonly resetToken: string; readonly resetTokenExpiresAt: string };
    }>();
    expect(reset.data.resetToken).toMatch(/^[A-Za-z0-9_-]{43,128}$/);

    const rawGrant = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.oneTimeCodes)
      .findOne({ type: 'passwordResetGrant' });
    expect(rawGrant?.codeHash).toBe(hashOpaqueToken(reset.data.resetToken));
    expect(rawGrant?.codeHash).not.toBe(reset.data.resetToken);
    expect(rawGrant).not.toHaveProperty('resetToken');

    const sessionBeforeReset = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: EMAIL, password: ORIGINAL_PASSWORD },
    });
    expect(sessionBeforeReset.statusCode).toBe(200);
    const activeBeforeReset = await context.disposable.connection.db!
      .collection(COLLECTION_NAMES.sessions)
      .countDocuments({ revokedAt: { $exists: false } });
    expect(activeBeforeReset).toBeGreaterThan(0);

    const weakReset = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/password-reset/complete',
      payload: { resetToken: reset.data.resetToken, newPassword: 'alllowercase' },
    });
    const weakResetError = expectError(weakReset, 400, 'VALIDATION_ERROR');
    expect(weakResetError.error.fields?.password).toBeDefined();

    const completed = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/password-reset/complete',
      payload: { resetToken: reset.data.resetToken, newPassword: NEW_PASSWORD },
    });
    expect(completed.statusCode).toBe(200);
    expect(completed.json()).toMatchObject({ data: { status: 'passwordReset' } });
    const activeAfterReset = await context.disposable.connection.db!
      .collection(COLLECTION_NAMES.sessions)
      .countDocuments({ revokedAt: { $exists: false } });
    expect(activeAfterReset).toBe(0);

    const reused = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/password-reset/complete',
      payload: { resetToken: reset.data.resetToken, newPassword: 'AnotherPassword6' },
    });
    expectError(reused, 400, 'INVALID_OR_EXPIRED_RESET_TOKEN');

    const oldLogin = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: EMAIL, password: ORIGINAL_PASSWORD },
    });
    expectError(oldLogin, 401, 'INVALID_CREDENTIALS');
    const newLogin = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: EMAIL, password: NEW_PASSWORD },
    });
    expect(newLogin.statusCode).toBe(200);

    const rawUser = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.users)
      .findOne({ email: EMAIL });
    expect(rawUser?.passwordHash).not.toBe(ORIGINAL_PASSWORD);
    expect(rawUser?.passwordHash).not.toBe(NEW_PASSWORD);
    await expect(verifyPassword(String(rawUser?.passwordHash), NEW_PASSWORD)).resolves.toBe(true);
  });

  it('keeps credential errors equivalent and blocks disabled accounts', async () => {
    const context = requireContext(app, disposable, email);
    const wrongPassword = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: EMAIL, password: 'IncorrectPassword5' },
    });
    const missingAccount = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: 'missing-login@example.edu', password: 'IncorrectPassword5' },
    });
    const wrongError = expectError(wrongPassword, 401, 'INVALID_CREDENTIALS');
    const missingError = expectError(missingAccount, 401, 'INVALID_CREDENTIALS');
    expect(missingError.error.message).toBe(wrongError.error.message);

    await context.disposable.connection.db!
      .collection(COLLECTION_NAMES.users)
      .updateOne({ email: EMAIL }, { $set: { status: 'disabled' } });
    const disabled = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email: EMAIL, password: NEW_PASSWORD },
    });
    expectError(disabled, 403, 'ACCOUNT_DISABLED');
    await context.disposable.connection.db!
      .collection(COLLECTION_NAMES.users)
      .updateOne({ email: EMAIL }, { $set: { status: 'active' } });
  });

  it('preserves health and readiness behavior with the real disposable database', async () => {
    const context = requireContext(app, disposable, email);
    const health = await context.app.inject({ method: 'GET', url: '/health' });
    expect(health.statusCode).toBe(200);
    expect(health.json()).toMatchObject({ data: { status: 'ok' } });

    const ready = await context.app.inject({ method: 'GET', url: '/ready' });
    expect(ready.statusCode).toBe(200);
    expect(ready.json()).toMatchObject({
      data: {
        status: 'ready',
        checks: { database: 'up', storage: 'local', email: 'console' },
      },
    });
  });

  it('maps email delivery failures to the safe existing error contract', async () => {
    const context = requireContext(app, disposable, email);
    context.email.failure = new Error('private provider hostname and credentials');
    const response = await context.app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: {
        firstName: 'Delivery',
        lastName: 'Failure',
        email: 'delivery.failure@example.edu',
        password: 'DeliveryPassword8',
      },
    });
    context.email.failure = undefined;

    const body = expectError(response, 503, 'EMAIL_UNAVAILABLE');
    const serialized = JSON.stringify(body);
    expect(serialized).not.toContain('private provider hostname');
    expect(serialized).not.toContain('credentials');
  });
});
