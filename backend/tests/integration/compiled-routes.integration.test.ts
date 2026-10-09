import { randomUUID } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { FastifyInstance } from 'fastify';
import { PDFDocument, StandardFonts } from 'pdf-lib';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config/env.js';
import { runMigrations } from '../../src/database/migrations/migration-runner.js';
import { seedDatabase } from '../../src/database/seeds/seed-database.js';
import type { AppServices } from '../../src/infrastructure/create-services.js';
import type {
  EmailMessage,
  EmailSendResult,
  EmailSender,
} from '../../src/infrastructure/email/email-sender.js';
import { LocalObjectStorage } from '../../src/infrastructure/storage/local-object-storage.js';
import { LocalOcrEngine } from '../../src/infrastructure/ocr/local-ocr-engine.js';
import { AiMetadataService } from '../../src/modules/documents/ai-metadata.service.js';
import { createTestServices } from '../helpers/build-test-app.js';
import {
  createDisposableMongoDatabase,
  type DisposableMongoDatabase,
} from '../helpers/disposable-mongodb.js';

interface Credentials {
  readonly userId: string;
  readonly accessToken: string;
}

class CapturingEmailSender implements EmailSender {
  private readonly messages: EmailMessage[] = [];

  async send(message: EmailMessage): Promise<EmailSendResult> {
    this.messages.push(message);
    return { messageId: `compiled-test-${this.messages.length}` };
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

async function registerVerifiedUser(
  app: FastifyInstance,
  email: string,
  emailSender: CapturingEmailSender,
): Promise<Credentials> {
  const password = 'CompiledPassword8';
  expect(
    (
      await app.inject({
        method: 'POST',
        url: '/api/v1/auth/register',
        payload: { firstName: 'Compiled', lastName: 'Tester', email, password },
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

function multipartUpload(
  fields: Readonly<Record<string, string>>,
  file: { readonly name: string; readonly mimeType: string; readonly contents: Buffer },
) {
  const boundary = `gradport-${randomUUID()}`;
  const chunks: Buffer[] = [];
  for (const [name, value] of Object.entries(fields)) {
    chunks.push(
      Buffer.from(
        `--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n${value}\r\n`,
      ),
    );
  }
  chunks.push(
    Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${file.name}"\r\nContent-Type: ${file.mimeType}\r\n\r\n`,
    ),
    file.contents,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  );
  return {
    headers: { 'content-type': `multipart/form-data; boundary=${boundary}` },
    payload: Buffer.concat(chunks),
  };
}

async function createMultiDocPdf(): Promise<Buffer> {
  const doc = await PDFDocument.create();
  const font = await doc.embedFont(StandardFonts.Helvetica);

  // Page 1: CV
  const p1 = doc.addPage([600, 400]);
  p1.drawText('CURRICULUM VITAE', { x: 50, y: 350, font, size: 16 });
  p1.drawText('John Lloyd - Software Engineer and Researcher', { x: 50, y: 320, font, size: 12 });
  p1.drawText('Experienced in Flutter, Dart, TypeScript, Node.js and MongoDB.', { x: 50, y: 300, font, size: 12 });

  // Page 2: TOR
  const p2 = doc.addPage([600, 400]);
  p2.drawText('TRANSCRIPT OF RECORDS', { x: 50, y: 350, font, size: 16 });
  p2.drawText('Bachelor of Science in Information Technology - CICS', { x: 50, y: 320, font, size: 12 });
  p2.drawText('Course: Advanced Mobile Development - Grade: 1.00', { x: 50, y: 300, font, size: 12 });

  // Page 3: Certificate
  const p3 = doc.addPage([600, 400]);
  p3.drawText('CERTIFICATE OF PARTICIPATION', { x: 50, y: 350, font, size: 16 });
  p3.drawText('This certifies that the participant attended the Flutter Seminar', { x: 50, y: 320, font, size: 12 });
  p3.drawText('Issued on 2024-05-15 by Tech Society', { x: 50, y: 300, font, size: 12 });

  return Buffer.from(await doc.save());
}

describe.sequential('Compiled document API and Document PATCH routes', () => {
  let app: FastifyInstance;
  let disposable: DisposableMongoDatabase;
  let storageRoot: string;
  let firstUser: Credentials;
  let secondUser: Credentials;
  const emailSender = new CapturingEmailSender();

  beforeAll(async () => {
    disposable = await createDisposableMongoDatabase();
    await runMigrations(disposable.connection.db!);
    await seedDatabase(disposable.connection);
    storageRoot = await mkdtemp(join(tmpdir(), 'gradport-compiled-test-'));
    const storage = new LocalObjectStorage(storageRoot);
    const ocrEngine = new LocalOcrEngine();

    const services: AppServices = {
      ...createTestServices(),
      database: disposable.database,
      email: emailSender,
      storage,
      ocr: ocrEngine,
      metadata: new AiMetadataService({
        recommend: async () => ({}),
        separateCompiled: async () => ({
          documents: [
            {
              startPage: 1,
              endPage: 2,
              categoryKey: 'curriculum-vitae',
              folderKey: 'curriculum-vitae',
              title: 'Curriculum Vitae and Grades',
              documentDate: '2024-01-01',
              confidence: 0.95,
            },
            {
              startPage: 3,
              endPage: 3,
              categoryKey: 'certificates',
              folderKey: 'seminars',
              title: 'Flutter Seminar Certificate',
              documentDate: '2024-05-15',
              confidence: 0.9,
            },
          ],
        }),
      }),
    };

    app = await buildApp({
      config: loadConfig({ NODE_ENV: 'test', LOG_LEVEL: 'silent' }),
      services,
      connectDatabase: false,
    });
    await app.ready();

    firstUser = await registerVerifiedUser(app, 'compiled.one@example.edu', emailSender);
    secondUser = await registerVerifiedUser(app, 'compiled.two@example.edu', emailSender);
  });

  afterAll(async () => {
    await disposable?.stop();
    await app?.close();
    await rm(storageRoot, { recursive: true, force: true }).catch(() => undefined);
  }, 120_000);

  it('PATCH /api/v1/documents/:documentId updates document metadata for the owner', async () => {
    // First upload a document
    const pdfBytes = await createMultiDocPdf();
    const upload = multipartUpload(
      {
        categoryKey: 'curriculum-vitae',
        folderKey: 'curriculum-vitae',
        title: 'Original Title',
        documentDate: '2024-01-01',
      },
      { name: 'doc.pdf', mimeType: 'application/pdf', contents: pdfBytes },
    );

    const uploadRes = await app.inject({
      method: 'POST',
      url: '/api/v1/documents',
      headers: {
        authorization: `Bearer ${firstUser.accessToken}`,
        ...upload.headers,
      },
      payload: upload.payload,
    });
    expect(uploadRes.statusCode).toBe(201);
    const docId = uploadRes.json<{ data: { document: { id: string } } }>().data.document.id;

    // Patch metadata
    const patchRes = await app.inject({
      method: 'PATCH',
      url: `/api/v1/documents/${docId}`,
      headers: {
        authorization: `Bearer ${firstUser.accessToken}`,
        'content-type': 'application/json',
      },
      payload: {
        title: 'Updated Title by Batch Auto-Categorization',
        categoryKey: 'certificates',
        folderKey: 'seminars',
      },
    });
    expect(patchRes.statusCode).toBe(200);
    const updated = patchRes.json<{ data: { document: { title: string; categoryKey: string; folderKey: string } } }>().data.document;
    expect(updated.title).toBe('Updated Title by Batch Auto-Categorization');
    expect(updated.categoryKey).toBe('certificates');
    expect(updated.folderKey).toBe('seminars');

    // Reject folderKey that does not belong to category
    const badFolderRes = await app.inject({
      method: 'PATCH',
      url: `/api/v1/documents/${docId}`,
      headers: {
        authorization: `Bearer ${firstUser.accessToken}`,
        'content-type': 'application/json',
      },
      payload: {
        folderKey: 'invalid-folder',
      },
    });
    expect(badFolderRes.statusCode).toBe(400);

    // Another user cannot patch this document
    const forbiddenRes = await app.inject({
      method: 'PATCH',
      url: `/api/v1/documents/${docId}`,
      headers: {
        authorization: `Bearer ${secondUser.accessToken}`,
        'content-type': 'application/json',
      },
      payload: { title: 'Hacked Title' },
    });
    expect(forbiddenRes.statusCode).toBe(404);
  });

  it('POST /api/v1/documents/compiled/analyze, split, and cancel flow', async () => {
    const pdfBytes = await createMultiDocPdf();
    const upload = multipartUpload(
      {},
      { name: 'compiled.pdf', mimeType: 'application/pdf', contents: pdfBytes },
    );

    // Analyze
    const analyzeRes = await app.inject({
      method: 'POST',
      url: '/api/v1/documents/compiled/analyze',
      headers: {
        authorization: `Bearer ${firstUser.accessToken}`,
        ...upload.headers,
      },
      payload: upload.payload,
    });
    expect(analyzeRes.statusCode).toBe(200);
    const analysis = analyzeRes.json<{
      data: {
        sessionId: string;
        totalPages: number;
        originalFileName: string;
        documents: Array<{
          startPage: number;
          endPage: number;
          categoryKey: string;
          folderKey: string;
          title: string;
        }>;
      };
    }>().data;

    expect(analysis.sessionId).toMatch(/^csess_/);
    expect(analysis.totalPages).toBe(3);
    expect(analysis.documents.length).toBe(2);

    // Split
    const idempotencyKey = randomUUID();
    const splitRes = await app.inject({
      method: 'POST',
      url: '/api/v1/documents/compiled/split',
      headers: {
        authorization: `Bearer ${firstUser.accessToken}`,
        'content-type': 'application/json',
      },
      payload: {
        sessionId: analysis.sessionId,
        idempotencyKey,
        segments: [
          {
            startPage: 1,
            endPage: 2,
            categoryKey: 'curriculum-vitae',
            folderKey: 'curriculum-vitae',
            title: 'Split Curriculum Vitae',
            documentDate: '2024-01-01',
          },
          {
            startPage: 3,
            endPage: 3,
            categoryKey: 'certificates',
            folderKey: 'seminars',
            title: 'Split Certificate',
            documentDate: '2024-05-15',
          },
        ],
      },
    });
    expect(splitRes.statusCode).toBe(200);
    const splitData = splitRes.json<{ data: { documents: Array<{ id: string; title: string }> } }>().data;
    expect(splitData.documents.length).toBe(2);
    expect(splitData.documents[0]?.title).toBe('Split Curriculum Vitae');
    expect(splitData.documents[1]?.title).toBe('Split Certificate');

    // Repeated split with same idempotencyKey returns cached result
    const repeatRes = await app.inject({
      method: 'POST',
      url: '/api/v1/documents/compiled/split',
      headers: {
        authorization: `Bearer ${firstUser.accessToken}`,
        'content-type': 'application/json',
      },
      payload: {
        sessionId: analysis.sessionId,
        idempotencyKey,
        segments: [
          {
            startPage: 1,
            endPage: 2,
            categoryKey: 'curriculum-vitae',
            folderKey: 'curriculum-vitae',
            title: 'Split Curriculum Vitae',
            documentDate: '2024-01-01',
          },
        ],
      },
    });
    // A key cannot be reused with a different reviewed payload.
    expect(repeatRes.statusCode).toBe(409);
    expect(repeatRes.json().error.code).toBe('SPLIT_REQUEST_CHANGED');
  });

  it('POST /api/v1/documents/compiled/cancel cleans up session', async () => {
    const pdfBytes = await createMultiDocPdf();
    const upload = multipartUpload(
      {},
      { name: 'compiled_to_cancel.pdf', mimeType: 'application/pdf', contents: pdfBytes },
    );

    const analyzeRes = await app.inject({
      method: 'POST',
      url: '/api/v1/documents/compiled/analyze',
      headers: {
        authorization: `Bearer ${firstUser.accessToken}`,
        ...upload.headers,
      },
      payload: upload.payload,
    });
    const { sessionId } = analyzeRes.json<{ data: { sessionId: string } }>().data;

    const cancelRes = await app.inject({
      method: 'POST',
      url: '/api/v1/documents/compiled/cancel',
      headers: {
        authorization: `Bearer ${firstUser.accessToken}`,
        'content-type': 'application/json',
      },
      payload: { sessionId },
    });
    expect(cancelRes.statusCode).toBe(200);
    expect(cancelRes.json<{ data: { cancelled: boolean } }>().data.cancelled).toBe(true);

    // Split after cancel fails with 404
    const splitAfterCancel = await app.inject({
      method: 'POST',
      url: '/api/v1/documents/compiled/split',
      headers: {
        authorization: `Bearer ${firstUser.accessToken}`,
        'content-type': 'application/json',
      },
      payload: {
        sessionId,
        idempotencyKey: 'cancelled-key',
        segments: [
          {
            startPage: 1,
            endPage: 1,
            categoryKey: 'curriculum-vitae',
            folderKey: 'curriculum-vitae',
            title: 'Cancelled CV',
            documentDate: '2024-01-01',
          },
        ],
      },
    });
    expect(splitAfterCancel.statusCode).toBe(404);
  });
});
