import { randomUUID, createHash } from 'node:crypto';
import { extname, basename } from 'node:path';
import { Readable } from 'node:stream';
import type { Types } from 'mongoose';
import { PDFDocument } from 'pdf-lib';
import { AppError } from '../../common/errors/app-error.js';
import type { DatabaseConnection } from '../../infrastructure/database/database-connection.js';
import { createRepositories } from '../../database/repositories/index.js';
import type { ObjectStorage } from '../../infrastructure/storage/object-storage.js';
import { OcrEngineError, type OcrEngine, type OcrPageText } from '../../infrastructure/ocr/ocr-engine.js';
import { COLLECTION_NAMES } from '../../database/collection-names.js';
import type { AiMetadataService, MetadataAnalysis } from './ai-metadata.service.js';
import { suggestDocumentMetadata, type MetadataSuggestions } from './metadata-suggestion.service.js';
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
  readonly pages: readonly OcrPageText[];
  readonly detection: 'single' | 'multiple' | 'needs_review';
  readonly metadataSuggestions?: MetadataSuggestions;
  readonly metadataAnalysis?: MetadataAnalysis;
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
  readonly pageTexts: readonly OcrPageText[];
  readonly proposals: readonly CompiledDocumentProposal[];
  readonly createdAt: Date;
  readonly expiresAt: Date;
  completedDocuments?: readonly PublicDocument[];
  completedIdempotencyKey?: string;
  requestHash?: string;
  state?: 'analyzing' | 'ready' | 'processing' | 'complete' | 'failed' | 'cancelling';
}

