import { randomUUID } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Readable } from 'node:stream';
import type { FastifyInstance, LightMyRequestResponse } from 'fastify';
import { Types } from 'mongoose';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config/env.js';
import { COLLECTION_NAMES } from '../../src/database/collection-names.js';
import { runMigrations } from '../../src/database/migrations/migration-runner.js';
import { seedDatabase } from '../../src/database/seeds/seed-database.js';
import type { AppServices } from '../../src/infrastructure/create-services.js';
import type {
  EmailMessage,
  EmailSendResult,
  EmailSender,
} from '../../src/infrastructure/email/email-sender.js';
import { LocalObjectStorage } from '../../src/infrastructure/storage/local-object-storage.js';
import type {
  ObjectStorage,
  StoredObject,
} from '../../src/infrastructure/storage/object-storage.js';
import {
  OcrEngineError,
  type OcrEngine,
  type OcrExtraction,
  type OcrInput,
} from '../../src/infrastructure/ocr/ocr-engine.js';
import {
  DocumentService,
  MAX_DOCUMENT_FILE_SIZE_BYTES,
} from '../../src/modules/documents/document.service.js';
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
  readonly error: { readonly code: string; readonly requestId: string };
}

interface DocumentBody {
  readonly id: string;
  readonly categoryKey: string;
  readonly folderKey: string;
  readonly title: string;
  readonly originalFileName: string;
  readonly mimeType: string;
  readonly sizeBytes: number;
}

interface OcrBody {
  readonly status: string;
  readonly rawText?: string;
  readonly reviewedText?: string;
  readonly engine?: string;
}

class CapturingEmailSender implements EmailSender {
  private readonly messages: EmailMessage[] = [];

