import { createHash, randomUUID } from 'node:crypto';
import { basename, extname } from 'node:path';
import { Readable } from 'node:stream';
import { Types } from 'mongoose';
import { AppError } from '../../common/errors/app-error.js';
import type { DocumentRecord } from '../../database/repositories/document.repository.js';
import { createRepositories } from '../../database/repositories/index.js';
import type { DatabaseConnection } from '../../infrastructure/database/database-connection.js';
import {
  OCR_PROCESSING_TIMEOUT_MS,
  OCR_MAX_TEXT_LENGTH,
} from '../../infrastructure/ocr/local-ocr-engine.js';
import {
  OcrEngineError,
  type OcrEngine,
  type OcrEngineName,
} from '../../infrastructure/ocr/ocr-engine.js';
import type { ObjectStorage } from '../../infrastructure/storage/object-storage.js';
import { suggestDocumentMetadata, type MetadataSuggestions } from './metadata-suggestion.service.js';

export const MAX_DOCUMENT_FILE_SIZE_BYTES = 15 * 1024 * 1024;

interface SupportedFileType {
  readonly mimeType: string;
  readonly extensions: readonly string[];
  readonly fileKind: 'image' | 'pdf';
  hasValidSignature(contents: Buffer): boolean;
}

const SUPPORTED_FILE_TYPES: readonly SupportedFileType[] = [
  {
    mimeType: 'application/pdf',
    extensions: ['pdf'],
    fileKind: 'pdf',
    hasValidSignature: (contents) => contents.subarray(0, 5).toString('ascii') === '%PDF-',
  },
  {
    mimeType: 'image/jpeg',
    extensions: ['jpg', 'jpeg'],
    fileKind: 'image',
    hasValidSignature: (contents) =>
      contents.length >= 3 &&
      contents[0] === 0xff &&
      contents[1] === 0xd8 &&
      contents[2] === 0xff,
  },
  {
    mimeType: 'image/png',
    extensions: ['png'],
    fileKind: 'image',
    hasValidSignature: (contents) =>
      contents.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])),
  },
] as const;

export interface DocumentFileInput {
  readonly originalFileName: string;
  readonly mimeType: string;
  readonly contents: Buffer;
}

export interface DocumentUploadInput extends DocumentFileInput {
  readonly categoryKey: string;
  readonly folderKey: string;
  readonly title: string;
  readonly documentDate: string;
  readonly description?: string;
  readonly reflection?: string;
}

export interface PublicDocument {
  readonly id: string;
  readonly categoryKey: string;
  readonly folderKey: string;
  readonly title: string;
  readonly documentDate: string;
  readonly description?: string;
  readonly reflection?: string;
  readonly originalFileName: string;
  readonly mimeType: string;
  readonly fileKind: 'image' | 'pdf' | 'docx';
  readonly extension: string;
  readonly sizeBytes: number;
  readonly createdAt: string;
  readonly updatedAt: string;
}

export interface PublicDocumentCategory {
  readonly key: string;
  readonly name: string;
  readonly folders: readonly {
    readonly key: string;
    readonly name: string;
  }[];
}

export interface PublicDocumentSummary {
  readonly totalCount: number;
  readonly categoryCounts: Readonly<Record<string, number>>;
  readonly folderCounts: Readonly<Record<string, number>>;
}

export interface DocumentContent {
  readonly document: PublicDocument;
  readonly contents: Readable;
}

export interface PublicDocumentOcr {
  readonly status: 'not_processed' | 'processing' | 'ready' | 'failed';
  readonly rawText?: string;
  readonly reviewedText?: string;
  readonly engine?: OcrEngineName;
  readonly processedAt?: string;
  readonly updatedAt?: string;
  readonly metadataSuggestions?: MetadataSuggestions;
}

const NOT_FOUND = new AppError(
  404,
  'DOCUMENT_NOT_FOUND',
  'The requested document was not found.',
);

function validationError(field: string, message: string): AppError {
  return new AppError(400, 'VALIDATION_ERROR', 'The request is invalid.', {
    [field]: [message],
  });
}

