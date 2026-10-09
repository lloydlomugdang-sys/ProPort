import { Readable } from 'node:stream';
import { Types } from 'mongoose';
import { PDFDocument, StandardFonts } from 'pdf-lib';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { runMigrations } from '../../src/database/migrations/migration-runner.js';
import { seedDatabase } from '../../src/database/seeds/seed-database.js';
import { LocalOcrEngine } from '../../src/infrastructure/ocr/local-ocr-engine.js';
import type { ObjectStorage, StoredObject } from '../../src/infrastructure/storage/object-storage.js';
import { CompiledDocumentService } from '../../src/modules/documents/compiled-document.service.js';
import {
  createDisposableMongoDatabase,
  type DisposableMongoDatabase,
} from '../helpers/disposable-mongodb.js';

class MemoryStorage implements ObjectStorage {
  readonly objects = new Map<string, Buffer>();
  readonly deletedKeys: string[] = [];

  async put(key: string, contents: Readable): Promise<StoredObject> {
    const chunks: Buffer[] = [];
    for await (const chunk of contents) {
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    }
    const buf = Buffer.concat(chunks);
    this.objects.set(key, buf);
    return { key, sizeBytes: buf.length };
  }

  async get(key: string): Promise<Readable> {
    const buf = this.objects.get(key);
    if (!buf) throw new Error(`Not found: ${key}`);
    return Readable.from([buf]);
  }

  async delete(key: string): Promise<void> {
    this.deletedKeys.push(key);
    this.objects.delete(key);
  }

  async exists(key: string): Promise<boolean> {
    return this.objects.has(key);
  }

  async healthCheck() {
    return { status: 'up' as const };
  }
}

