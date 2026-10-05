import { randomUUID, createHash } from 'node:crypto';
import { extname, basename } from 'node:path';
import { Readable } from 'node:stream';
import type { Types } from 'mongoose';
import { PDFDocument } from 'pdf-lib';
import { AppError } from '../../common/errors/app-error.js';
import type { DatabaseConnection } from '../../infrastructure/database/database-connection.js';
import { createRepositories } from '../../database/repositories/index.js';
import type { ObjectStorage } from '../../infrastructure/storage/object-storage.js';
import { OcrEngineError, type OcrEngine } from '../../infrastructure/ocr/ocr-engine.js';
import type { AiMetadataService } from './ai-metadata.service.js';
import { suggestDocumentMetadata } from './metadata-suggestion.service.js';
import {
  MAX_DOCUMENT_FILE_SIZE_BYTES,
  type DocumentFileInput,
  type PublicDocument,
  type PublicDocumentCategory,
} from './document.service.js';

export interface CompiledDocumentProposal {
  readonly startPage: number;
  readonly endPage: number;
  readonly categoryKey: string;
  readonly folderKey: string;
  readonly title: string;
  readonly documentDate: string | null;
  readonly confidence: number;
}

export interface CompiledAnalysisResult {
  readonly sessionId: string;
  readonly originalFileName: string;
  readonly totalPages: number;
  readonly documents: readonly CompiledDocumentProposal[];
}

export interface CompiledSplitSegment {
  readonly startPage: number;
  readonly endPage: number;
  readonly categoryKey: string;
  readonly folderKey: string;
  readonly title: string;
  readonly documentDate: string;
  readonly description?: string;
  readonly reflection?: string;
}

export interface CompiledSplitInput {
  readonly sessionId: string;
  readonly idempotencyKey: string;
  readonly segments: readonly CompiledSplitSegment[];
}

interface CompiledSessionRecord {
  readonly sessionId: string;
  readonly ownerId: string;
  readonly tempObjectKey: string;
  readonly originalFileName: string;
  readonly totalPages: number;
  readonly pageTexts: readonly { readonly pageNumber: number; readonly text: string }[];
  readonly proposals: readonly CompiledDocumentProposal[];
  readonly createdAt: Date;
  readonly expiresAt: Date;
  completedDocuments?: readonly PublicDocument[];
  completedIdempotencyKey?: string;
}

function validationError(field: string, message: string): AppError {
  return new AppError(400, 'VALIDATION_ERROR', 'The request is invalid.', {
    [field]: [message],
  });
}

function sanitizedFileName(value: string): string {
  const leaf = basename(value.replaceAll('\\', '/'))
    .normalize('NFKC')
    .replace(/[<>:"/\\|?*]/g, '_')
    .split('')
    .map((c) => (c.charCodeAt(0) < 32 ? '_' : c))
    .join('')
    .trim();
  if (leaf.length === 0 || leaf === '.' || leaf === '..') {
    return 'document.pdf';
  }
  if (leaf.length <= 255) return leaf;
  const extension = extname(leaf);
  return `${leaf.slice(0, 255 - extension.length)}${extension}`;
}

function documentDate(value: string): Date {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw validationError('documentDate', 'must use YYYY-MM-DD format');
  }
  const parsed = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    throw validationError('documentDate', 'must be a valid calendar date');
  }
  return parsed;
}

async function readableToBoundedBuffer(stream: Readable, maxBytes: number): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let total = 0;
  for await (const chunk of stream) {
    const value: unknown = chunk;
    const buffer = Buffer.isBuffer(value)
      ? value
      : typeof value === 'string' || value instanceof Uint8Array
        ? Buffer.from(value)
        : null;
    if (buffer === null) {
      throw new AppError(503, 'STORAGE_UNAVAILABLE', 'Unable to read document stream.');
    }
    total += buffer.length;
    if (total > maxBytes) {
      throw new AppError(413, 'FILE_TOO_LARGE', 'The document is too large to process.');
    }
    chunks.push(buffer);
  }
  return Buffer.concat(chunks, total);
}

export class CompiledDocumentService {
  private readonly inMemorySessions = new Map<string, CompiledSessionRecord>();
  private indexInitialized = false;