  async send(message: EmailMessage): Promise<EmailSendResult> {
    this.messages.push(message);
    return { messageId: `document-test-${this.messages.length}` };
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

class TrackingStorage implements ObjectStorage {
  readonly keys = new Set<string>();
  failNextPut = false;
  corruptNextReturnedKey = false;
  private readonly aliases = new Map<string, string>();

  constructor(private readonly local: LocalObjectStorage) {}

  async put(key: string, contents: Readable): Promise<StoredObject> {
    if (this.failNextPut) {
      this.failNextPut = false;
      throw new Error('Simulated storage failure.');
    }
    const stored = await this.local.put(key, contents);
    this.keys.add(stored.key);
    if (!this.corruptNextReturnedKey) return stored;
    this.corruptNextReturnedKey = false;
    const invalidKey = `invalid-${'x'.repeat(1_025)}`;
    this.aliases.set(invalidKey, stored.key);
    return { key: invalidKey, sizeBytes: stored.sizeBytes };
  }

  async get(key: string): Promise<Readable> {
    return this.local.get(this.aliases.get(key) ?? key);
  }

  async delete(key: string): Promise<void> {
    const actual = this.aliases.get(key) ?? key;
    this.aliases.delete(key);
    await this.local.delete(actual);
    this.keys.delete(actual);
  }

  async exists(key: string): Promise<boolean> {
    return this.local.exists(this.aliases.get(key) ?? key);
  }

  async healthCheck() {
    return this.local.healthCheck();
  }
}

class ControllableOcrEngine implements OcrEngine {
  readonly calls: OcrInput[] = [];
  nextFailure: OcrEngineError | undefined;
  nextRawText: string | undefined;
  private blocked:
    | {
        readonly started: Promise<void>;
        readonly markStarted: () => void;
        readonly released: Promise<void>;
        readonly release: () => void;
      }
    | undefined;

  blockNext() {
    let markStarted!: () => void;
    let release!: () => void;
    const started = new Promise<void>((resolve) => {
      markStarted = resolve;
    });
    const released = new Promise<void>((resolve) => {
      release = resolve;
    });
    this.blocked = { started, markStarted, released, release };
    return { started, release };
  }

  async extract(input: OcrInput): Promise<OcrExtraction> {
    this.calls.push(input);
    const blocked = this.blocked;
    this.blocked = undefined;
    if (blocked !== undefined) {
      blocked.markStarted();
      await blocked.released;
    }
    const failure = this.nextFailure;
    this.nextFailure = undefined;
    if (failure !== undefined) throw failure;
    const rawText =
      this.nextRawText ??
      (input.fileKind === 'pdf'
        ? 'Embedded PDF text from a deterministic fixture.'
        : 'Recognized image text from a deterministic fixture.');
    this.nextRawText = undefined;
    return {
      rawText,
      engine: input.fileKind === 'pdf' ? 'pdfjs' : 'tesseract.js',
    };
  }
}

function bearer(token: string) {
  return { authorization: `Bearer ${token}` };
}

function expectError(response: LightMyRequestResponse, status: number, code: string) {
  expect(response.statusCode).toBe(status);
  expect(response.json<ErrorEnvelope>().error).toMatchObject({
    code,
    requestId: response.headers['x-request-id'],
  });
}

async function registerVerifiedUser(
  app: FastifyInstance,
  email: string,
  emailSender: CapturingEmailSender,
): Promise<Credentials> {
  const password = 'DocumentPassword8';
  expect(
    (
      await app.inject({
        method: 'POST',
        url: '/api/v1/auth/register',
        payload: { firstName: 'Document', lastName: 'Owner', email, password },
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

const documentFields = {
  categoryKey: 'certificates',
  folderKey: 'seminars',
  title: '  Demo Certificate  ',
  documentDate: '2026-09-11',
  description: '  Uploaded for the demonstration.  ',
};

const pdf = Buffer.from('%PDF-1.7\nGradPort demo PDF');
const jpeg = Buffer.from(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/AX//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAY/An//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/IX//2gAMAwEAAgADAAAAEP/EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQMBAT8Qf//EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQIBAT8Qf//EABQQAQAAAAAAAAAAAAAAAAAAABD/2gAIAQEAAT8Qf//Z',
  'base64',
);
const png = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64',
);

describe.sequential('authenticated document API with disposable storage and MongoDB', () => {
  let app: FastifyInstance | undefined;
  let limitedApp: FastifyInstance | undefined;
  let disposable: DisposableMongoDatabase | undefined;
  let storageRoot: string | undefined;
  let storage: TrackingStorage;
  let firstUser: Credentials;
  let secondUser: Credentials;
  const emailSender = new CapturingEmailSender();
  const ocrEngine = new ControllableOcrEngine();
  const uploadedIds: string[] = [];

  beforeAll(async () => {
    disposable = await createDisposableMongoDatabase();
    await runMigrations(disposable.connection.db!);
    await seedDatabase(disposable.connection);
    storageRoot = await mkdtemp(join(tmpdir(), 'gradport-document-test-'));
    storage = new TrackingStorage(new LocalObjectStorage(storageRoot));
    const services: AppServices = {
      ...createTestServices(),
      database: disposable.database,
      email: emailSender,
      storage,
      ocr: ocrEngine,
    };
    app = await buildApp({
      config: loadConfig({ NODE_ENV: 'test', LOG_LEVEL: 'silent' }),
      services,
      connectDatabase: false,
    });
    await app.ready();
    firstUser = await registerVerifiedUser(app, 'document.one@example.edu', emailSender);
    secondUser = await registerVerifiedUser(app, 'document.two@example.edu', emailSender);
    limitedApp = await buildApp({
      config: loadConfig({
        NODE_ENV: 'test',
        LOG_LEVEL: 'silent',
        DOCUMENT_UPLOAD_RATE_LIMIT_MAX: '1',
        DOCUMENT_OCR_RATE_LIMIT_MAX: '1',
      }),
      services,
      connectDatabase: false,
    });
    await limitedApp.ready();
  }, 120_000);

  afterAll(async () => {
    if (disposable !== undefined) await disposable.stop();
    if (limitedApp !== undefined) await limitedApp.close();
    if (app !== undefined) await app.close();
    if (storageRoot !== undefined) await rm(storageRoot, { recursive: true, force: true });
  }, 120_000);

  it('rejects unauthenticated document operations', async () => {
    const id = '0123456789abcdef01234567';
    for (const request of [
      { method: 'GET', url: '/api/v1/documents' },
      { method: 'GET', url: '/api/v1/documents/categories' },
      { method: 'GET', url: `/api/v1/documents/${id}` },
      { method: 'GET', url: `/api/v1/documents/${id}/content` },
      { method: 'GET', url: `/api/v1/documents/${id}/ocr` },
      { method: 'POST', url: `/api/v1/documents/${id}/ocr`, payload: {} },
      {
        method: 'PATCH',
        url: `/api/v1/documents/${id}/ocr`,
        payload: { reviewedText: 'reviewed' },
      },
      { method: 'DELETE', url: `/api/v1/documents/${id}` },
      { method: 'POST', url: '/api/v1/documents' },
    ] as const) {
      expectError(await app!.inject(request), 401, 'UNAUTHORIZED');
    }
  });

  it('returns the seeded categories and Creative Title folders', async () => {
    const response = await app!.inject({
      method: 'GET',
      url: '/api/v1/documents/categories',
      headers: bearer(firstUser.accessToken),
    });
    expect(response.statusCode).toBe(200);
    const categories = response.json<{
      readonly data: {
        readonly categories: readonly {
          readonly key: string;
          readonly folders: readonly { readonly key: string }[];
        }[];
      };
    }>().data.categories;
    expect(categories).toHaveLength(6);
    expect(categories.find(({ key }) => key === 'curriculum-vitae')?.folders).toContainEqual({
      key: 'creative-title',
      name: 'Creative Title',
    });
  });

  it.each([
    ['PDF', '../../resume.pdf', 'resume.pdf', 'application/pdf', pdf],
    ['JPEG', 'certificate.jpg', 'certificate.jpg', 'image/jpeg', jpeg],
    ['PNG', 'award.png', 'award.png', 'image/png', png],
  ])('uploads a valid %s with safe persisted metadata', async (
    _label,
    uploadName,
    expectedName,
    mimeType,
    contents,
  ) => {
    const upload = multipartUpload(documentFields, { name: uploadName, mimeType, contents });
    const response = await app!.inject({
      method: 'POST',
      url: '/api/v1/documents',
      headers: { ...bearer(firstUser.accessToken), ...upload.headers },
      payload: upload.payload,
    });
    expect(response.statusCode).toBe(201);
    const document = response.json<{ readonly data: { readonly document: DocumentBody } }>().data
      .document;
    uploadedIds.push(document.id);
    expect(document).toMatchObject({
      categoryKey: 'certificates',
      folderKey: 'seminars',
      title: 'Demo Certificate',
      originalFileName: expectedName,
      mimeType,
      sizeBytes: contents.length,
    });
    for (const forbidden of ['ownerId', 'objectKey', 'sha256', 'fileBytes', 'filePath']) {
      expect(JSON.stringify(document)).not.toContain(forbidden);
    }

    const raw = await disposable!.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.documents)
      .findOne({ _id: new Types.ObjectId(document.id) });
    expect(raw?.ownerId?.toString()).toBe(firstUser.userId);
    expect(raw?.sha256).toBeTypeOf('string');
    expect(raw?.objectKey).toBeTypeOf('string');
    expect(await storage.exists(String(raw?.objectKey))).toBe(true);
    expect(raw).not.toHaveProperty('fileBytes');
  });

  it('rejects unsupported, mismatched, excessive, and protected upload data', async () => {
    for (const file of [
      { name: 'notes.txt', mimeType: 'text/plain', contents: Buffer.from('notes') },
      { name: 'fake.pdf', mimeType: 'application/pdf', contents: Buffer.from('not a pdf') },
    ]) {
      const upload = multipartUpload(documentFields, file);
      expectError(
        await app!.inject({
          method: 'POST',
          url: '/api/v1/documents',
          headers: { ...bearer(firstUser.accessToken), ...upload.headers },
          payload: upload.payload,
        }),
        415,
        'UNSUPPORTED_FILE_TYPE',
      );
    }

    const excessive = multipartUpload(documentFields, {
      name: 'large.pdf',
      mimeType: 'application/pdf',
      contents: Buffer.concat([
        Buffer.from('%PDF-'),
        Buffer.alloc(MAX_DOCUMENT_FILE_SIZE_BYTES - 4),
      ]),
    });
    expectError(
      await app!.inject({
        method: 'POST',
        url: '/api/v1/documents',
        headers: { ...bearer(firstUser.accessToken), ...excessive.headers },
        payload: excessive.payload,
      }),
      413,
      'FILE_TOO_LARGE',
    );

    const protectedField = multipartUpload(
      { ...documentFields, ownerId: secondUser.userId },
      { name: 'protected.pdf', mimeType: 'application/pdf', contents: pdf },
    );
    expectError(
      await app!.inject({
        method: 'POST',
        url: '/api/v1/documents',
        headers: { ...bearer(firstUser.accessToken), ...protectedField.headers },
        payload: protectedField.payload,
      }),
      400,
      'VALIDATION_ERROR',
    );

    const overlongField = multipartUpload(
      { ...documentFields, title: 'x'.repeat(5_001) },
      { name: 'overlong.pdf', mimeType: 'application/pdf', contents: pdf },
    );
    expectError(
      await app!.inject({
        method: 'POST',
        url: '/api/v1/documents',
        headers: { ...bearer(firstUser.accessToken), ...overlongField.headers },
        payload: overlongField.payload,
      }),
      400,
      'VALIDATION_ERROR',
    );
  });

  it('previews OCR with suggestions without persisting guessed metadata or objects', async () => {
    const beforeCount = await disposable!.connection.db!.collection(COLLECTION_NAMES.documents).countDocuments();
    const beforeKeys = storage.keys.size;
    const rawText = 'Certificate of Completion\nCourse: Digital Records Management\nIssued on Sep 14, 2026';
    ocrEngine.nextRawText = rawText;
    const upload = multipartUpload({}, { name: 'course.png', mimeType: 'image/png', contents: png });
    const response = await app!.inject({
      method: 'POST', url: '/api/v1/documents/ocr-preview',
      headers: { ...bearer(firstUser.accessToken), ...upload.headers }, payload: upload.payload,
    });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ data: { ocr: {
      status: 'ready', rawText, reviewedText: rawText,
      metadataSuggestions: {
        categoryKey: 'certificates', folderKey: 'trainings',
        title: 'Digital Records Management', documentDate: '2026-09-14',
      },
    } }, meta: { requestId: response.headers['x-request-id'] } });
    expect(JSON.stringify(response.json())).not.toContain('reflection');
    expect(await disposable!.connection.db!.collection(COLLECTION_NAMES.documents).countDocuments()).toBe(beforeCount);
    expect(storage.keys.size).toBe(beforeKeys);
  });

  it('authenticates preview and rejects client ownership/text fields and invalid files', async () => {
    const upload = multipartUpload({}, { name: 'course.png', mimeType: 'image/png', contents: png });
    expectError(await app!.inject({
      method: 'POST', url: '/api/v1/documents/ocr-preview',
      headers: upload.headers, payload: upload.payload,
    }), 401, 'UNAUTHORIZED');
    for (const field of ['ownerId', 'documentId', 'reviewedText']) {
      const invalid = multipartUpload({ [field]: secondUser.userId }, { name: 'course.png', mimeType: 'image/png', contents: png });
      expectError(await app!.inject({
        method: 'POST', url: '/api/v1/documents/ocr-preview',
        headers: { ...bearer(firstUser.accessToken), ...invalid.headers }, payload: invalid.payload,
      }), 400, 'VALIDATION_ERROR');
    }
    const invalid = multipartUpload({}, { name: 'fake.png', mimeType: 'image/png', contents: Buffer.from('not an image') });
    expectError(await app!.inject({
      method: 'POST', url: '/api/v1/documents/ocr-preview',
      headers: { ...bearer(firstUser.accessToken), ...invalid.headers }, payload: invalid.payload,
    }), 415, 'UNSUPPORTED_FILE_TYPE');
    ocrEngine.nextFailure = new OcrEngineError('timeout');
    expectError(await app!.inject({
      method: 'POST', url: '/api/v1/documents/ocr-preview',
      headers: { ...bearer(firstUser.accessToken), ...upload.headers }, payload: upload.payload,
    }), 504, 'OCR_TIMEOUT');
  });

  it('lists, summarizes, retrieves, and streams only safe owned data', async () => {
    const list = await app!.inject({
      method: 'GET',
      url: '/api/v1/documents',
      headers: bearer(firstUser.accessToken),
    });
    expect(list.statusCode).toBe(200);
    expect(list.json()).toMatchObject({
      data: {
        documents: expect.arrayContaining(
          uploadedIds.map((id) => expect.objectContaining({ id })),
        ),
        summary: {
          totalCount: 3,
          categoryCounts: { certificates: 3 },
          folderCounts: { 'certificates/seminars': 3 },
        },
      },
    });

    const id = uploadedIds[0]!;
    const get = await app!.inject({
      method: 'GET',
      url: `/api/v1/documents/${id}`,
      headers: bearer(firstUser.accessToken),
    });
    expect(get.statusCode).toBe(200);
    expect(get.json()).toMatchObject({ data: { document: { id } } });

    const content = await app!.inject({
      method: 'GET',
      url: `/api/v1/documents/${id}/content`,
      headers: bearer(firstUser.accessToken),
    });
    expect(content.statusCode).toBe(200);
    expect(content.headers['content-type']).toContain('application/pdf');
    expect(content.rawPayload).toEqual(pdf);

    const otherList = await app!.inject({
      method: 'GET',
      url: '/api/v1/documents',
      headers: bearer(secondUser.accessToken),
    });
    expect(otherList.json()).toMatchObject({
      data: { documents: [], summary: { totalCount: 0 } },
    });
  });

  it('uses the same safe not-found response for cross-user metadata, content, and delete', async () => {
    const id = uploadedIds[0]!;
    for (const request of [
      { method: 'GET', url: `/api/v1/documents/${id}` },
      { method: 'GET', url: `/api/v1/documents/${id}/content` },
      { method: 'DELETE', url: `/api/v1/documents/${id}` },
    ] as const) {
      expectError(
        await app!.inject({ ...request, headers: bearer(secondUser.accessToken) }),
        404,
        'DOCUMENT_NOT_FOUND',
      );
    }
  });

  it('extracts PNG/JPEG image text and embedded PDF text, then persists reviewed text', async () => {
    const [pdfId, jpegId, pngId] = uploadedIds;
    expect(pdfId).toBeDefined();
    expect(jpegId).toBeDefined();
    expect(pngId).toBeDefined();

    const initial = await app!.inject({
      method: 'GET',
      url: `/api/v1/documents/${pngId!}/ocr`,
      headers: bearer(firstUser.accessToken),
    });
    expect(initial.statusCode).toBe(200);
    expect(initial.json()).toMatchObject({ data: { ocr: { status: 'not_processed' } } });

    for (const [id, expectedEngine] of [
      [pngId!, 'tesseract.js'],
      [jpegId!, 'tesseract.js'],
      [pdfId!, 'pdfjs'],
    ] as const) {
      const response = await app!.inject({
        method: 'POST',
        url: `/api/v1/documents/${id}/ocr`,
        headers: bearer(firstUser.accessToken),
        payload: {},
      });
      expect(response.statusCode).toBe(200);
      expect(response.json<{ readonly data: { readonly ocr: OcrBody } }>().data.ocr).toMatchObject({
        status: 'ready',
        engine: expectedEngine,
      });
    }

    const beforeEdit = await disposable!.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.documents)
      .findOne({ _id: new Types.ObjectId(pngId!) });
    expect(beforeEdit?.ocr).toMatchObject({
      status: 'ready',
      rawText: 'Recognized image text from a deterministic fixture.',
      reviewedText: 'Recognized image text from a deterministic fixture.',
    });

    const editedText = 'Corrected student achievement text.\nSecond line.';
    const edit = await app!.inject({
      method: 'PATCH',
      url: `/api/v1/documents/${pngId!}/ocr`,
      headers: bearer(firstUser.accessToken),
      payload: { reviewedText: editedText },
    });
    expect(edit.statusCode).toBe(200);
    expect(edit.json()).toMatchObject({
      data: {
        ocr: {
          status: 'ready',
          rawText: 'Recognized image text from a deterministic fixture.',
          reviewedText: editedText,
        },
      },
    });

    const reload = await app!.inject({
      method: 'GET',
      url: `/api/v1/documents/${pngId!}/ocr`,
      headers: bearer(firstUser.accessToken),
    });
    expect(reload.json()).toMatchObject({ data: { ocr: { reviewedText: editedText } } });

    const restartedService = new DocumentService(
      disposable!.database,
      storage,
      ocrEngine,
    );
    await expect(
      restartedService.getOcr(new Types.ObjectId(firstUser.userId), pngId!),
    ).resolves.toMatchObject({ status: 'ready', reviewedText: editedText });
  });

  it('suggests from saved reviewed text while preserving raw OCR and existing document metadata', async () => {
    const id = uploadedIds[0]!;
    const before = await app!.inject({ method: 'GET', url: `/api/v1/documents/${id}`, headers: bearer(firstUser.accessToken) });
    const response = await app!.inject({
      method: 'PATCH', url: `/api/v1/documents/${id}/ocr`, headers: bearer(firstUser.accessToken),
      payload: { reviewedText: 'Certificate of Attendance\nparticipated in the seminar: Safe Digital Records\nDated 14/09/2026' },
    });
    expect(response.statusCode).toBe(200);
    const expected = { data: { ocr: {
      rawText: 'Embedded PDF text from a deterministic fixture.',
      metadataSuggestions: { categoryKey: 'certificates', folderKey: 'seminars', title: 'Safe Digital Records', documentDate: '2026-09-14' },
    } } };
    expect(response.json()).toMatchObject(expected);
    const get = await app!.inject({ method: 'GET', url: `/api/v1/documents/${id}/ocr`, headers: bearer(firstUser.accessToken) });
    expect(get.json()).toMatchObject(expected);
    const after = await app!.inject({ method: 'GET', url: `/api/v1/documents/${id}`, headers: bearer(firstUser.accessToken) });
    expect(after.json().data.document.title).toBe(before.json().data.document.title);
    expect(after.json().data.document.reflection).toBe(before.json().data.document.reflection);
  });

  it('rejects raw-text mutation and isolates every OCR operation by owner', async () => {
    const id = uploadedIds[0]!;
    expectError(
      await app!.inject({
        method: 'PATCH',
        url: `/api/v1/documents/${id}/ocr`,
        headers: bearer(firstUser.accessToken),
        payload: { reviewedText: 'allowed', rawText: 'forbidden' },
      }),
      400,
      'VALIDATION_ERROR',
    );

    for (const request of [
      { method: 'GET', url: `/api/v1/documents/${id}/ocr` },
      { method: 'POST', url: `/api/v1/documents/${id}/ocr`, payload: {} },
      {
        method: 'PATCH',
        url: `/api/v1/documents/${id}/ocr`,
        payload: { reviewedText: 'cross-user edit' },
      },
    ] as const) {
      expectError(
        await app!.inject({ ...request, headers: bearer(secondUser.accessToken) }),
        404,
        'DOCUMENT_NOT_FOUND',
      );
    }
  });

  it('prevents duplicate concurrent OCR for the same document', async () => {
    const id = uploadedIds[1]!;
    const blocked = ocrEngine.blockNext();
    const first = app!.inject({
      method: 'POST',
      url: `/api/v1/documents/${id}/ocr`,
      headers: bearer(firstUser.accessToken),
      payload: {},
    });
    await blocked.started;

    const duplicate = await app!.inject({
      method: 'POST',
      url: `/api/v1/documents/${id}/ocr`,
      headers: bearer(firstUser.accessToken),
      payload: {},
    });
    expectError(duplicate, 409, 'OCR_ALREADY_PROCESSING');

    blocked.release();
    expect((await first).statusCode).toBe(200);
  });

  it('returns the explicit scanned-PDF limitation and preserves the uploaded object', async () => {
    const id = uploadedIds[0]!;
    const raw = await disposable!.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.documents)
      .findOne({ _id: new Types.ObjectId(id) });
    const objectKey = String(raw?.objectKey);
    ocrEngine.nextFailure = new OcrEngineError('scanned-pdf-not-supported');

    expectError(
      await app!.inject({
        method: 'POST',
        url: `/api/v1/documents/${id}/ocr`,
        headers: bearer(firstUser.accessToken),
        payload: {},
      }),
      422,
      'SCANNED_PDF_OCR_NOT_SUPPORTED',
    );
    expect(await storage.exists(objectKey)).toBe(true);
    const status = await app!.inject({
      method: 'GET',
      url: `/api/v1/documents/${id}/ocr`,
      headers: bearer(firstUser.accessToken),
    });
    expect(status.json()).toMatchObject({ data: { ocr: { status: 'failed' } } });
  });

  it.each([
    ['protected-pdf', 422, 'PROTECTED_PDF_NOT_SUPPORTED'],
    ['timeout', 504, 'OCR_TIMEOUT'],
  ] as const)('maps %s OCR failures to a safe API error', async (reason, status, code) => {
    const id = uploadedIds[0]!;
    ocrEngine.nextFailure = new OcrEngineError(reason);
    expectError(
      await app!.inject({
        method: 'POST',
        url: `/api/v1/documents/${id}/ocr`,
        headers: bearer(firstUser.accessToken),
        payload: {},
      }),
      status,
      code,
    );
  });

  it('handles empty image results, validates endpoint bodies, and supports a successful retry', async () => {
    const id = uploadedIds[2]!;
    ocrEngine.nextRawText = '';
    expectError(
      await app!.inject({
        method: 'POST',
        url: `/api/v1/documents/${id}/ocr`,
        headers: bearer(firstUser.accessToken),
        payload: {},
      }),
      422,
      'OCR_NO_TEXT_FOUND',
    );

    for (const request of [
      { method: 'POST', payload: { unsupported: true } },
      { method: 'PATCH', payload: {} },
    ] as const) {
      expectError(
        await app!.inject({
          ...request,
          url: `/api/v1/documents/${id}/ocr`,
          headers: bearer(firstUser.accessToken),
        }),
        400,
        'VALIDATION_ERROR',
      );
    }

    const retry = await app!.inject({
      method: 'POST',
      url: `/api/v1/documents/${id}/ocr`,
      headers: bearer(firstUser.accessToken),
      payload: {},
    });
    expect(retry.statusCode).toBe(200);
    expect(retry.json()).toMatchObject({ data: { ocr: { status: 'ready' } } });
  });

  it('rejects a stored but unsupported document kind before reading its object', async () => {
    const id = new Types.ObjectId();
    await disposable!.connection.db!.collection(COLLECTION_NAMES.documents).insertOne({
      _id: id,
      ownerId: new Types.ObjectId(firstUser.userId),
      categoryKey: 'certificates',
      folderKey: 'seminars',
      title: 'Legacy DOCX',
      documentDate: new Date('2026-09-12T00:00:00.000Z'),
      originalFileName: 'legacy.docx',
      objectKey: `users/${firstUser.userId}/documents/legacy.docx`,
      mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      fileKind: 'docx',
      extension: 'docx',
      sizeBytes: 128,
      sha256: 'a'.repeat(64),
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    expectError(
      await app!.inject({
        method: 'POST',
        url: `/api/v1/documents/${id.toString()}/ocr`,
        headers: bearer(firstUser.accessToken),
        payload: {},
      }),
      415,
      'OCR_FILE_TYPE_NOT_SUPPORTED',
    );
    await disposable!.connection.db!
      .collection(COLLECTION_NAMES.documents)
      .deleteOne({ _id: id });
  });

  it('cleans storage after persistence failure and leaves no metadata after storage failure', async () => {
    const beforeCount = await disposable!.connection.db!
      .collection(COLLECTION_NAMES.documents)
      .countDocuments();
    const beforeKeys = storage.keys.size;

    storage.failNextPut = true;
    const storageFailure = multipartUpload(documentFields, {
      name: 'storage-failure.pdf',
      mimeType: 'application/pdf',
      contents: pdf,
    });
    expectError(
      await app!.inject({
        method: 'POST',
        url: '/api/v1/documents',
        headers: { ...bearer(firstUser.accessToken), ...storageFailure.headers },
        payload: storageFailure.payload,
      }),
      503,
      'DOCUMENT_UNAVAILABLE',
    );

    storage.corruptNextReturnedKey = true;
    const databaseFailure = multipartUpload(documentFields, {
      name: 'database-failure.pdf',
      mimeType: 'application/pdf',
      contents: pdf,
    });
    expectError(
      await app!.inject({
        method: 'POST',
        url: '/api/v1/documents',
        headers: { ...bearer(firstUser.accessToken), ...databaseFailure.headers },
        payload: databaseFailure.payload,
      }),
      503,
      'DOCUMENT_UNAVAILABLE',
    );

    expect(
      await disposable!.connection.db!.collection(COLLECTION_NAMES.documents).countDocuments(),
    ).toBe(beforeCount);
    expect(storage.keys.size).toBe(beforeKeys);
  });

  it('deletes metadata and the stored object together', async () => {
    const id = uploadedIds.pop()!;
    const raw = await disposable!.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.documents)
      .findOne({ _id: new Types.ObjectId(id) });
    const objectKey = String(raw?.objectKey);
    expect(await storage.exists(objectKey)).toBe(true);

    const deleted = await app!.inject({
      method: 'DELETE',
      url: `/api/v1/documents/${id}`,
      headers: bearer(firstUser.accessToken),
    });
    expect(deleted.statusCode).toBe(200);
    expect(deleted.json()).toMatchObject({ data: { status: 'deleted', documentId: id } });
    expect(await storage.exists(objectKey)).toBe(false);
    expect(
      await disposable!.connection.db!
        .collection(COLLECTION_NAMES.documents)
        .findOne({ _id: new Types.ObjectId(id) }),
    ).toBeNull();
  });

  it('rate-limits upload and OCR per authenticated user with standard errors', async () => {
    const upload = multipartUpload(
      { ...documentFields, title: 'Rate limit fixture' },
      { name: 'rate-limit.pdf', mimeType: 'application/pdf', contents: pdf },
    );
    const firstUpload = await limitedApp!.inject({
      method: 'POST',
      url: '/api/v1/documents',
      headers: { ...bearer(firstUser.accessToken), ...upload.headers },
      payload: upload.payload,
    });
    expect(firstUpload.statusCode).toBe(201);
    const documentId = firstUpload.json<{ readonly data: { readonly document: DocumentBody } }>()
      .data.document.id;

    const secondUpload = await limitedApp!.inject({
      method: 'POST',
      url: '/api/v1/documents',
      headers: { ...bearer(firstUser.accessToken), ...upload.headers },
      payload: upload.payload,
    });
    expectError(secondUpload, 429, 'RATE_LIMITED');
    expect(secondUpload.headers['retry-after']).toBeDefined();

    const firstOcr = await limitedApp!.inject({
      method: 'POST',
      url: `/api/v1/documents/${documentId}/ocr`,
      headers: bearer(firstUser.accessToken),
      payload: {},
    });
    expect(firstOcr.statusCode).toBe(200);

    const secondOcr = await limitedApp!.inject({
      method: 'POST',
      url: `/api/v1/documents/${documentId}/ocr`,
      headers: bearer(firstUser.accessToken),
      payload: {},
    });
    expectError(secondOcr, 429, 'RATE_LIMITED');
    expect(secondOcr.headers['retry-after']).toBeDefined();
    const preview = multipartUpload({}, { name: 'rate-limit.pdf', mimeType: 'application/pdf', contents: pdf });
    expectError(await limitedApp!.inject({
      method: 'POST', url: '/api/v1/documents/ocr-preview',
      headers: { ...bearer(firstUser.accessToken), ...preview.headers }, payload: preview.payload,
    }), 429, 'RATE_LIMITED');
  });
});
