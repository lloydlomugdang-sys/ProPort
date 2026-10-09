import { Readable } from 'node:stream';
import { randomUUID } from 'node:crypto';
import { Types } from 'mongoose';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { PDFDocument } from 'pdf-lib';
import { createDisposableMongoDatabase, type DisposableMongoDatabase } from '../helpers/disposable-mongodb.js';
import { mixedPdf, certificateText, cvText, cvContinuationText } from '../helpers/mixed-pdf-fixtures.js';
import { runMigrations } from '../../src/database/migrations/migration-runner.js';
import { seedDatabase } from '../../src/database/seeds/seed-database.js';
import { CompiledDocumentService, hasCompleteCoverage, type CompiledAnalysisResult, type CompiledSplitInput } from '../../src/modules/documents/compiled-document.service.js';
import { AiMetadataService } from '../../src/modules/documents/ai-metadata.service.js';
import { LocalOcrEngine } from '../../src/infrastructure/ocr/local-ocr-engine.js';
import type { OcrEngine, OcrPageText } from '../../src/infrastructure/ocr/ocr-engine.js';
import type { ObjectStorage } from '../../src/infrastructure/storage/object-storage.js';
import { compiledSessionIndexesMigration } from '../../src/database/migrations/003-compiled-session-indexes.js';

class MemoryStorage implements ObjectStorage {
  objects = new Map<string, Buffer>();
  failDelete = false;
  failPut = false;
  beforePut: (() => Promise<void>) | undefined;
  async put(key: string, stream: Readable) {
    if (this.failPut) throw new Error('fake storage unavailable');
    if (key.includes('/documents/')) await this.beforePut?.();
    const chunks: Buffer[] = [];
    for await (const chunk of stream) chunks.push(Buffer.from(chunk));
    const bytes = Buffer.concat(chunks); this.objects.set(key, bytes);
    return { key, sizeBytes: bytes.length };
  }
  async get(key: string) { const value = this.objects.get(key); if (!value) throw new Error('not found'); return Readable.from([value]); }
  async delete(key: string) { if (this.failDelete) throw new Error('fake cleanup unavailable'); this.objects.delete(key); }
  async exists(key: string) { return this.objects.has(key); }
  async healthCheck() { return { status: 'up' as const }; }
}