  constructor(
    private readonly database: DatabaseConnection,
    private readonly storage: ObjectStorage,
    private readonly ocrEngine: OcrEngine,
    private readonly metadata?: AiMetadataService,
  ) {}

  private repositories() {
    const conn = this.database.mongooseConnection;
    if (!conn) {
      throw new AppError(503, 'DATABASE_UNAVAILABLE', 'Database connection is unavailable.');
    }
    return createRepositories(conn);
  }

  private async getSession(sessionId: string, ownerId: Types.ObjectId): Promise<CompiledSessionRecord | null> {
    const conn = this.database.mongooseConnection;
    if (conn) {
      const col = conn.collection<CompiledSessionRecord>('compiled_document_sessions');
      const found = await col.findOne({ sessionId, ownerId: ownerId.toString() });
      if (found) return found;
    }
    const mem = this.inMemorySessions.get(sessionId);
    if (mem && mem.ownerId === ownerId.toString() && mem.expiresAt > new Date()) {
      return mem;
    }
    return null;
  }

  private async saveSession(session: CompiledSessionRecord): Promise<void> {
    const conn = this.database.mongooseConnection;
    if (conn) {
      const col = conn.collection<CompiledSessionRecord>('compiled_document_sessions');
      if (!this.indexInitialized) {
        col.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 }).catch(() => undefined);
        this.indexInitialized = true;
      }
      await col.updateOne(
        { sessionId: session.sessionId },
        { $set: session },
        { upsert: true },
      );
    }
    this.inMemorySessions.set(session.sessionId, session);
  }

  private async deleteSession(sessionId: string): Promise<void> {
    const conn = this.database.mongooseConnection;
    if (conn) {
      const col = conn.collection<CompiledSessionRecord>('compiled_document_sessions');
      await col.deleteOne({ sessionId }).catch(() => undefined);
    }
    this.inMemorySessions.delete(sessionId);
  }

  async analyze(
    ownerId: Types.ObjectId,
    file: DocumentFileInput,
    _requestId?: string,
  ): Promise<CompiledAnalysisResult> {
    if (file.contents.length === 0) {
      throw validationError('file', 'must not be empty');
    }
    if (file.contents.length > MAX_DOCUMENT_FILE_SIZE_BYTES) {
      throw new AppError(413, 'FILE_TOO_LARGE', 'The file exceeds the 15 MB upload limit.');
    }
    // Validate PDF magic bytes: %PDF- (0x25 0x50 0x44 0x46 0x2D)
    if (
      file.contents.length < 5 ||
      file.contents[0] !== 0x25 ||
      file.contents[1] !== 0x50 ||
      file.contents[2] !== 0x44 ||
      file.contents[3] !== 0x46 ||
      file.contents[4] !== 0x2d
    ) {
      throw new AppError(415, 'UNSUPPORTED_FILE_TYPE', 'Compiled document separation supports PDF files only.');
    }

    // Page-aware extraction using pdfjs-dist
    let extracted;
    try {
      extracted = await this.ocrEngine.extract({
        contents: file.contents,
        mimeType: 'application/pdf',
        fileKind: 'pdf',
      });
    } catch (error) {
      if (error instanceof OcrEngineError) {
        if (error.reason === 'scanned-pdf-not-supported') {
          throw new AppError(
            422,
            'COMPILED_INSUFFICIENT_TEXT',
            'The uploaded PDF does not contain sufficient digital text for automated separation. Please upload scanned documents individually.',
          );
        }
        if (error.reason === 'protected-pdf') {
          throw new AppError(422, 'DOCUMENT_PROTECTED_PDF', 'Password-protected PDF documents are not supported.');
        }
        if (error.reason === 'invalid-pdf') {
          throw new AppError(400, 'INVALID_PDF', 'The provided PDF file is invalid or corrupted.');
        }
      }
      throw error;
    }

    const totalPages = extracted.totalPages ?? extracted.pages?.length ?? 1;
    const pages = extracted.pages && extracted.pages.length > 0
      ? extracted.pages
      : [{ pageNumber: 1, text: extracted.rawText }];

    // Detect scanned/insufficient text
    const totalChars = pages.reduce((sum, p) => sum + p.text.trim().length, 0);
    const avgChars = totalPages > 0 ? totalChars / totalPages : 0;
    if (totalChars < 50 || avgChars < 15) {
      throw new AppError(
        422,
        'COMPILED_INSUFFICIENT_TEXT',
        'The uploaded PDF does not contain sufficient digital text for automated separation. Please upload scanned documents individually.',
      );
    }

    // Store temporary compiled PDF in R2
    const sessionId = `csess_${randomUUID()}`;
    const tempObjectKey = `users/${ownerId.toString()}/temp-compiled/${sessionId}.pdf`;
    await this.storage.put(tempObjectKey, Readable.from([file.contents]));

    // Fetch active categories
    const repositories = this.repositories();
    const categories = (await repositories.documentCategories.listActive()).map((cat) => ({
      key: cat.key,
      name: cat.name,
      folders: cat.folders.filter((f) => f.active).map((f) => ({ key: f.key, name: f.name })),
    }));

    // AI Separation & Validation
    let proposals: CompiledDocumentProposal[] = [];
    if (this.metadata?.separateCompiled) {
      try {
        const rawAiResult = await this.metadata.separateCompiled(pages, categories);
        if (rawAiResult) {
          proposals = this.validateAndNormalizeProposals(rawAiResult, totalPages, categories, pages);
        }
      } catch {
        // Fallback to deterministic rules
        proposals = [];
      }
    }

    if (proposals.length === 0) {
      proposals = this.heuristicSplit(pages, totalPages, categories);
    }

    const session: CompiledSessionRecord = {
      sessionId,
      ownerId: ownerId.toString(),
      tempObjectKey,
      originalFileName: sanitizedFileName(file.originalFileName),
      totalPages,
      pageTexts: pages.map((p) => ({ pageNumber: p.pageNumber, text: p.text })),
      proposals,
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + 60 * 60 * 1000), // 1 hour
    };

    await this.saveSession(session);

    return {
      sessionId,
      originalFileName: session.originalFileName,
      totalPages,
      documents: proposals,
    };
  }

  async split(
    ownerId: Types.ObjectId,
    input: CompiledSplitInput,
  ): Promise<{ documents: PublicDocument[] }> {
    if (!input.sessionId) throw validationError('sessionId', 'is required');
    if (!input.idempotencyKey) throw validationError('idempotencyKey', 'is required');
    if (!Array.isArray(input.segments) || input.segments.length === 0) {
      throw validationError('segments', 'must contain at least one document segment');
    }

    const session = await this.getSession(input.sessionId, ownerId);
    if (!session) {
      throw new AppError(404, 'SESSION_NOT_FOUND', 'The compiled document session was not found or has expired.');
    }

    // Idempotency: return previously completed documents
    if (session.completedIdempotencyKey === input.idempotencyKey && session.completedDocuments) {
      return { documents: [...session.completedDocuments] };
    }

    const repositories = this.repositories();
    const categories = await repositories.documentCategories.listActive();

    // Validate segments
    for (let i = 0; i < input.segments.length; i++) {
      const seg = input.segments[i];
      if (!seg) continue;
      if (
        !Number.isInteger(seg.startPage) ||
        !Number.isInteger(seg.endPage) ||
        seg.startPage < 1 ||
        seg.endPage > session.totalPages ||
        seg.startPage > seg.endPage
      ) {
        throw validationError(
          `segments[${i}]`,
          `invalid page range ${seg.startPage}-${seg.endPage} for document with ${session.totalPages} pages`,
        );
      }
      const cat = categories.find((c) => c.key === seg.categoryKey && c.active);
      if (!cat) {
        throw validationError(`segments[${i}].categoryKey`, 'must identify an active document category');
      }
      if (!cat.folders.some((f) => f.key === seg.folderKey && f.active)) {
        throw validationError(`segments[${i}].folderKey`, 'must belong to the selected document category');
      }
      if (!seg.title || typeof seg.title !== 'string' || seg.title.trim().length === 0) {
        throw validationError(`segments[${i}].title`, 'is required');
      }
      if (seg.title.trim().length > 250) {
        throw validationError(`segments[${i}].title`, 'must contain at most 250 characters');
      }
    }

    // Retrieve temporary compiled PDF
    let pdfBuffer: Buffer;
    try {
      const stream = await this.storage.get(session.tempObjectKey);
      pdfBuffer = await readableToBoundedBuffer(stream, MAX_DOCUMENT_FILE_SIZE_BYTES);
    } catch (error) {
      throw new AppError(503, 'STORAGE_UNAVAILABLE', 'Unable to retrieve compiled document from storage.', undefined, undefined, { cause: error });
    }

    let srcDoc: PDFDocument;
    try {
      srcDoc = await PDFDocument.load(pdfBuffer);
    } catch (error) {
      throw new AppError(422, 'INVALID_PDF', 'Unable to parse PDF for document separation.', undefined, undefined, { cause: error });
    }

    const createdDocs: PublicDocument[] = [];
    const createdObjectKeys: string[] = [];
    const createdDocIds: Types.ObjectId[] = [];

    try {
      for (let i = 0; i < input.segments.length; i++) {
        const seg = input.segments[i]!;
        const subDoc = await PDFDocument.create();
        const pageIndices: number[] = [];
        for (let p = seg.startPage - 1; p < seg.endPage; p++) {
          pageIndices.push(p);
        }
        const copiedPages = await subDoc.copyPages(srcDoc, pageIndices);
        for (const page of copiedPages) {
          subDoc.addPage(page);
        }
        const subPdfBytes = Buffer.from(await subDoc.save());

        const objectKey = `users/${ownerId.toString()}/documents/${randomUUID()}.pdf`;
        const stored = await this.storage.put(objectKey, Readable.from([subPdfBytes]));
        createdObjectKeys.push(stored.key);

        // Pre-extracted text for this segment's page range
        const segmentPageTexts = session.pageTexts
          .filter((p) => p.pageNumber >= seg.startPage && p.pageNumber <= seg.endPage)
          .map((p) => p.text)
          .filter((t) => t.trim().length > 0);
        const segmentRawText = segmentPageTexts.join('\n\n');

        const cleanTitle = sanitizedFileName(seg.title).replace(/\.pdf$/i, '');
        const originalFileName = `${cleanTitle}.pdf`;
        const sha256 = createHash('sha256').update(subPdfBytes).digest('hex');

        const created = await repositories.documents.create({
          ownerId,
          categoryKey: seg.categoryKey,
          folderKey: seg.folderKey,
          title: seg.title.trim(),
          documentDate: documentDate(seg.documentDate),
          ...(seg.description && seg.description.trim().length > 0 ? { description: seg.description.trim() } : {}),
          ...(seg.reflection && seg.reflection.trim().length > 0 ? { reflection: seg.reflection.trim() } : {}),
          originalFileName,
          objectKey: stored.key,
          mimeType: 'application/pdf',
          fileKind: 'pdf',
          extension: 'pdf',
          sizeBytes: subPdfBytes.length,
          sha256,
          attachments: [
            {
              id: '1',
              originalFileName,
              objectKey: stored.key,
              mimeType: 'application/pdf',
              fileKind: 'pdf',
              extension: 'pdf',
              sizeBytes: subPdfBytes.length,
              sha256,
              order: 0,
            },
          ],
          ...(segmentRawText.length > 0
            ? {
                ocr: {
                  status: 'ready' as const,
                  rawText: segmentRawText,
                  reviewedText: segmentRawText,
                  engine: 'pdfjs' as const,
                  processedAt: new Date(),
                  updatedAt: new Date(),
                },
              }
            : {}),
        });

        createdDocIds.push(created._id);
        createdDocs.push({
          id: created._id.toString(),
          categoryKey: created.categoryKey,
          folderKey: created.folderKey,
          title: created.title,
          documentDate: created.documentDate.toISOString(),
          ...(created.description ? { description: created.description } : {}),
          ...(created.reflection ? { reflection: created.reflection } : {}),
          originalFileName: created.originalFileName,
          mimeType: created.mimeType,
          fileKind: created.fileKind,
          extension: created.extension,
          sizeBytes: created.sizeBytes,
          ...(created.attachments
            ? {
                attachments: created.attachments.map((a) => ({
                  id: a.id,
                  originalFileName: a.originalFileName,
                  mimeType: a.mimeType,
                  fileKind: a.fileKind,
                  extension: a.extension,
                  sizeBytes: a.sizeBytes,
                  order: a.order,
                })),
              }
            : {}),
          createdAt: created.createdAt.toISOString(),
          updatedAt: created.updatedAt.toISOString(),
        });
      }

      // Record completed documents for idempotency
      await this.saveSession({
        ...session,
        completedIdempotencyKey: input.idempotencyKey,
        completedDocuments: createdDocs,
      });

      // Cleanup temporary compiled PDF
      await this.storage.delete(session.tempObjectKey).catch(() => undefined);

      return { documents: createdDocs };
    } catch (error) {
      // Compensating rollback
      for (const key of createdObjectKeys) {
        await this.storage.delete(key).catch(() => undefined);
      }
      for (const docId of createdDocIds) {
        await repositories.documents.deleteByIdForOwner(ownerId, docId).catch(() => undefined);
      }
      if (error instanceof AppError) throw error;
      throw new AppError(503, 'SPLIT_FAILED', 'Failed to split and create document records. All partial files were cleaned up.', undefined, undefined, { cause: error });
    }
  }

  async cancel(ownerId: Types.ObjectId, sessionId: string): Promise<{ cancelled: boolean }> {
    const session = await this.getSession(sessionId, ownerId);
    if (session) {
      await this.storage.delete(session.tempObjectKey).catch(() => undefined);
      await this.deleteSession(sessionId).catch(() => undefined);
    }
    return { cancelled: true };
  }

  private validateAndNormalizeProposals(
    raw: unknown,
    totalPages: number,
    categories: readonly PublicDocumentCategory[],
    pages: readonly { readonly pageNumber: number; readonly text: string }[],
  ): CompiledDocumentProposal[] {
    if (typeof raw !== 'object' || raw === null || !('documents' in raw) || !Array.isArray(raw.documents)) {
      return [];
    }

    const proposals: CompiledDocumentProposal[] = [];
    let lastEndPage = 0;

    for (const doc of raw.documents) {
      if (typeof doc !== 'object' || doc === null) continue;
      const startPage = Number(doc.startPage);
      const endPage = Number(doc.endPage);
      if (!Number.isInteger(startPage) || !Number.isInteger(endPage)) continue;
      if (startPage < 1 || endPage > totalPages || startPage > endPage) continue;
      // Ranges must be non-overlapping and contiguous/ascending
      if (startPage <= lastEndPage) continue;

      const catKey = typeof doc.categoryKey === 'string' ? doc.categoryKey.trim() : '';
      const cat = categories.find((c) => c.key === catKey);
      if (!cat) continue;

      let folderKey = typeof doc.folderKey === 'string' ? doc.folderKey.trim() : '';
      if (!cat.folders.some((f) => f.key === folderKey)) {
        folderKey = cat.folders[0]?.key ?? '';
      }

      let title = typeof doc.title === 'string' ? doc.title.trim().slice(0, 250) : '';
      if (!title) {
        title = cat.name;
      }

      const date: string | null =
        typeof doc.documentDate === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(doc.documentDate)
          ? doc.documentDate
          : suggestDocumentMetadata(
              {
                rawText: pages
                  .filter((p) => p.pageNumber >= startPage && p.pageNumber <= endPage)
                  .map((p) => p.text)
                  .join('\n'),
              },
              [],
            ).documentDate ?? null;

      const conf = typeof doc.confidence === 'number' && doc.confidence >= 0 && doc.confidence <= 1
        ? doc.confidence
        : 0.85;

      proposals.push({
        startPage,
        endPage,
        categoryKey: cat.key,
        folderKey,
        title,
        documentDate: date,
        confidence: conf,
      });

      lastEndPage = endPage;
    }

    return proposals;
  }

  private heuristicSplit(
    pages: readonly { readonly pageNumber: number; readonly text: string }[],
    totalPages: number,
    categories: readonly PublicDocumentCategory[],
  ): CompiledDocumentProposal[] {
    const boundaryStarts: { page: number; categoryKey: string; folderKey: string; defaultTitle: string }[] = [];

    const getCat = (key: string) => categories.find((c) => c.key === key);
    const getFolder = (catKey: string, folderKey: string) => {
      const c = getCat(catKey);
      if (!c) return { catKey: categories[0]?.key ?? 'accomplishments', folderKey: categories[0]?.folders[0]?.key ?? 'projects' };
      const f = c.folders.find((fol) => fol.key === folderKey) ?? c.folders[0];
      return { catKey: c.key, folderKey: f?.key ?? folderKey };
    };

    for (const page of pages) {
      const text = page.text.toLowerCase();
      let match: { categoryKey: string; folderKey: string; defaultTitle: string } | null = null;

      if (/(?:curriculum\s+vitae|\bresume\b|\bbio-data\b)/.test(text)) {
        const f = getFolder('curriculum-vitae', 'resume');
        match = { categoryKey: f.catKey, folderKey: f.folderKey, defaultTitle: 'Curriculum Vitae' };
      } else if (/(?:transcript\s+of\s+records|\bofficial\s+transcript\b|\bcertificate\s+of\s+grades\b|\bunofficial\s+tor\b)/.test(text)) {
        const f = getFolder('scholastic-record', 'unofficial-tor-with-reflections');
        match = { categoryKey: f.catKey, folderKey: f.folderKey, defaultTitle: 'Transcript of Records' };
      } else if (/(?:certificate\s+of\s+(?:completion|participation|attendance|recognition|appreciation)|\bhas\s+successfully\s+completed\b|\bseminar\b|\bwebinar\b|\bworkshop\b)/.test(text)) {
        const isTraining = /(?:training\s+course|\bbootcamp\b|\bworkshop\b|\bcourse\s+completion\b)/.test(text);
        const folder = isTraining ? 'trainings' : 'seminars';
        const f = getFolder('certificates', folder);
        match = { categoryKey: f.catKey, folderKey: f.folderKey, defaultTitle: isTraining ? 'Training Certificate' : 'Certificate of Attendance' };
      } else if (/(?:capstone\s+project|\bthesis\b|\bcase\s+study\b|\bproject\s+documentation\b)/.test(text)) {
        const isThesis = /(?:capstone|\bthesis\b)/.test(text);
        const folder = isThesis ? 'thesis-capstone' : 'projects';
        const f = getFolder('accomplishments', folder);
        match = { categoryKey: f.catKey, folderKey: f.folderKey, defaultTitle: isThesis ? 'Capstone Project' : 'Academic Project' };
      } else if (/(?:terminal\s+report|\bpracticum\s+report|\bojt\s+report|\binternship\s+report\b)/.test(text)) {
        const f = getFolder('college-report', 'college-report');
        match = { categoryKey: f.catKey, folderKey: f.folderKey, defaultTitle: 'College Report' };
      }

      if (match) {
        if (boundaryStarts.length === 0 || boundaryStarts[boundaryStarts.length - 1]!.page !== page.pageNumber) {
          boundaryStarts.push({ page: page.pageNumber, ...match });
        }
      }
    }

    if (boundaryStarts.length === 0) {
      const f = getFolder('accomplishments', 'projects');
      boundaryStarts.push({ page: 1, categoryKey: f.catKey, folderKey: f.folderKey, defaultTitle: 'Portfolio Document' });
    } else if (boundaryStarts[0]!.page !== 1) {
      // If page 1 had no explicit anchor, prepend it
      const first = boundaryStarts[0]!;
      boundaryStarts.unshift({ page: 1, categoryKey: first.categoryKey, folderKey: first.folderKey, defaultTitle: first.defaultTitle });
    }

    const proposals: CompiledDocumentProposal[] = [];
    for (let i = 0; i < boundaryStarts.length; i++) {
      const start = boundaryStarts[i]!;
      const endPage = i + 1 < boundaryStarts.length ? boundaryStarts[i + 1]!.page - 1 : totalPages;
      if (start.page > endPage) continue;

      const segText = pages
        .filter((p) => p.pageNumber >= start.page && p.pageNumber <= endPage)
        .map((p) => p.text)
        .join('\n');

      const meta = suggestDocumentMetadata({ rawText: segText }, categories);
      const title = meta.title ?? start.defaultTitle;
      const date = meta.documentDate ?? null;

      proposals.push({
        startPage: start.page,
        endPage,
        categoryKey: start.categoryKey,
        folderKey: start.folderKey,
        title,
        documentDate: date,
        confidence: 0.8,
      });
    }

    return proposals;
  }
}
