import type { FastifyInstance, LightMyRequestResponse } from 'fastify';
import { Types } from 'mongoose';
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

interface Credentials {
  readonly userId: string;
  readonly accessToken: string;
}

interface ErrorEnvelope {
  readonly error: {
    readonly code: string;
    readonly requestId: string;
    readonly fields?: Readonly<Record<string, readonly string[]>>;
  };
}

interface PortfolioBody {
  readonly id: string;
  readonly fullName: string;
  readonly yearAndSection: string;
  readonly schedule: string;
  readonly instructorName: string;
  readonly course: string;
  readonly courseCode: string;
  readonly semesterAndYear: string;
  readonly createdAt: string;
  readonly updatedAt: string;
}

class CapturingEmailSender implements EmailSender {
  private readonly messages: EmailMessage[] = [];

  async send(message: EmailMessage): Promise<EmailSendResult> {
    this.messages.push(message);
    return { messageId: `portfolio-test-${this.messages.length}` };
  }

  async healthCheck() {
    return { status: 'console' as const };
  }

  latestCode(): string {
    const code = this.messages.at(-1)?.text?.match(/\b\d{6}\b/)?.[0];
    if (code === undefined) throw new Error('Verification code was not captured.');
    return code;
  }
}

function bearer(token: string) {
  return { authorization: `Bearer ${token}` };
}

function expectError(response: LightMyRequestResponse, status: number, code: string) {
  expect(response.statusCode).toBe(status);
  const body = response.json<ErrorEnvelope>();
  expect(body.error).toMatchObject({ code, requestId: response.headers['x-request-id'] });
  return body;
}

async function registerVerifiedUser(
  app: FastifyInstance,
  email: string,
  emailSender: CapturingEmailSender,
): Promise<Credentials> {
  const password = 'PortfolioPassword8';
  expect(
    (
      await app.inject({
        method: 'POST',
        url: '/api/v1/auth/register',
        payload: { firstName: 'Portfolio', lastName: 'Owner', email, password },
      })
    ).statusCode,
  ).toBe(201);
  expect(
    (
      await app.inject({
        method: 'POST',
        url: '/api/v1/auth/email-verification/verify',
        payload: { email, code: emailSender.latestCode() },
      })
    ).statusCode,
  ).toBe(200);
  const login = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/login',
    payload: { email, password },
  });
  expect(login.statusCode).toBe(200);
  const session = login.json<{
    readonly data: {
      readonly user: { readonly id: string };
      readonly tokens: { readonly accessToken: string };
    };
  }>();
  return { userId: session.data.user.id, accessToken: session.data.tokens.accessToken };
}

const portfolioInput = {
  fullName: '  Portfolio Student  ',
  yearAndSection: '  4BSIT-1  ',
  schedule: '  Monday 8:00 AM - 9:30 AM  ',
  instructorName: '  Professor Example  ',
  course: '  Free Elective  ',
  courseCode: '  CCSFE4-18  ',
  semesterAndYear: '  2nd Semester, A.Y. 2025-2026  ',
};