function documentUnavailable(cause?: unknown): AppError {
  return new AppError(
    503,
    'DOCUMENT_UNAVAILABLE',
    'Documents are temporarily unavailable. Please try again.',
    undefined,
    undefined,
    cause === undefined ? undefined : { cause },
  );
}

function ocrUnavailable(_cause?: unknown): AppError {
  return new AppError(
    503,
    'OCR_UNAVAILABLE',
    'Text extraction is temporarily unavailable. Please try again.',
  );
}

function publicOcr(document: DocumentRecord): PublicDocumentOcr {
  const ocr = document.ocr;
  if (ocr === undefined) return { status: 'not_processed' };
  return {
    status: ocr.status,
    ...(ocr.rawText === undefined ? {} : { rawText: ocr.rawText }),
    ...(ocr.reviewedText === undefined ? {} : { reviewedText: ocr.reviewedText }),
    ...(ocr.engine === undefined ? {} : { engine: ocr.engine }),
    ...(ocr.processedAt === undefined
      ? {}
      : { processedAt: ocr.processedAt.toISOString() }),
    updatedAt: ocr.updatedAt.toISOString(),
  };
}

function mappedOcrError(error: unknown): AppError {
  if (!(error instanceof OcrEngineError)) return ocrUnavailable(error);
  switch (error.reason) {
    case 'invalid-image':
      return new AppError(422, 'INVALID_OCR_IMAGE', 'The uploaded image cannot be processed.');
    case 'image-too-large':
      return new AppError(
        422,
        'OCR_IMAGE_TOO_LARGE',
        'The image dimensions are too large for text extraction.',
      );
    case 'invalid-pdf':
      return new AppError(422, 'INVALID_OCR_PDF', 'The uploaded PDF cannot be processed.');
    case 'pdf-too-many-pages':
      return new AppError(
        422,
        'OCR_PDF_TOO_LARGE',
        'The PDF contains too many pages for text extraction.',
      );
    case 'protected-pdf':
      return new AppError(
        422,
        'PROTECTED_PDF_NOT_SUPPORTED',
        'Password-protected PDFs are not supported for text extraction.',
      );
    case 'scanned-pdf-not-supported':
      return new AppError(
        422,
        'SCANNED_PDF_OCR_NOT_SUPPORTED',
        'This PDF has no embedded text. Scanned PDF OCR is not supported yet.',
      );
    case 'text-too-large':
      return new AppError(
        422,
        'OCR_TEXT_TOO_LARGE',
        'The extracted text is too large to save.',
      );
    case 'timeout':
      return new AppError(
        504,
        'OCR_TIMEOUT',
        'Text extraction took too long. Please try a smaller document.',
      );
    case 'unavailable':
      return ocrUnavailable(error);
  }
}

function normalizedRequired(value: string, field: string, maxLength: number): string {
  const normalized = value.trim();
  if (normalized.length === 0) throw validationError(field, 'is required');
  if (normalized.length > maxLength) {
    throw validationError(field, `must contain at most ${maxLength} characters`);
  }
  return normalized;
}