describe('Compiled document split service', () => {
  let disposable: DisposableMongoDatabase;
  let storage: MemoryStorage;
  let ocrEngine: LocalOcrEngine;
  const ownerId = new Types.ObjectId();

  beforeAll(async () => {
    disposable = await createDisposableMongoDatabase();
    await runMigrations(disposable.connection.db!);
    await seedDatabase(disposable.connection);
    storage = new MemoryStorage();
    ocrEngine = new LocalOcrEngine();
  });

  afterAll(async () => {
    await disposable?.stop();
  });

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

  it('splits compiled PDF into multiple documents with correct page counts and metadata', async () => {
    const pdfBytes = await createMultiDocPdf();
    const service = new CompiledDocumentService(
      disposable.database,
      storage,
      ocrEngine,
    );

    const analyzed = await service.analyze(ownerId, {
      contents: pdfBytes,
      mimeType: 'application/pdf',
      originalFileName: 'compiled_portfolio.pdf',
    });

    const tempKey = `users/${ownerId.toString()}/temp-compiled/${analyzed.sessionId}.pdf`;
    expect(await storage.exists(tempKey)).toBe(true);

    const splitResult = await service.split(ownerId, {
      sessionId: analyzed.sessionId,
      idempotencyKey: 'split-key-1',
      segments: [
        {
          startPage: 1,
          endPage: 2,
          categoryKey: 'curriculum-vitae',
          folderKey: 'curriculum-vitae',
          title: 'My Curriculum Vitae and Transcript',
          documentDate: '2024-01-01',
          description: 'CV and grades combined',
        },
        {
          startPage: 3,
          endPage: 3,
          categoryKey: 'certificates',
          folderKey: 'seminars',
          title: 'Flutter Seminar Certificate',
          documentDate: '2024-05-15',
        },
      ],
    });

    expect(splitResult.documents.length).toBe(2);

    const doc1 = splitResult.documents[0]!;
    expect(doc1.title).toBe('My Curriculum Vitae and Transcript');
    expect(doc1.categoryKey).toBe('curriculum-vitae');
    expect(doc1.folderKey).toBe('curriculum-vitae');

    const doc2 = splitResult.documents[1]!;
    expect(doc2.title).toBe('Flutter Seminar Certificate');
    expect(doc2.categoryKey).toBe('certificates');
    expect(doc2.folderKey).toBe('seminars');

    // Verify sub-PDFs in storage and verify page counts
    const conn = disposable.connection;
    const docRecords = conn.collection('documents');

    const rec1 = await docRecords.findOne({ _id: new Types.ObjectId(doc1.id) });
    expect(rec1).not.toBeNull();
    expect(rec1?.ocr?.status).toBe('ready');
    expect(rec1?.ocr?.rawText).toContain('CURRICULUM VITAE');
    expect(rec1?.ocr?.rawText).toContain('TRANSCRIPT OF RECORDS');
    const bytes1 = storage.objects.get(rec1?.objectKey);
    expect(bytes1).toBeDefined();
    const pdf1 = await PDFDocument.load(bytes1!);
    expect(pdf1.getPageCount()).toBe(2);

    const rec2 = await docRecords.findOne({ _id: new Types.ObjectId(doc2.id) });
    expect(rec2).not.toBeNull();
    expect(rec2?.ocr?.status).toBe('ready');
    expect(rec2?.ocr?.rawText).toContain('CERTIFICATE OF PARTICIPATION');
    const bytes2 = storage.objects.get(rec2?.objectKey);
    expect(bytes2).toBeDefined();
    const pdf2 = await PDFDocument.load(bytes2!);
    expect(pdf2.getPageCount()).toBe(1);

    // Verify temporary PDF is cleaned up from storage
    expect(await storage.exists(tempKey)).toBe(false);
  });

  it('is idempotent when repeating split with the same idempotencyKey', async () => {
    const pdfBytes = await createMultiDocPdf();
    const service = new CompiledDocumentService(
      disposable.database,
      storage,
      ocrEngine,
    );

    const analyzed = await service.analyze(ownerId, {
      contents: pdfBytes,
      mimeType: 'application/pdf',
      originalFileName: 'compiled_portfolio_idempotent.pdf',
    });

    const splitInput = {
      sessionId: analyzed.sessionId,
      idempotencyKey: 'idempotent-split-key',
      segments: [
        {
          startPage: 1,
          endPage: 3,
          categoryKey: 'curriculum-vitae',
          folderKey: 'curriculum-vitae',
          title: 'CV Single',
          documentDate: '2024-01-01',
        },
      ],
    };

    const firstRun = await service.split(ownerId, splitInput);
    expect(firstRun.documents.length).toBe(1);

    const secondRun = await service.split(ownerId, splitInput);
    expect(secondRun.documents.length).toBe(1);
    expect(secondRun.documents[0]?.id).toBe(firstRun.documents[0]?.id);

    // Ensure only one document record was created in MongoDB
    const conn = disposable.connection;
    const docRecords = conn.collection('documents');
    const count = await docRecords.countDocuments({
      ownerId,
      title: 'CV Single',
    });
    expect(count).toBe(1);
  });

  it('performs compensating rollback if storage fails midway', async () => {
    const pdfBytes = await createMultiDocPdf();
    const service = new CompiledDocumentService(
      disposable.database,
      storage,
      ocrEngine,
    );

    const analyzed = await service.analyze(ownerId, {
      contents: pdfBytes,
      mimeType: 'application/pdf',
      originalFileName: 'compiled_portfolio_rollback.pdf',
    });

    // Make storage fail on the second document segment put
    let docPutCount = 0;
    const originalPut = storage.put.bind(storage);
    storage.put = async (key: string, contents: Readable) => {
      if (key.includes('/documents/')) {
        docPutCount++;
        if (docPutCount === 2) {
          throw new Error('Mid-split storage failure');
        }
      }
      return originalPut(key, contents);
    };

    const conn = disposable.connection;
    const docRecords = conn.collection('documents');
    const countBefore = await docRecords.countDocuments({ ownerId });

    await expect(
      service.split(ownerId, {
        sessionId: analyzed.sessionId,
        idempotencyKey: 'fail-split-key',
        segments: [
          {
            startPage: 1,
            endPage: 1,
            categoryKey: 'curriculum-vitae',
            folderKey: 'curriculum-vitae',
            title: 'Doc Segment 1',
            documentDate: '2024-01-01',
          },
          {
            startPage: 2,
            endPage: 3,
            categoryKey: 'certificates',
            folderKey: 'seminars',
            title: 'Doc Segment 2',
            documentDate: '2024-05-15',
          },
        ],
      }),
    ).rejects.toThrow();

    // Storage put restored
    storage.put = originalPut;

    // Database records should have been rolled back
    const countAfter = await docRecords.countDocuments({ ownerId });
    expect(countAfter).toBe(countBefore);

    // Segment 1's uploaded file was cleaned up from storage via rollback
    expect(storage.deletedKeys.length).toBeGreaterThan(0);
  });

  it('cancel deletes temporary PDF and session', async () => {
    const pdfBytes = await createMultiDocPdf();
    const service = new CompiledDocumentService(
      disposable.database,
      storage,
      ocrEngine,
    );

    const analyzed = await service.analyze(ownerId, {
      contents: pdfBytes,
      mimeType: 'application/pdf',
      originalFileName: 'compiled_portfolio_cancel.pdf',
    });

    const tempKey = `users/${ownerId.toString()}/temp-compiled/${analyzed.sessionId}.pdf`;
    expect(await storage.exists(tempKey)).toBe(true);

    const cancelResult = await service.cancel(ownerId, analyzed.sessionId);
    expect(cancelResult.cancelled).toBe(true);

    // Temp file removed from storage
    expect(await storage.exists(tempKey)).toBe(false);

    // Calling split after cancel throws 404
    await expect(
      service.split(ownerId, {
        sessionId: analyzed.sessionId,
        idempotencyKey: 'after-cancel-key',
        segments: [
          {
            startPage: 1,
            endPage: 1,
            categoryKey: 'curriculum-vitae',
            folderKey: 'curriculum-vitae',
            title: 'CV',
            documentDate: '2024-01-01',
          },
        ],
      }),
    ).rejects.toMatchObject({
      code: 'SESSION_NOT_FOUND',
      statusCode: 404,
    });
  });
});

