import { Readable } from 'node:stream';
import { Types } from 'mongoose';
import { PDFDocument, StandardFonts } from 'pdf-lib';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { runMigrations } from '../../src/database/migrations/migration-runner.js';
import { seedDatabase } from '../../src/database/seeds/seed-database.js';
import { LocalOcrEngine } from '../../src/infrastructure/ocr/local-ocr-engine.js';
import type { ObjectStorage, StoredObject } from '../../src/infrastructure/storage/object-storage.js';
import { AiMetadataService } from '../../src/modules/documents/ai-metadata.service.js';
import { CompiledDocumentService } from '../../src/modules/documents/compiled-document.service.js';
import {
  createDisposableMongoDatabase,
  type DisposableMongoDatabase,
} from '../helpers/disposable-mongodb.js';

class MemoryStorage implements ObjectStorage {
  readonly objects = new Map<string, Buffer>();

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
    this.objects.delete(key);
  }

  async exists(key: string): Promise<boolean> {
    return this.objects.has(key);
  }

  async healthCheck() {
    return { status: 'up' as const };
  }
}

describe('Compiled document analysis service', () => {
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
    await disposable.stop();
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

  it('rejects PDFs with insufficient digital text with COMPILED_INSUFFICIENT_TEXT', async () => {
    const doc = await PDFDocument.create();
    doc.addPage([600, 400]); // Blank page
    const emptyPdf = Buffer.from(await doc.save());

    const service = new CompiledDocumentService(
      disposable.database,
      storage,
      ocrEngine,
    );

    await expect(
      service.analyze(ownerId, {
        contents: emptyPdf,
        mimeType: 'application/pdf',
        originalFileName: 'scanned_portfolio.pdf',
      }),
    ).rejects.toMatchObject({
      code: 'COMPILED_INSUFFICIENT_TEXT',
      statusCode: 422,
    });
  });

  it('produces multiple proposed logical documents via heuristic boundary detection when AI is not configured', async () => {
    const pdfBytes = await createMultiDocPdf();
    const service = new CompiledDocumentService(
      disposable.database,
      storage,
      ocrEngine,
    );

    const result = await service.analyze(ownerId, {
      contents: pdfBytes,
      mimeType: 'application/pdf',
      originalFileName: 'compiled_portfolio.pdf',
    });

    expect(result.sessionId).toMatch(/^csess_/);
    expect(result.totalPages).toBe(3);
    expect(result.originalFileName).toBe('compiled_portfolio.pdf');

    // Should detect the 3 distinct document sections
    expect(result.documents.length).toBe(3);

    // Document 1: CV
    expect(result.documents[0]?.startPage).toBe(1);
    expect(result.documents[0]?.endPage).toBe(1);
    expect(result.documents[0]?.categoryKey).toBe('curriculum-vitae');

    // Document 2: TOR
    expect(result.documents[1]?.startPage).toBe(2);
    expect(result.documents[1]?.endPage).toBe(2);
    expect(result.documents[1]?.categoryKey).toBe('scholastic-record');

    // Document 3: Certificate
    expect(result.documents[2]?.startPage).toBe(3);
    expect(result.documents[2]?.endPage).toBe(3);
    expect(result.documents[2]?.categoryKey).toBe('certificates');

    // Temporary PDF was stored in storage
    const tempKey = `users/${ownerId.toString()}/temp-compiled/${result.sessionId}.pdf`;
    expect(await storage.exists(tempKey)).toBe(true);
  });

  it('validates and accepts valid AI separation proposals', async () => {
    const pdfBytes = await createMultiDocPdf();

    const mockAiProvider = {
      model: 'gemini-2.5-flash',
      recommend: async () => ({}),
      separateCompiled: async () => ({
        documents: [
          {
            startPage: 1,
            endPage: 2,
            categoryKey: 'curriculum-vitae',
            folderKey: 'resume',
            title: 'Curriculum Vitae',
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
    };

    const metadataService = new AiMetadataService(mockAiProvider);
    const service = new CompiledDocumentService(
      disposable.database,
      storage,
      ocrEngine,
      metadataService,
    );

    const result = await service.analyze(ownerId, {
      contents: pdfBytes,
      mimeType: 'application/pdf',
      originalFileName: 'compiled_portfolio.pdf',
    });

    expect(result.documents.length).toBe(2);
    expect(result.documents[0]?.categoryKey).toBe('curriculum-vitae');
    expect(result.documents[0]?.startPage).toBe(1);
    expect(result.documents[0]?.endPage).toBe(2);
    expect(result.documents[1]?.categoryKey).toBe('certificates');
    expect(result.documents[1]?.startPage).toBe(3);
    expect(result.documents[1]?.endPage).toBe(3);
  });

  it('rejects out-of-range, overlapping, or invalid category AI output and falls back safely', async () => {
    const pdfBytes = await createMultiDocPdf();

    const mockAiProvider = {
      model: 'gemini-2.5-flash',
      recommend: async () => ({}),
      separateCompiled: async () => ({
        documents: [
          {
            startPage: 1,
            endPage: 99, // Out of range! (total pages is 3)
            categoryKey: 'non-existent-category',
            folderKey: 'fake-folder',
            title: 'Invalid Doc',
            documentDate: 'bad-date',
            confidence: 0.5,
          },
        ],
      }),
    };

    const metadataService = new AiMetadataService(mockAiProvider);
    const service = new CompiledDocumentService(
      disposable.database,
      storage,
      ocrEngine,
      metadataService,
    );

    const result = await service.analyze(ownerId, {
      contents: pdfBytes,
      mimeType: 'application/pdf',
      originalFileName: 'compiled_portfolio.pdf',
    });

    // Invalid AI proposals should be rejected and heuristic fallback used
    expect(result.documents.length).toBeGreaterThanOrEqual(1);
    expect(result.documents.every((d) => d.endPage <= 3)).toBe(true);
    expect(result.documents.every((d) => ['curriculum-vitae', 'scholastic-record', 'certificates', 'accomplishments'].includes(d.categoryKey))).toBe(true);
  });
});