function normalizedOptional(
  value: string | undefined,
  field: string,
  maxLength: number,
): string | undefined {
  if (value === undefined) return undefined;
  const normalized = value.trim();
  if (normalized.length === 0) return undefined;
  if (normalized.length > maxLength) {
    throw validationError(field, `must contain at most ${maxLength} characters`);
  }
  return normalized;
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

function sanitizedFileName(value: string): string {
  const leaf = basename(value.replaceAll('\\', '/'))
    .normalize('NFKC')
    .replace(/[<>:"/\\|?*]/g, '_')
    .split('')
    .map((character) => (character.charCodeAt(0) < 32 ? '_' : character))
    .join('')
    .trim();
  if (leaf.length === 0 || leaf === '.' || leaf === '..') {
    throw validationError('file', 'must have a valid filename');
  }
  if (leaf.length <= 255) return leaf;
  const extension = extname(leaf);
  return `${leaf.slice(0, 255 - extension.length)}${extension}`;
}

function fileTypeFor(fileName: string, mimeType: string, contents: Buffer) {
  const extension = extname(fileName).slice(1).toLowerCase();
  const type = SUPPORTED_FILE_TYPES.find(
    (candidate) =>
      candidate.mimeType === mimeType.toLowerCase() &&
      candidate.extensions.includes(extension),
  );
  if (type === undefined || !type.hasValidSignature(contents)) {
    throw new AppError(
      415,
      'UNSUPPORTED_FILE_TYPE',
      'Only valid PDF, JPG, JPEG, and PNG files are supported.',
    );
  }
  return { extension, fileKind: type.fileKind, mimeType: type.mimeType };
}

function publicDocument(document: DocumentRecord): PublicDocument {
  return {
    id: document._id.toString(),
    categoryKey: document.categoryKey,
    folderKey: document.folderKey,
    title: document.title,
    documentDate: document.documentDate.toISOString(),
    ...(document.description === undefined ? {} : { description: document.description }),
    ...(document.reflection === undefined ? {} : { reflection: document.reflection }),
    originalFileName: document.originalFileName,
    mimeType: document.mimeType,
    fileKind: document.fileKind,
    extension: document.extension,
    sizeBytes: document.sizeBytes,
    createdAt: document.createdAt.toISOString(),
    updatedAt: document.updatedAt.toISOString(),
  };
}

export class DocumentService {
  constructor(
    private readonly database: DatabaseConnection,
    private readonly storage: ObjectStorage,
    private readonly ocrEngine: OcrEngine,
  ) {}

  async upload(ownerId: Types.ObjectId, input: DocumentUploadInput): Promise<PublicDocument> {
    if (input.contents.length === 0) throw validationError('file', 'must not be empty');
    if (input.contents.length > MAX_DOCUMENT_FILE_SIZE_BYTES) {
      throw new AppError(413, 'FILE_TOO_LARGE', 'The file exceeds the 15 MB upload limit.');
    }

    const categoryKey = normalizedRequired(input.categoryKey, 'categoryKey', 100);
    const folderKey = normalizedRequired(input.folderKey, 'folderKey', 100);
    const title = normalizedRequired(input.title, 'title', 250);
    const description = normalizedOptional(input.description, 'description', 2_000);
    const reflection = normalizedOptional(input.reflection, 'reflection', 5_000);
    const originalFileName = sanitizedFileName(input.originalFileName);
    const fileType = fileTypeFor(originalFileName, input.mimeType, input.contents);
    const repositories = this.repositories();

    let category;
    try {
      category = await repositories.documentCategories.findByKey(categoryKey);
    } catch (error) {
      throw documentUnavailable(error);
    }
    if (category === null || !category.active) {
      throw validationError('categoryKey', 'must identify an active document category');
    }
    if (!category.folders.some((folder) => folder.active && folder.key === folderKey)) {
      throw validationError('folderKey', 'must belong to the selected document category');
    }

    const objectKey = `users/${ownerId.toString()}/documents/${randomUUID()}.${fileType.extension}`;
    let storedKey: string;
    try {
      const stored = await this.storage.put(objectKey, Readable.from([input.contents]));
      if (stored.sizeBytes !== input.contents.length) {
        await this.bestEffortDelete(stored.key);
        throw documentUnavailable();
      }
      storedKey = stored.key;
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw documentUnavailable(error);
    }

    try {
      const created = await repositories.documents.create({
        ownerId,
        categoryKey,
        folderKey,
        title,
        documentDate: documentDate(input.documentDate),
        ...(description === undefined ? {} : { description }),
        ...(reflection === undefined ? {} : { reflection }),
        originalFileName,
        objectKey: storedKey,
        mimeType: fileType.mimeType,
        fileKind: fileType.fileKind,
        extension: fileType.extension,
        sizeBytes: input.contents.length,
        sha256: createHash('sha256').update(input.contents).digest('hex'),
      });
      return publicDocument(created);
    } catch (error) {
      await this.bestEffortDelete(storedKey);
      if (error instanceof AppError) throw error;
      throw documentUnavailable(error);
    }
  }

  async list(ownerId: Types.ObjectId): Promise<{
    readonly documents: readonly PublicDocument[];
    readonly summary: PublicDocumentSummary;
  }> {
    try {
      const repositories = this.repositories();
      const [documents, summary] = await Promise.all([
        repositories.documents.listForOwner(ownerId),
        repositories.documents.countForOwner(ownerId),
      ]);
      return { documents: documents.map(publicDocument), summary };
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw documentUnavailable(error);
    }
  }

  async listCategories(): Promise<readonly PublicDocumentCategory[]> {
    try {
      const categories = await this.repositories().documentCategories.listActive();
      return categories.map((category) => ({
        key: category.key,
        name: category.name,
        folders: category.folders
          .filter((folder) => folder.active)
          .sort((left, right) => left.sortOrder - right.sortOrder)
          .map((folder) => ({ key: folder.key, name: folder.name })),
      }));
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw documentUnavailable(error);
    }
  }

  async get(ownerId: Types.ObjectId, documentId: string): Promise<PublicDocument> {
    return publicDocument(await this.ownedDocument(ownerId, documentId));
  }

  async openContent(ownerId: Types.ObjectId, documentId: string): Promise<DocumentContent> {
    const stored = await this.ownedDocument(ownerId, documentId);
    try {
      return {
        document: publicDocument(stored),
        contents: await this.storage.get(stored.objectKey),
      };
    } catch (error) {
      throw documentUnavailable(error);
    }
  }

  async getOcr(ownerId: Types.ObjectId, documentId: string): Promise<PublicDocumentOcr> {
    return this.withSuggestions(publicOcr(await this.ownedDocument(ownerId, documentId)));
  }

  // Pre-upload OCR is transient: no document, object, or guessed metadata is persisted.
  async previewOcr(input: DocumentFileInput): Promise<PublicDocumentOcr> {
    if (input.contents.length === 0) throw validationError('file', 'must not be empty');
    if (input.contents.length > MAX_DOCUMENT_FILE_SIZE_BYTES) {
      throw new AppError(413, 'FILE_TOO_LARGE', 'The file exceeds the 15 MB upload limit.');
    }
    const type = fileTypeFor(sanitizedFileName(input.originalFileName), input.mimeType, input.contents);
    try {
      const extracted = await this.extractContents({ ...type, contents: input.contents });
      return this.withSuggestions({
        status: 'ready',
        rawText: extracted.rawText,
        reviewedText: extracted.rawText,
        engine: extracted.engine,
      });
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw mappedOcrError(error);
    }
  }

  async extractOcr(ownerId: Types.ObjectId, documentId: string): Promise<PublicDocumentOcr> {
    const document = await this.ownedDocument(ownerId, documentId);
    if (document.fileKind !== 'image' && document.fileKind !== 'pdf') {
      throw new AppError(
        415,
        'OCR_FILE_TYPE_NOT_SUPPORTED',
        'Text extraction is supported only for images and PDFs.',
      );
    }

    const repositories = this.repositories();
    const processingId = randomUUID();
    const startedAt = new Date();
    const engine: OcrEngineName = document.fileKind === 'image' ? 'tesseract.js' : 'pdfjs';
    let claimed: boolean;
    try {
      claimed = await repositories.documents.claimOcrForProcessing(
        ownerId,
        document._id,
        {
          processingId,
          engine,
          now: startedAt,
          expiresAt: new Date(startedAt.getTime() + OCR_PROCESSING_TIMEOUT_MS * 2),
        },
      );
    } catch (error) {
      throw ocrUnavailable(error);
    }
    if (!claimed) {
      throw new AppError(
        409,
        'OCR_ALREADY_PROCESSING',
        'Text extraction is already in progress for this document.',
      );
    }

    try {
      const stream = await this.storage.get(document.objectKey);
      const contents = await readableToBoundedBuffer(stream, MAX_DOCUMENT_FILE_SIZE_BYTES);
      const extracted = await this.extractContents({
        contents,
        mimeType: document.mimeType,
        fileKind: document.fileKind,
      });
      const completed = await repositories.documents.completeOcr(
        ownerId,
        document._id,
        processingId,
        {
          rawText: extracted.rawText,
          engine: extracted.engine,
          processedAt: new Date(),
        },
      );
      if (completed === null) throw ocrUnavailable();
      return this.withSuggestions(publicOcr(completed));
    } catch (error) {
      try {
        await repositories.documents.failOcr(
          ownerId,
          document._id,
          processingId,
          engine,
          new Date(),
        );
      } catch {
        // Preserve the extraction error; failure state is best-effort only.
      }
      if (error instanceof AppError) throw error;
      throw mappedOcrError(error);
    }
  }

  async updateOcr(
    ownerId: Types.ObjectId,
    documentId: string,
    reviewedText: string,
  ): Promise<PublicDocumentOcr> {
    if (reviewedText.length > OCR_MAX_TEXT_LENGTH) {
      throw validationError(
        'reviewedText',
        `must contain at most ${OCR_MAX_TEXT_LENGTH} characters`,
      );
    }
    const document = await this.ownedDocument(ownerId, documentId);
    let updated;
    try {
      updated = await this.repositories().documents.updateReviewedOcrText(
        ownerId,
        document._id,
        reviewedText,
        new Date(),
      );
    } catch (error) {
      throw ocrUnavailable(error);
    }
    if (updated === null) {
      throw new AppError(
        409,
        'OCR_NOT_READY',
        'Extract text before saving reviewed text.',
      );
    }
    return this.withSuggestions(publicOcr(updated));
  }

  private async extractContents(input: Parameters<OcrEngine['extract']>[0]) {
    const extracted = await this.ocrEngine.extract(input);
    if (extracted.rawText.length === 0) {
      throw new AppError(422, 'OCR_NO_TEXT_FOUND', 'No readable text was found.');
    }
    if (extracted.rawText.length > OCR_MAX_TEXT_LENGTH) {
      throw new AppError(422, 'OCR_TEXT_TOO_LARGE', 'The extracted text is too large to save.');
    }
    return extracted;
  }

  private async withSuggestions(ocr: PublicDocumentOcr): Promise<PublicDocumentOcr> {
    if (ocr.status !== 'ready') return ocr;
    let categories: readonly PublicDocumentCategory[] = [];
    try {
      categories = await this.listCategories();
    } catch {
      // An unavailable category list must not discard successful OCR. Text fields
      // remain useful; no category or folder will be invented as a fallback.
    }
    return { ...ocr, metadataSuggestions: suggestDocumentMetadata(ocr, categories) };
  }

  async delete(ownerId: Types.ObjectId, documentId: string): Promise<void> {
    const document = await this.ownedDocument(ownerId, documentId);
    try {
      await this.storage.delete(document.objectKey);
    } catch (error) {
      throw documentUnavailable(error);
    }
    try {
      const deleted = await this.repositories().documents.deleteByIdForOwner(
        ownerId,
        document._id,
      );
      if (!deleted) throw NOT_FOUND;
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw documentUnavailable(error);
    }
  }

  private async ownedDocument(
    ownerId: Types.ObjectId,
    documentId: string,
  ): Promise<DocumentRecord> {
    let document;
    try {
      document = await this.repositories().documents.findByIdForOwner(
        ownerId,
        new Types.ObjectId(documentId),
      );
    } catch (error) {
      throw documentUnavailable(error);
    }
    if (document === null) throw NOT_FOUND;
    return document;
  }

  private repositories() {
    const connection = this.database.mongooseConnection;
    if (this.database.status !== 'connected' || connection === undefined) {
      throw documentUnavailable();
    }
    return createRepositories(connection);
  }

  private async bestEffortDelete(key: string): Promise<void> {
    try {
      await this.storage.delete(key);
    } catch {
      // Preserve the original failure. Storage cleanup can be retried operationally.
    }
  }
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
    if (buffer === null) throw ocrUnavailable();
    total += buffer.length;
    if (total > maxBytes) {
      throw new AppError(413, 'OCR_INPUT_TOO_LARGE', 'The document is too large to process.');
    }
    chunks.push(buffer);
  }
  return Buffer.concat(chunks, total);
}
