import { Readable } from 'node:stream';
import { inflateSync } from 'node:zlib';
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

const SAMPLE_1X1_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  'base64',
);

function hexToString(hex: string): string {
  let str = '';
  for (let i = 0; i < hex.length; i += 2) {
    str += String.fromCharCode(parseInt(hex.slice(i, i + 2), 16));
  }
  return str;
}

function extractAllPdfText(pdfBytes: Buffer): string {
  const raw = pdfBytes.toString('latin1');
  let accumulated = raw;
  const regex = /stream\r?\n([\s\S]*?)\r?\nendstream/g;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(raw)) !== null) {
    const streamContent = match[1];
    if (!streamContent) continue;
    const streamBuffer = Buffer.from(streamContent, 'latin1');
    try {
      const decompressed = inflateSync(streamBuffer).toString('latin1');
      accumulated += '\n' + decompressed;
      const hexMatches = decompressed.matchAll(/<([0-9a-fA-F]+)>/g);
      for (const h of hexMatches) {
        const hex = h[1];
        if (hex) accumulated += ' ' + hexToString(hex);
      }
    } catch {
      // Ignore non-zlib streams
    }
  }
  return accumulated;
}

import type {
  ObjectStorage,
  StoredObject,
} from '../../src/infrastructure/storage/object-storage.js';
import type { ServiceHealth } from '../../src/common/types/service-health.js';

class InMemoryTestStorage implements ObjectStorage {
  readonly items = new Map<string, Buffer>();

  async put(key: string, contents: Readable): Promise<StoredObject> {
    const chunks: Buffer[] = [];
    for await (const chunk of contents) {
      chunks.push(typeof chunk === 'string' ? Buffer.from(chunk) : chunk);
    }
    const buf = Buffer.concat(chunks);
    this.items.set(key, buf);
    return { key, sizeBytes: buf.length };
  }

  async get(key: string): Promise<Readable> {
    const data = this.items.get(key);
    if (!data) throw new Error(`Object not found in test storage: ${key}`);
    return Readable.from([data]);
  }

  async delete(key: string): Promise<void> {
    this.items.delete(key);
  }

  async exists(key: string): Promise<boolean> {
    return this.items.has(key);
  }

  async healthCheck(): Promise<ServiceHealth> {
    return { status: 'local' };
  }
}

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
  let services: AppServices | undefined;
  let firstUser: Credentials;
  let secondUser: Credentials;
  const emailSender = new CapturingEmailSender();

  beforeAll(async () => {
    disposable = await createDisposableMongoDatabase();
    await runMigrations(disposable.connection.db!);
    services = {
      ...createTestServices(),
      database: disposable.database,
      storage: new InMemoryTestStorage(),
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

  it('enforces owner-scoped PDF export security on GET and POST endpoints', async () => {
    // 1. Unauthenticated requests are rejected
    expectError(
      await app!.inject({ method: 'GET', url: `/api/v1/portfolios/${portfolioId}/export/pdf` }),
      401,
      'UNAUTHORIZED',
    );
    expectError(
      await app!.inject({
        method: 'POST',
        url: '/api/v1/portfolios/export/pdf',
        payload: portfolioInput,
      }),
      401,
      'UNAUTHORIZED',
    );

    // 2. Second user cannot export first user's portfolio via GET
    expectError(
      await app!.inject({
        method: 'GET',
        url: `/api/v1/portfolios/${portfolioId}/export/pdf`,
        headers: bearer(secondUser.accessToken),
      }),
      404,
      'PORTFOLIO_NOT_FOUND',
    );

    // 3. First user CAN export own portfolio via GET
    const firstExport = await app!.inject({
      method: 'GET',
      url: `/api/v1/portfolios/${portfolioId}/export/pdf`,
      headers: bearer(firstUser.accessToken),
    });
    expect(firstExport.statusCode).toBe(200);
    expect(firstExport.headers['content-type']).toBe('application/pdf');
    expect(firstExport.rawPayload.subarray(0, 5).toString()).toBe('%PDF-');

    // 4. Seed documents for both users and test POST /api/v1/portfolios/export/pdf
    const storage = services!.storage;
    const doc1Key = `users/${firstUser.userId}/documents/first_owner_cert.png`;
    const doc2Key = `users/${secondUser.userId}/documents/second_owner_secret.png`;
    await storage.put(doc1Key, Readable.from([SAMPLE_1X1_PNG]));
    await storage.put(doc2Key, Readable.from([SAMPLE_1X1_PNG]));

    await disposable!.connection.db!.collection(COLLECTION_NAMES.documents).insertOne({
      ownerId: new Types.ObjectId(firstUser.userId),
      categoryKey: 'certificates',
      folderKey: 'certificate-of-attendance',
      title: 'FirstUser_AllowedDoc_Title',
      description: 'First user certificate',
      reflection: 'First user personal reflection',
      objectKey: doc1Key,
      originalFileName: 'first_cert.png',
      mimeType: 'image/png',
      fileKind: 'image',
      extension: 'png',
      sizeBytes: SAMPLE_1X1_PNG.length,
      sha256: 'hash1',
      documentDate: new Date(),
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    await disposable!.connection.db!.collection(COLLECTION_NAMES.documents).insertOne({
      ownerId: new Types.ObjectId(secondUser.userId),
      categoryKey: 'certificates',
      folderKey: 'certificate-of-attendance',
      title: 'SecondUser_ForbiddenSecret_Title',
      description: 'Second user secret doc',
      reflection: 'Second user private reflection',
      objectKey: doc2Key,
      originalFileName: 'second_cert.png',
      mimeType: 'image/png',
      fileKind: 'image',
      extension: 'png',
      sizeBytes: SAMPLE_1X1_PNG.length,
      sha256: 'hash2',
      documentDate: new Date(),
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    const postExport = await app!.inject({
      method: 'POST',
      url: '/api/v1/portfolios/export/pdf',
      headers: bearer(firstUser.accessToken),
      payload: portfolioInput,
    });
    expect(postExport.statusCode).toBe(200);
    expect(postExport.headers['content-type']).toBe('application/pdf');

    const pdfBuffer = postExport.rawPayload;
    const decompressed = extractAllPdfText(pdfBuffer);

    // Verify first owner's documents are present
    expect(decompressed).toContain('FirstUser_AllowedDoc_Title');

    // Verify second owner's documents are NEVER included
    expect(decompressed).not.toContain('SecondUser_ForbiddenSecret_Title');
    expect(decompressed).not.toContain('Second user secret doc');
    expect(decompressed).not.toContain('Second user private reflection');

    // Verify raw storage keys / private URLs are not leaked
    expect(decompressed).not.toContain(doc1Key);
    expect(decompressed).not.toContain(doc2Key);
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