describe.sequential('authenticated portfolio API with disposable MongoDB', () => {
  let app: FastifyInstance | undefined;
  let disposable: DisposableMongoDatabase | undefined;
  let firstUser: Credentials;
  let secondUser: Credentials;
  const emailSender = new CapturingEmailSender();

  beforeAll(async () => {
    disposable = await createDisposableMongoDatabase();
    await runMigrations(disposable.connection.db!);
    const services: AppServices = {
      ...createTestServices(),
      database: disposable.database,
      email: emailSender,
    };
    app = await buildApp({
      config: loadConfig({ NODE_ENV: 'test', LOG_LEVEL: 'silent' }),
      services,
      connectDatabase: false,
    });
    await app.ready();
    firstUser = await registerVerifiedUser(app, 'portfolio.one@example.edu', emailSender);
    secondUser = await registerVerifiedUser(app, 'portfolio.two@example.edu', emailSender);
  }, 120_000);

  afterAll(async () => {
    if (disposable !== undefined) await disposable.stop();
    if (app !== undefined) await app.close();
  }, 120_000);

  it('rejects every unauthenticated CRUD operation', async () => {
    const id = '0123456789abcdef01234567';
    for (const request of [
      { method: 'GET', url: '/api/v1/portfolios' },
      { method: 'POST', url: '/api/v1/portfolios', payload: portfolioInput },
      { method: 'GET', url: `/api/v1/portfolios/${id}` },
      { method: 'PATCH', url: `/api/v1/portfolios/${id}`, payload: { course: 'No' } },
      { method: 'DELETE', url: `/api/v1/portfolios/${id}` },
    ] as const) {
      expectError(await app!.inject(request), 401, 'UNAUTHORIZED');
    }
  });

  let portfolioId = '';

  it('creates, normalizes, safely projects, lists, and retrieves an owned portfolio', async () => {
    const created = await app!.inject({
      method: 'POST',
      url: '/api/v1/portfolios',
      headers: bearer(firstUser.accessToken),
      payload: portfolioInput,
    });
    expect(created.statusCode).toBe(201);
    const portfolio = created.json<{ readonly data: { readonly portfolio: PortfolioBody } }>().data
      .portfolio;
    portfolioId = portfolio.id;
    expect(portfolio).toMatchObject({
      fullName: 'Portfolio Student',
      yearAndSection: '4BSIT-1',
      course: 'Free Elective',
      courseCode: 'CCSFE4-18',
    });
    const serialized = JSON.stringify(portfolio);
    for (const forbidden of ['ownerId', 'userId', 'passwordHash', 'session', '__v']) {
      expect(serialized).not.toContain(forbidden);
    }

    const raw = await disposable!.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.portfolios)
      .findOne({ _id: new Types.ObjectId(portfolioId) });
    expect(raw?.ownerId?.toString()).toBe(firstUser.userId);

    const list = await app!.inject({
      method: 'GET',
      url: '/api/v1/portfolios',
      headers: bearer(firstUser.accessToken),
    });
    expect(list.statusCode).toBe(200);
    expect(
      list.json<{ readonly data: { readonly portfolios: PortfolioBody[] } }>().data.portfolios,
    ).toEqual([expect.objectContaining({ id: portfolioId, fullName: 'Portfolio Student' })]);

    const get = await app!.inject({
      method: 'GET',
      url: `/api/v1/portfolios/${portfolioId}`,
      headers: bearer(firstUser.accessToken),
    });
    expect(get.statusCode).toBe(200);
    expect(get.json()).toMatchObject({ data: { portfolio: { id: portfolioId } } });
  });

  it('persists allowed edits and rejects invalid or protected fields', async () => {
    const updated = await app!.inject({
      method: 'PATCH',
      url: `/api/v1/portfolios/${portfolioId}`,
      headers: bearer(firstUser.accessToken),
      payload: { course: '  Updated Course  ', semesterAndYear: '' },
    });
    expect(updated.statusCode).toBe(200);
    expect(updated.json()).toMatchObject({
      data: { portfolio: { id: portfolioId, course: 'Updated Course', semesterAndYear: '' } },
    });

    const persisted = await disposable!.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.portfolios)
      .findOne({ course: 'Updated Course' });
    expect(persisted).toMatchObject({ fullName: 'Portfolio Student' });
    expect(persisted?.ownerId?.toString()).toBe(firstUser.userId);

    for (const payload of [
      {},
      { fullName: '   ' },
      { ownerId: secondUser.userId },
      { userId: secondUser.userId, course: 'Ownership violation' },
      { createdAt: new Date().toISOString() },
    ]) {
      const response = await app!.inject({
        method: 'PATCH',
        url: `/api/v1/portfolios/${portfolioId}`,
        headers: bearer(firstUser.accessToken),
        payload,
      });
      expectError(response, 400, 'VALIDATION_ERROR');
    }

    const missingRequired = await app!.inject({
      method: 'POST',
      url: '/api/v1/portfolios',
      headers: bearer(firstUser.accessToken),
      payload: { ...portfolioInput, schedule: undefined },
    });
    expectError(missingRequired, 400, 'VALIDATION_ERROR');
  });

  it('returns the same safe not-found response for another owner', async () => {
    for (const request of [
      { method: 'GET', url: `/api/v1/portfolios/${portfolioId}` },
      {
        method: 'PATCH',
        url: `/api/v1/portfolios/${portfolioId}`,
        payload: { course: 'Stolen' },
      },
      { method: 'DELETE', url: `/api/v1/portfolios/${portfolioId}` },
    ] as const) {
      expectError(
        await app!.inject({ ...request, headers: bearer(secondUser.accessToken) }),
        404,
        'PORTFOLIO_NOT_FOUND',
      );
    }

    const secondList = await app!.inject({
      method: 'GET',
      url: '/api/v1/portfolios',
      headers: bearer(secondUser.accessToken),
    });
    expect(secondList.statusCode).toBe(200);
    expect(secondList.json()).toMatchObject({ data: { portfolios: [] } });
  });

  it('deletes only the authenticated owner portfolio', async () => {
    const deleted = await app!.inject({
      method: 'DELETE',
      url: `/api/v1/portfolios/${portfolioId}`,
      headers: bearer(firstUser.accessToken),
    });
    expect(deleted.statusCode).toBe(200);
    expect(deleted.json()).toMatchObject({ data: { status: 'deleted', portfolioId } });

    const missing = await app!.inject({
      method: 'GET',
      url: `/api/v1/portfolios/${portfolioId}`,
      headers: bearer(firstUser.accessToken),
    });
    expectError(missing, 404, 'PORTFOLIO_NOT_FOUND');
  });
});