describe('Phase A mixed PDFs with disposable MongoDB only', () => {
  let fixture: DisposableMongoDatabase;
  beforeAll(async () => {
    fixture = await createDisposableMongoDatabase();
    await runMigrations(fixture.connection.db!);
    await seedDatabase(fixture.connection);
  });
  afterAll(async () => { await fixture?.stop(); });

  const sourcePages = [certificateText, cvText, cvContinuationText, certificateText];
  async function setup(aiResult?: unknown, failedPage?: number) {
    const owner = new Types.ObjectId();
    const storage = new MemoryStorage();
    const pages: OcrPageText[] = sourcePages.map((text, index) => ({
      pageNumber: index + 1, text: failedPage === index + 1 ? '' : text,
      source: failedPage === index + 1 ? 'failed' : 'digital', status: failedPage === index + 1 ? 'unresolved' : 'ready',
    }));
    const ocr: OcrEngine = { async extract() { return { rawText: pages.map((page) => page.text).join('\n'), pages, totalPages: 4, engine: 'pdfjs' }; } };
    const ai = new AiMetadataService({ model: 'test-text-only', async recommend() { return {}; }, async separateCompiled() {
      if (aiResult instanceof Error) throw aiResult;
      return aiResult;
    } });
    const service = new CompiledDocumentService(fixture.database, storage, ocr, ai);
    const input = { contents: await mixedPdf(sourcePages.map((text) => ({ text }))), mimeType: 'application/pdf', originalFileName: 'mixed.pdf' };
    const analysis = await service.analyze(owner, input);
    return { owner, storage, ocr, service, input, analysis };
  }
  function splitInput(analysis: CompiledAnalysisResult): CompiledSplitInput {
    return { sessionId: analysis.sessionId, idempotencyKey: randomUUID(), segments: analysis.documents.map((proposal) => ({
      startPage: proposal.startPage, endPage: proposal.endPage, categoryKey: proposal.categoryKey, folderKey: proposal.folderKey,
      title: proposal.title, documentDate: '2024-05-15', reflection: 'My own reflection, unchanged.',
    })) };
  }

  it.each([[false, false], [true, true], [false, true], [true, false]])('detects and physically splits certificate/CV (%s / %s)', async (scannedCertificate, scannedCv) => {
    const owner = new Types.ObjectId(); const storage = new MemoryStorage();
    const service = new CompiledDocumentService(fixture.database, storage, new LocalOcrEngine());
    const analysis = await service.analyze(owner, { contents: await mixedPdf([
      { text: certificateText, scanned: scannedCertificate }, { text: cvText, scanned: scannedCv },
    ]), mimeType: 'application/pdf', originalFileName: 'mixed.pdf' });
    expect(analysis.detection).toBe('multiple');
    expect(analysis.documents.map((document) => document.folderKey)).toEqual(['seminars', 'curriculum-vitae']);
    const saved = await service.split(owner, splitInput(analysis));
    expect(saved.documents).toHaveLength(2);
    for (const document of saved.documents) {
      const row = await fixture.connection.collection('documents').findOne({ _id: new Types.ObjectId(document.id), ownerId: owner });
      const pdf = await PDFDocument.load(storage.objects.get(row!.objectKey as string)!);
      expect(pdf.getPageCount()).toBe(1);
      expect(row!.ocr.rawText).toBeTruthy();
      expect(row!.reflection).toBe('My own reflection, unchanged.');
    }
  });

  it('keeps repeated CV headers together and separate certificates independent', async () => {
    const { analysis } = await setup();
    expect(analysis.documents.map((document) => [document.startPage, document.endPage, document.folderKey]))
      .toEqual([[1, 1, 'seminars'], [2, 3, 'curriculum-vitae'], [4, 4, 'seminars']]);
    const owner = new Types.ObjectId();
    const service = new CompiledDocumentService(fixture.database, new MemoryStorage(), new LocalOcrEngine());
    const single = await service.analyze(owner, { contents: await mixedPdf([cvText, cvContinuationText, cvContinuationText].map((text) => ({ text }))), mimeType: 'application/pdf', originalFileName: 'cv.pdf' });
    expect(single.detection).toBe('single');
    expect(single.documents).toHaveLength(1);
    expect(single.documents[0]).toMatchObject({ startPage: 1, endPage: 3, folderKey: 'curriculum-vitae' });
  });

  it('retains failed pages explicitly and rejects splitting without discarding raw text', async () => {
    const { analysis, service, owner } = await setup(undefined, 2);
    expect(analysis.pages[1]).toMatchObject({ pageNumber: 2, source: 'failed', status: 'unresolved' });
    expect(analysis.detection).toBe('needs_review');
    expect(analysis.documents.find((document) => document.startPage === 2)).toMatchObject({ endPage: 2, categoryKey: '' });
    await expect(service.split(owner, splitInput(analysis))).rejects.toMatchObject({ code: 'COMPILED_UNRESOLVED_PAGES' });
    expect(analysis.pages[0]?.text).toBe(certificateText);
  });

  it.each(['missing', 'overlap', 'out-of-order', 'unknown-category', 'unknown-folder', 'out-of-bounds', 'failure'])('rejects unsafe AI segmentation (%s) and uses complete deterministic proposals', async (kind) => {
    const proposal = { startPage: 1, endPage: 4, categoryKey: 'curriculum-vitae', folderKey: 'curriculum-vitae', title: 'CV', confidence: 0.95, documentDate: null };
    const invalid = kind === 'failure' ? new Error('fake provider failure') : { documents:
      kind === 'missing' ? [{ ...proposal, endPage: 3 }] :
      kind === 'overlap' ? [{ ...proposal, endPage: 2 }, { ...proposal, startPage: 2 }] :
      kind === 'out-of-order' ? [{ ...proposal, startPage: 3 }, { ...proposal, endPage: 2 }] :
      kind === 'unknown-category' ? [{ ...proposal, categoryKey: 'invented' }] :
      kind === 'unknown-folder' ? [{ ...proposal, folderKey: 'resume' }] : [{ ...proposal, endPage: 5 }],
    };
    const { analysis } = await setup(invalid);
    expect(analysis.documents).toHaveLength(3);
    expect(hasCompleteCoverage(analysis.documents, 4)).toBe(true);
    expect(analysis.pages[0]?.text).toBe(certificateText);
  });

  it.each([
    [[1, 1], [3, 4]], [[1, 3], [3, 4]], [[3, 4], [1, 2]], [[1, 5]],
  ])('enforces coverage again on final user-submitted ranges %j', async (...ranges) => {
    const { analysis, service, owner } = await setup();
    const request = splitInput(analysis);
    const segments = ranges.map((range) => ({ ...request.segments[0]!, startPage: range[0]!, endPage: range[1]! }));
    await expect(service.split(owner, { ...request, segments })).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });
    expect(await fixture.connection.collection('documents').countDocuments({ ownerId: owner })).toBe(0);
  });

  it('replays the same receipt after a lost response/service restart and rejects changed payload or owner', async () => {
    const { analysis, service, owner, storage, ocr } = await setup();
    const request = splitInput(analysis);
    const first = await service.split(owner, request); // Response is assumed lost by client.
    const restarted = new CompiledDocumentService(fixture.database, storage, ocr);
    expect(await restarted.split(owner, request)).toEqual(first);
    await expect(restarted.split(owner, { ...request, segments: [{ ...request.segments[0]!, title: 'Changed' }, ...request.segments.slice(1)] })).rejects.toMatchObject({ code: 'SPLIT_REQUEST_CHANGED' });
    await expect(restarted.split(new Types.ObjectId(), request)).rejects.toMatchObject({ code: 'SESSION_NOT_FOUND' });
    expect(await fixture.connection.collection('documents').countDocuments({ ownerId: owner })).toBe(3);
  });

  it('does not resplit a completed legacy session that has no state field', async () => {
    const { analysis, service, owner } = await setup();
    const request = splitInput(analysis);
    await service.split(owner, request);
    await fixture.connection.collection('compiled_document_sessions').updateOne({ sessionId: analysis.sessionId }, { $unset: { state: '', requestHash: '' } });
    await expect(service.split(owner, { ...request, idempotencyKey: 'different-key' })).rejects.toMatchObject({ code: 'SESSION_ALREADY_SPLIT' });
    expect(await fixture.connection.collection('documents').countDocuments({ ownerId: owner })).toBe(3);
  });

  it('retains saved documents if the completion receipt acknowledgement is lost', async () => {
    const { analysis, service, owner } = await setup();
    const collection = fixture.connection.collection('compiled_document_sessions');
    const original = collection.updateOne.bind(collection);
    const spy = vi.spyOn(collection, 'updateOne').mockImplementation(async (...args) => {
      const result = await original(...args);
      const update = args[1] as { $set?: { state?: string } };
      if (update.$set?.state === 'complete') throw new Error('simulated lost database acknowledgement');
      return result;
    });
    const request = splitInput(analysis);
    try {
      await expect(service.split(owner, request)).rejects.toMatchObject({ code: 'SPLIT_RESULT_UNCONFIRMED' });
    } finally { spy.mockRestore(); }
    const retried = await service.split(owner, request);
    expect(retried.documents).toHaveLength(3);
    expect(await fixture.connection.collection('documents').countDocuments({ ownerId: owner })).toBe(3);
  });

  it('atomically claims concurrent split attempts across service instances', async () => {
    const { analysis, service, owner, storage, ocr } = await setup();
    let release!: () => void; let started!: () => void;
    const entered = new Promise<void>((resolve) => { started = resolve; });
    const gate = new Promise<void>((resolve) => { release = resolve; });
    storage.beforePut = async () => { started(); await gate; };
    const request = splitInput(analysis);
    const first = service.split(owner, request);
    await entered;
    try {
      const competing = new CompiledDocumentService(fixture.database, storage, ocr);
      await expect(competing.split(owner, request)).rejects.toMatchObject({ code: 'SPLIT_IN_PROGRESS' });
      await expect(competing.cancel(owner, analysis.sessionId)).rejects.toMatchObject({ code: 'SPLIT_IN_PROGRESS' });
    } finally { release(); }
    await first;
    expect(await fixture.connection.collection('documents').countDocuments({ ownerId: owner })).toBe(3);
  });

  it('rejects expired sessions before TTL cleanup and removes their source object', async () => {
    const { analysis, service, owner, storage } = await setup();
    await fixture.connection.collection('compiled_document_sessions').updateOne({ sessionId: analysis.sessionId }, { $set: { expiresAt: new Date(0) } });
    await expect(service.split(owner, splitInput(analysis))).rejects.toMatchObject({ code: 'SESSION_NOT_FOUND' });
    expect(storage.objects.size).toBe(0);
    expect(await fixture.connection.collection('compiled_document_sessions').countDocuments({ sessionId: analysis.sessionId })).toBe(0);
  });

  it.each([false, true])('keeps cleanup intent when cancellation cannot delete storage (expired: %s)', async (expired) => {
    const { analysis, service, owner, storage } = await setup(); storage.failDelete = true;
    if (expired) await fixture.connection.collection('compiled_document_sessions').updateOne({ sessionId: analysis.sessionId }, { $set: { expiresAt: new Date(0) } });
    await expect(service.cancel(owner, analysis.sessionId)).rejects.toMatchObject({ code: 'CLEANUP_PENDING' });
    expect(await fixture.connection.collection('compiled_document_sessions').countDocuments({ sessionId: analysis.sessionId })).toBe(1);
    storage.failDelete = false;
    await expect(service.cancel(owner, analysis.sessionId)).resolves.toEqual({ cancelled: true });
    expect(storage.objects.size).toBe(0);
  });

  it('cleans failed analysis intent and retires expired objects on the next owned analysis', async () => {
    const { analysis, service, owner, storage, input } = await setup();
    await fixture.connection.collection('compiled_document_sessions').updateOne({ sessionId: analysis.sessionId }, { $set: { expiresAt: new Date(0) } });
    storage.failPut = true;
    await expect(service.analyze(owner, input)).rejects.toThrow();
    expect(storage.objects.size).toBe(0);
    expect(await fixture.connection.collection('compiled_document_sessions').countDocuments({ ownerId: owner.toString() })).toBe(0);
  });

  it('migration removes only the known legacy TTL and registers explicit session indexes', async () => {
    const collection = fixture.connection.db!.collection('compiled_document_sessions');
    await collection.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0, name: 'expiresAt_1' });
    await compiledSessionIndexesMigration.up(fixture.connection.db!);
    const indexes = await collection.listIndexes().toArray();
    expect(indexes.some((index) => index.expireAfterSeconds !== undefined)).toBe(false);
    expect(indexes.find((index) => index.name === 'uniq_compiled_session_id')?.unique).toBe(true);
    expect(indexes.some((index) => index.name === 'idx_compiled_owner_expiry')).toBe(true);
  });
});