/** Do not sort/repair ranges: the reviewed order itself must cover every page once. */
export function hasCompleteCoverage(segments: readonly { startPage: number; endPage: number }[], totalPages: number): boolean {
  let next = 1;
  for (const segment of segments) {
    if (!Number.isInteger(segment.startPage) || !Number.isInteger(segment.endPage) ||
        segment.startPage !== next || segment.endPage < segment.startPage || segment.endPage > totalPages) return false;
    next = segment.endPage + 1;
  }
  return segments.length > 0 && next === totalPages + 1;
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

  private sessions() {
    const conn = this.database.mongooseConnection;
    if (!conn) throw new AppError(503, 'DATABASE_UNAVAILABLE', 'Database connection is unavailable.');
    return conn.collection<CompiledSessionRecord>(COLLECTION_NAMES.compiledDocumentSessions);
  }

  private async retireSession(session: CompiledSessionRecord): Promise<void> {
    // Delete storage first. Keep the cleanup record if deletion fails.
    await this.storage.delete(session.tempObjectKey);
    await this.sessions().deleteOne({ sessionId: session.sessionId, ownerId: session.ownerId });
  }

  private async getSession(sessionId: string, ownerId: Types.ObjectId): Promise<CompiledSessionRecord | null> {
    const found = await this.sessions().findOne({ sessionId, ownerId: ownerId.toString() });
    if (found && found.expiresAt <= new Date()) {
      if (found.state !== 'processing' && found.state !== 'failed') {
        await this.retireSession(found).catch(() => undefined);
      }
      return null;
    }
    return found;
  }

  private async cleanupExpired(ownerId: Types.ObjectId): Promise<void> {
    const expired = await this.sessions().find({
      ownerId: ownerId.toString(), expiresAt: { $lte: new Date() }, state: { $nin: ['processing', 'failed'] },
    }).limit(10).toArray();
    for (const session of expired) {
      await this.retireSession(session).catch(() => undefined);
    }
  }

  async analyze(
    ownerId: Types.ObjectId,
    file: DocumentFileInput,
    requestId?: string,
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
        if (error.reason === 'pdf-too-many-pages' || error.reason === 'pdf-too-many-ocr-pages' || error.reason === 'text-too-large') {
          throw new AppError(422, 'COMPILED_PROCESSING_LIMIT', 'This PDF exceeds the supported page, OCR-page, or text limit. Please use a smaller PDF.');
        }
        if (error.reason === 'timeout') throw new AppError(504, 'OCR_TIMEOUT', 'PDF analysis timed out. Please use a smaller PDF or retry.');
        if (error.reason === 'busy') throw new AppError(503, 'OCR_BUSY', 'The server is processing another document. Please retry shortly.');
        throw new AppError(503, 'OCR_UNAVAILABLE', 'PDF analysis is temporarily unavailable. Please retry.');
      }
      throw error;
    }

    const totalPages = extracted.totalPages ?? extracted.pages?.length ?? 1;
    const extractedPages = extracted.pages && extracted.pages.length > 0
      ? extracted.pages
      : [{ pageNumber: 1, text: extracted.rawText }];
    const pages: OcrPageText[] = Array.from({ length: totalPages }, (_, index) => {
      const page = extractedPages.find((value) => value.pageNumber === index + 1);
      return page
        ? { ...page, source: page.source ?? (page.text.trim() ? 'digital' : 'failed'), status: page.status ?? (page.text.trim() ? 'ready' : 'unresolved') }
        : { pageNumber: index + 1, text: '', source: 'failed', status: 'unresolved' };
    });
    await this.cleanupExpired(ownerId);

    // Store temporary compiled PDF in R2
    const sessionId = `csess_${randomUUID()}`;
    const tempObjectKey = `users/${ownerId.toString()}/temp-compiled/${sessionId}.pdf`;
    const session: CompiledSessionRecord = {
      sessionId, ownerId: ownerId.toString(), tempObjectKey,
      originalFileName: sanitizedFileName(file.originalFileName), totalPages, pageTexts: pages,
      proposals: [], createdAt: new Date(), expiresAt: new Date(Date.now() + 60 * 60 * 1000), state: 'analyzing',
    };
    // Persist cleanup intent before storing an object; no runtime index creation.
    await this.sessions().insertOne(session);
    try {
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
      const unresolved = pages.some((page) => page.status === 'unresolved');
      let singleMetadata: { metadataSuggestions: MetadataSuggestions; metadataAnalysis: MetadataAnalysis } | undefined;
      let aiAccepted = false;
      let aiStatus: MetadataAnalysis['aiStatus'] = 'disabled';
      // One physical page cannot be split into regions. Preserve the established
      // metadata recommender for that case, using text already extracted above.
      if (!unresolved && totalPages === 1 && this.metadata?.recommend) {
        singleMetadata = await this.metadata.recommend({ rawText: extracted.rawText }, categories, requestId);
        const metadata = singleMetadata.metadataSuggestions;
        proposals = [{ startPage: 1, endPage: 1, categoryKey: metadata.categoryKey ?? '',
          folderKey: metadata.folderKey ?? '', title: metadata.title ?? 'Document — review category',
          documentDate: metadata.documentDate ?? null,
          confidence: metadata.confidence === 'high' ? 0.9 : metadata.confidence === 'medium' ? 0.8 : 0 }];
      } else if (!unresolved && this.metadata?.separateCompiled) {
        try {
          const rawAiResult = await this.metadata.separateCompiled(pages, categories);
          if (rawAiResult) {
            proposals = this.validateAndNormalizeProposals(rawAiResult, totalPages, categories, pages);
            aiAccepted = proposals.length > 0;
            aiStatus = aiAccepted ? 'success' : 'unavailable';
          }
        } catch {
          // Fallback to deterministic rules
          proposals = [];
          aiStatus = 'unavailable';
        }
      }

      if (proposals.length === 0) {
        proposals = this.heuristicSplit(pages, totalPages, categories);
      }
      if (!singleMetadata && !unresolved && proposals.length === 1) {
        const proposal = proposals[0]!;
        const rules = suggestDocumentMetadata({ rawText: extracted.rawText }, categories);
        singleMetadata = {
          metadataSuggestions: {
            ...rules,
            ...(proposal.categoryKey ? { categoryKey: proposal.categoryKey, folderKey: proposal.folderKey } : {}),
            ...(proposal.confidence > 0 ? { title: proposal.title } : {}),
            ...(proposal.documentDate ? { documentDate: proposal.documentDate } : {}),
            confidence: proposal.confidence >= 0.75 ? 'high' : 'low',
          },
          metadataAnalysis: { source: aiAccepted ? 'gemini' : 'rules', aiStatus },
        };
      }

      await this.sessions().updateOne({ sessionId }, { $set: { proposals, state: 'ready' } });
      const confident = !unresolved && proposals.every((proposal) => proposal.confidence >= 0.75 && proposal.categoryKey && proposal.folderKey);

      return {
        sessionId,
        originalFileName: session.originalFileName,
        totalPages,
        documents: proposals,
        pages,
        detection: confident ? (proposals.length > 1 ? 'multiple' : 'single') : 'needs_review',
        ...singleMetadata,
      };
    } catch (error) {
      await this.retireSession(session).catch(() => undefined);
      throw error;
    }
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

    const requestHash = createHash('sha256').update(JSON.stringify(input.segments.map((segment) => ({
      startPage: segment.startPage, endPage: segment.endPage, categoryKey: segment.categoryKey,
      folderKey: segment.folderKey, title: segment.title.trim(), documentDate: segment.documentDate,
      description: segment.description?.trim() ?? '', reflection: segment.reflection?.trim() ?? '',
    })))).digest('hex');
    // A cached success belongs to exactly this owner/session/key/payload.
    if (session.completedIdempotencyKey === input.idempotencyKey && session.completedDocuments) {
      if (session.requestHash !== requestHash) throw new AppError(409, 'SPLIT_REQUEST_CHANGED', 'This retry does not match the saved split request.');
      return { documents: [...session.completedDocuments] };
    }
    if (session.state === 'complete' || session.completedDocuments) throw new AppError(409, 'SESSION_ALREADY_SPLIT', 'This PDF has already been separated. Open the saved documents.');
    if (session.state === 'failed') throw new AppError(503, 'SPLIT_RECOVERY_REQUIRED', 'This split needs cleanup before it can be retried. No new documents were created by this request.');
    if (session.pageTexts.some((page) => page.status === 'unresolved' || page.source === 'failed')) {
      throw new AppError(422, 'COMPILED_UNRESOLVED_PAGES', 'Some pages could not be read. Retry analysis or handle the source manually before splitting.');
    }
    if (!hasCompleteCoverage(input.segments, session.totalPages)) {
      throw validationError('segments', 'must cover every source page exactly once, in order, without gaps or overlaps');
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
      documentDate(seg.documentDate);
    }

    const claim = await this.sessions().updateOne({
      sessionId: session.sessionId, ownerId: ownerId.toString(), expiresAt: { $gt: new Date() },
      $or: [{ state: 'ready' }, { state: { $exists: false } }],
    }, { $set: { state: 'processing', requestHash, completedIdempotencyKey: input.idempotencyKey } });
    if (claim.modifiedCount !== 1) throw new AppError(409, 'SPLIT_IN_PROGRESS', 'This PDF is already being processed. Retry the same request shortly.');

    const createdDocs: PublicDocument[] = [];
    const createdObjectKeys: string[] = [];
    const createdDocIds: Types.ObjectId[] = [];
    let recordingCompletion = false;
    try {

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
        createdObjectKeys.push(objectKey);
        const stored = await this.storage.put(objectKey, Readable.from([subPdfBytes]));

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
      recordingCompletion = true;
      const receipt = await this.sessions().updateOne({ sessionId: session.sessionId, state: 'processing', requestHash }, {
        $set: { state: 'complete', completedDocuments: createdDocs },
      });
      if (receipt.modifiedCount !== 1) throw new Error('Split completion was not recorded');

      // Cleanup temporary compiled PDF
      await this.storage.delete(session.tempObjectKey).catch(() => undefined);

      return { documents: createdDocs };
    } catch (error) {
      // An acknowledgement can be lost after MongoDB commits the receipt. Never
      // delete documents that a subsequent identical retry could return as saved.
      if (recordingCompletion) {
        throw new AppError(503, 'SPLIT_RESULT_UNCONFIRMED', 'The split result could not be confirmed. Retry the same request; do not start another upload.', undefined, undefined, { cause: error });
      }
      // Compensating rollback
      let cleaned = true;
      for (const key of createdObjectKeys) {
        await this.storage.delete(key).catch(() => { cleaned = false; });
      }
      for (const docId of createdDocIds) {
        await repositories.documents.deleteByIdForOwner(ownerId, docId).catch(() => { cleaned = false; });
      }
      await this.sessions().updateOne({ sessionId: session.sessionId, state: 'processing', requestHash }, {
        $set: { state: cleaned ? 'ready' : 'failed' },
      }).catch(() => undefined);
      if (error instanceof AppError) throw error;
      throw new AppError(503, 'SPLIT_FAILED', cleaned
        ? 'The split failed. Created files and records were removed; you may retry.'
        : 'The split failed and cleanup could not be completed. Please contact support before retrying.', undefined, undefined, { cause: error });
    }
  }

  async cancel(ownerId: Types.ObjectId, sessionId: string): Promise<{ cancelled: boolean }> {
    // Cancellation must report failed cleanup even for an expired session.
    const session = await this.sessions().findOne({ sessionId, ownerId: ownerId.toString() });
    if (session) {
      if (session.state === 'processing' || session.state === 'failed') throw new AppError(409, 'SPLIT_IN_PROGRESS', 'This split cannot be discarded while processing or recovery is pending.');
      if (session.state === 'complete') {
        try { await this.storage.delete(session.tempObjectKey); }
        catch { throw new AppError(503, 'CLEANUP_PENDING', 'Temporary-file cleanup is pending. Please retry cancellation.'); }
        return { cancelled: true }; // Keep the successful retry receipt until expiry.
      }
      const claim = await this.sessions().updateOne({ sessionId, ownerId: ownerId.toString(), state: { $nin: ['processing', 'complete', 'failed'] } }, { $set: { state: 'cancelling' } });
      if (claim.matchedCount !== 1) throw new AppError(409, 'SPLIT_IN_PROGRESS', 'This session is already being processed.');
      try { await this.retireSession(session); }
      catch { throw new AppError(503, 'CLEANUP_PENDING', 'Temporary-file cleanup is pending. Please retry cancellation.'); }
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
      if (typeof doc !== 'object' || doc === null) return [];
      const startPage = doc.startPage as number;
      const endPage = doc.endPage as number;
      if (!Number.isInteger(startPage) || !Number.isInteger(endPage)) return [];
      if (startPage < 1 || endPage > totalPages || startPage > endPage) return [];
      // Ranges must be non-overlapping and contiguous/ascending
      if (startPage !== lastEndPage + 1) return [];

      const catKey = typeof doc.categoryKey === 'string' ? doc.categoryKey.trim() : '';
      const cat = categories.find((c) => c.key === catKey);
      if (!cat) return [];

      const folderKey = typeof doc.folderKey === 'string' ? doc.folderKey.trim() : '';
      if (!cat.folders.some((f) => f.key === folderKey)) {
        return [];
      }

      let title = typeof doc.title === 'string' ? doc.title.trim().slice(0, 250) : '';
      if (!title) {
        title = cat.name;
      }

      let date: string | null =
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
      if (date !== null) {
        try { documentDate(date); } catch { date = null; }
      }

      const conf = typeof doc.confidence === 'number' && doc.confidence >= 0 && doc.confidence <= 1
        ? doc.confidence
        : 0;

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

    return hasCompleteCoverage(proposals, totalPages) ? proposals : [];
  }

  private heuristicSplit(
    pages: readonly OcrPageText[],
    totalPages: number,
    categories: readonly PublicDocumentCategory[],
  ): CompiledDocumentProposal[] {
    const boundaryStarts: { page: number; categoryKey: string; folderKey: string; defaultTitle: string }[] = [];

    const getCat = (key: string) => categories.find((c) => c.key === key);
    const getFolder = (catKey: string, folderKey: string) => {
      const c = getCat(catKey);
      const f = c?.folders.find((fol) => fol.key === folderKey);
      return c && f ? { catKey: c.key, folderKey: f.key } : { catKey: '', folderKey: '' };
    };

    for (const page of pages) {
      const text = page.text.toLowerCase();
      let match: { categoryKey: string; folderKey: string; defaultTitle: string } | null = null;

      if (page.status === 'unresolved') {
        boundaryStarts.push({ page: page.pageNumber, categoryKey: '', folderKey: '', defaultTitle: 'Unreadable page — retry required' });
        continue;
      }
      if (/(?:curriculum\s+vitae|\bresume\b|\bbio-data\b)/.test(text)) {
        const f = getFolder('curriculum-vitae', 'curriculum-vitae');
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
        const folder = isThesis ? 'thesis-capstone' : /case\s+study/.test(text) ? 'case-studies' : 'projects';
        const f = getFolder('accomplishments', folder);
        match = { categoryKey: f.catKey, folderKey: f.folderKey, defaultTitle: isThesis ? 'Capstone Project' : 'Academic Project' };
      } else if (/(?:terminal\s+report|\bpracticum\s+report|\bojt\s+report|\binternship\s+report\b)/.test(text)) {
        const f = getFolder('college-report', 'college-report');
        match = { categoryKey: f.catKey, folderKey: f.folderKey, defaultTitle: 'College Report' };
      }

      if (match) {
        const prior = boundaryStarts.at(-1);
        // Repeated CV/TOR/project headers usually introduce continuation pages,
        // unlike separate certificates, which must remain independent.
        if (prior?.categoryKey === match.categoryKey && ['curriculum-vitae', 'scholastic-record', 'accomplishments'].includes(match.categoryKey)) continue;
        if (boundaryStarts.length === 0 || boundaryStarts[boundaryStarts.length - 1]!.page !== page.pageNumber) {
          boundaryStarts.push({ page: page.pageNumber, ...match });
        }
      } else if (boundaryStarts.at(-1)?.categoryKey === '') {
        boundaryStarts.push({ page: page.pageNumber, categoryKey: '', folderKey: '', defaultTitle: 'Document — review category' });
      }
    }

    if (boundaryStarts.length === 0) {
      boundaryStarts.push({ page: 1, categoryKey: '', folderKey: '', defaultTitle: 'Document — review category' });
    } else if (boundaryStarts[0]!.page !== 1) {
      // An unrecognized leading page is not evidence for the next category.
      boundaryStarts.unshift({ page: 1, categoryKey: '', folderKey: '', defaultTitle: 'Document — review category' });
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
        confidence: start.categoryKey ? 0.8 : 0,
      });
    }

    return proposals;
  }
}
