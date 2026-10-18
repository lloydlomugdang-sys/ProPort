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
import { AiMetadataService, type MetadataAnalysis } from './ai-metadata.service.js';
import { requireTorReflection, validateScholasticDetails, type ScholasticDetails } from './scholastic-details.js';

export const MAX_DOCUMENT_FILE_SIZE_BYTES = 15 * 1024 * 1024;
export const MAX_DOCUMENT_ATTACHMENTS = 10;
export const MAX_COMBINED_DOCUMENT_SIZE_BYTES = 45 * 1024 * 1024;

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

export interface DocumentUploadInput {
  readonly scholastic?: ScholasticDetails;
  readonly categoryKey: string;
  readonly folderKey: string;
  readonly title: string;
  readonly documentDate: string;
  readonly description?: string;
  readonly reflection?: string;
  readonly files?: readonly DocumentFileInput[];
  readonly originalFileName?: string;
  readonly mimeType?: string;
  readonly contents?: Buffer;
}

export interface PublicDocumentAttachment {
  readonly id: string;
  readonly originalFileName: string;
  readonly mimeType: string;
  readonly fileKind: 'image' | 'pdf';
  readonly extension: string;
  readonly sizeBytes: number;
  readonly order: number;
}

export interface PublicDocument {
  readonly scholastic?: ScholasticDetails;
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
  readonly attachments?: readonly PublicDocumentAttachment[];
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
  readonly mimeType?: string;
  readonly originalFileName?: string;
  readonly sizeBytes?: number;
}

export interface PublicDocumentOcrPage {
  readonly pageNumber: number;
  readonly originalFileName?: string;
  readonly mimeType?: string;
  readonly status: 'ready' | 'failed';
  readonly rawText?: string;
}

export interface PublicDocumentOcr {
  readonly status: 'not_processed' | 'processing' | 'ready' | 'failed';
  readonly rawText?: string;
  readonly reviewedText?: string;
  readonly engine?: OcrEngineName;
  readonly processedAt?: string;
  readonly updatedAt?: string;
  readonly pages?: readonly PublicDocumentOcrPage[];
  readonly metadataSuggestions?: MetadataSuggestions;
  readonly metadataAnalysis?: MetadataAnalysis;
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
    ...(ocr.pages && ocr.pages.length > 0
      ? {
          pages: ocr.pages.map((page) => ({
            pageNumber: page.pageNumber,
            ...(page.originalFileName === undefined
              ? {}
              : { originalFileName: page.originalFileName }),
            ...(page.mimeType === undefined ? {} : { mimeType: page.mimeType }),
            status: page.status,
            ...(page.rawText === undefined ? {} : { rawText: page.rawText }),
          })),
        }
      : {}),
  };
}

function mappedOcrError(error: unknown): AppError {
  if (!(error instanceof OcrEngineError)) return ocrUnavailable(error);
  switch (error.reason) {
    case 'busy':
      return new AppError(
        503,
        'OCR_BUSY',
        'The server is busy processing another document. Please try again in a few moments.',
      );
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
    case 'pdf-too-many-ocr-pages':
      return new AppError(422, 'OCR_PDF_TOO_LARGE', 'This PDF needs OCR on too many pages. Please use a smaller PDF.');
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
  const attachments: PublicDocumentAttachment[] = (
    document.attachments && document.attachments.length > 0
  )
    ? document.attachments.map((a) => ({
        id: a.id,
        originalFileName: a.originalFileName,
        mimeType: a.mimeType,
        fileKind: a.fileKind,
        extension: a.extension,
        sizeBytes: a.sizeBytes,
        order: a.order,
      }))
    : [
        {
          id: '1',
          originalFileName: document.originalFileName,
          mimeType: document.mimeType,
          fileKind: document.fileKind as 'image' | 'pdf',
          extension: document.extension,
          sizeBytes: document.sizeBytes,
          order: 0,
        },
      ];

  return {
    id: document._id.toString(),
    categoryKey: document.categoryKey,
    folderKey: document.folderKey,
    title: document.title,
    documentDate: document.documentDate.toISOString(),
    ...(document.description === undefined ? {} : { description: document.description }),
    ...(document.reflection === undefined ? {} : { reflection: document.reflection }),
    ...(document.scholastic === undefined ? {} : { scholastic: document.scholastic }),
    originalFileName: document.originalFileName,
    mimeType: document.mimeType,
    fileKind: document.fileKind,
    extension: document.extension,
    sizeBytes: document.sizeBytes,
    attachments,
    createdAt: document.createdAt.toISOString(),
    updatedAt: document.updatedAt.toISOString(),
  };
}

const MAX_PREVIEW_OCR_CACHE_ENTRIES = 200;

interface CachedPreviewPageOcr {
  readonly status: 'ready' | 'failed';
  readonly rawText?: string;
  readonly engine: OcrEngineName;
  readonly originalFileName: string;
  readonly mimeType: string;
}

export class DocumentService {
  private readonly recentPreviewOcrBySha256 = new Map<string, CachedPreviewPageOcr>();

  constructor(
    private readonly database: DatabaseConnection,
    private readonly storage: ObjectStorage,
    private readonly ocrEngine: OcrEngine,
    private readonly metadata: AiMetadataService = new AiMetadataService(),
  ) {}

  private recordPreviewPageOcr(sha256: string, entry: CachedPreviewPageOcr): void {
    if (this.recentPreviewOcrBySha256.has(sha256)) {
      this.recentPreviewOcrBySha256.delete(sha256);
    } else if (this.recentPreviewOcrBySha256.size >= MAX_PREVIEW_OCR_CACHE_ENTRIES) {
      const oldestKey = this.recentPreviewOcrBySha256.keys().next().value;
      if (oldestKey !== undefined) {
        this.recentPreviewOcrBySha256.delete(oldestKey);
      }
    }
    this.recentPreviewOcrBySha256.set(sha256, entry);
  }

  async upload(ownerId: Types.ObjectId, input: DocumentUploadInput): Promise<PublicDocument> {
    const rawFiles: readonly DocumentFileInput[] =
      input.files && input.files.length > 0
        ? input.files
        : input.contents && input.originalFileName && input.mimeType
          ? [{ contents: input.contents, originalFileName: input.originalFileName, mimeType: input.mimeType }]
          : [];

    if (rawFiles.length === 0) throw validationError('file', 'must not be empty');
    if (rawFiles.length > MAX_DOCUMENT_ATTACHMENTS) {
      throw validationError('files', `cannot contain more than ${MAX_DOCUMENT_ATTACHMENTS} files`);
    }

    let totalBytes = 0;
    for (const f of rawFiles) {
      if (f.contents.length === 0) throw validationError('file', 'must not be empty');
      if (f.contents.length > MAX_DOCUMENT_FILE_SIZE_BYTES) {
        throw new AppError(413, 'FILE_TOO_LARGE', 'The file exceeds the 15 MB upload limit.');
      }
      totalBytes += f.contents.length;
    }
    if (totalBytes > MAX_COMBINED_DOCUMENT_SIZE_BYTES) {
      throw new AppError(413, 'FILES_TOO_LARGE', 'The combined files exceed the 45 MB upload limit.');
    }

    if (rawFiles.length > 1) {
      for (const f of rawFiles) {
        const leaf = sanitizedFileName(f.originalFileName);
        const type = fileTypeFor(leaf, f.mimeType, f.contents);
        if (type.fileKind !== 'image') {
          throw new AppError(415, 'UNSUPPORTED_FILE_TYPE', 'Multi-page documents support images only (JPG, JPEG, PNG).');
        }
      }
    }

    const categoryKey = normalizedRequired(input.categoryKey, 'categoryKey', 100);
    const folderKey = normalizedRequired(input.folderKey, 'folderKey', 100);
    const title = normalizedRequired(input.title, 'title', 250);
    const description = normalizedOptional(input.description, 'description', 2_000);
    const reflection = normalizedOptional(input.reflection, 'reflection', 5_000);
    const scholastic = validateScholasticDetails(input.scholastic);
    requireTorReflection(categoryKey, folderKey, reflection, scholastic);
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

    const storedAttachments: {
      id: string;
      originalFileName: string;
      objectKey: string;
      mimeType: string;
      fileKind: 'image' | 'pdf';
      extension: string;
      sizeBytes: number;
      sha256: string;
      order: number;
    }[] = [];
    const storedKeys: string[] = [];

    try {
      for (let i = 0; i < rawFiles.length; i++) {
        const file = rawFiles[i];
        if (!file) continue;
        const originalFileName = sanitizedFileName(file.originalFileName);
        const fileType = fileTypeFor(originalFileName, file.mimeType, file.contents);
        const objectKey = `users/${ownerId.toString()}/documents/${randomUUID()}.${fileType.extension}`;
        const stored = await this.storage.put(objectKey, Readable.from([file.contents]));
        if (stored.sizeBytes !== file.contents.length) {
          throw documentUnavailable();
        }
        storedKeys.push(stored.key);
        storedAttachments.push({
          id: String(i + 1),
          originalFileName,
          objectKey: stored.key,
          mimeType: fileType.mimeType,
          fileKind: fileType.fileKind,
          extension: fileType.extension,
          sizeBytes: file.contents.length,
          sha256: createHash('sha256').update(file.contents).digest('hex'),
          order: i,
        });
      }
    } catch (error) {
      for (const key of storedKeys) {
        await this.bestEffortDelete(key);
      }
      if (error instanceof AppError) throw error;
      throw documentUnavailable(error);
    }

    const primary = storedAttachments[0];
    if (!primary) {
      throw documentUnavailable();
    }

    let persistedOcr:
      | {
          status: 'ready';
          rawText: string;
          reviewedText: string;
          engine: OcrEngineName;
          processedAt: Date;
          updatedAt: Date;
          pages: PublicDocumentOcrPage[];
        }
      | undefined;

    if (storedAttachments.some((att) => this.recentPreviewOcrBySha256.has(att.sha256))) {
      const pages: PublicDocumentOcrPage[] = [];
      const textChunks: string[] = [];
      let engine: OcrEngineName = primary.fileKind === 'image' ? 'tesseract.js' : 'pdfjs';
      for (let i = 0; i < storedAttachments.length; i++) {
        const att = storedAttachments[i]!;
        let cached = this.recentPreviewOcrBySha256.get(att.sha256);
        const rawFile = rawFiles[i];
        if (cached === undefined && rawFile !== undefined && att.fileKind === 'image') {
          try {
            const extracted = await this.extractContents({
              contents: rawFile.contents,
              mimeType: att.mimeType,
              fileKind: att.fileKind,
            });
            const pageText = extracted.rawText.trim();
            cached =
              pageText.length > 0
                ? {
                    status: 'ready',
                    rawText: pageText,
                    engine: extracted.engine,
                    originalFileName: att.originalFileName,
                    mimeType: att.mimeType,
                  }
                : {
                    status: 'failed',
                    engine: extracted.engine,
                    originalFileName: att.originalFileName,
                    mimeType: att.mimeType,
                  };
          } catch {
            cached = {
              status: 'failed',
              engine: 'tesseract.js',
              originalFileName: att.originalFileName,
              mimeType: att.mimeType,
            };
          }
          this.recordPreviewPageOcr(att.sha256, cached);
        }

        if (cached && cached.status === 'ready' && cached.rawText && cached.rawText.trim().length > 0) {
          const pageText = cached.rawText.trim();
          engine = cached.engine;
          pages.push({
            pageNumber: i + 1,
            originalFileName: att.originalFileName,
            mimeType: att.mimeType,
            status: 'ready',
            rawText: pageText,
          });
          textChunks.push(
            storedAttachments.length > 1 ? `--- Page ${i + 1} ---\n${pageText}` : pageText,
          );
        } else {
          pages.push({
            pageNumber: i + 1,
            originalFileName: att.originalFileName,
            mimeType: att.mimeType,
            status: 'failed',
          });
        }
      }
      const combinedText = textChunks.join('\n\n');
      if (combinedText.length > 0 && combinedText.length <= OCR_MAX_TEXT_LENGTH) {
        const now = new Date();
        persistedOcr = {
          status: 'ready',
          rawText: combinedText,
          reviewedText: combinedText,
          engine,
          processedAt: now,
          updatedAt: now,
          pages,
        };
      }
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
        ...(scholastic === undefined ? {} : { scholastic }),
        originalFileName: primary.originalFileName,
        objectKey: primary.objectKey,
        mimeType: primary.mimeType,
        fileKind: primary.fileKind,
        extension: primary.extension,
        sizeBytes: primary.sizeBytes,
        sha256: primary.sha256,
        attachments: storedAttachments,
        ...(persistedOcr === undefined ? {} : { ocr: persistedOcr }),
      });
      return publicDocument(created);
    } catch (error) {
      for (const key of storedKeys) {
        await this.bestEffortDelete(key);
      }
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

  async openContent(
    ownerId: Types.ObjectId,
    documentId: string,
    attachmentId?: string,
  ): Promise<DocumentContent> {
    const stored = await this.ownedDocument(ownerId, documentId);
    let targetKey = stored.objectKey;
    let targetMimeType = stored.mimeType;
    let targetFileName = stored.originalFileName;
    let targetSizeBytes = stored.sizeBytes;

    if (attachmentId !== undefined && attachmentId.length > 0) {
      const match = stored.attachments?.find((candidate) => candidate.id === attachmentId);
      if (match === undefined) {
        throw NOT_FOUND;
      }
      targetKey = match.objectKey;
      targetMimeType = match.mimeType;
      targetFileName = match.originalFileName;
      targetSizeBytes = match.sizeBytes;
    }

    try {
      return {
        document: publicDocument(stored),
        contents: await this.storage.get(targetKey),
        mimeType: targetMimeType,
        originalFileName: targetFileName,
        sizeBytes: targetSizeBytes,
      };
    } catch (error) {
      throw documentUnavailable(error);
    }
  }

  async getOcr(ownerId: Types.ObjectId, documentId: string): Promise<PublicDocumentOcr> {
    return this.withSuggestions(publicOcr(await this.ownedDocument(ownerId, documentId)));
  }

  // Pre-upload OCR is transient: no document, object, or guessed metadata is persisted.
  async previewOcr(
    input: DocumentFileInput | readonly DocumentFileInput[],
    requestId?: string,
  ): Promise<PublicDocumentOcr> {
    const rawFiles: readonly DocumentFileInput[] = Array.isArray(input) ? input : [input];
    if (rawFiles.length === 0) throw validationError('file', 'must not be empty');
    if (rawFiles.length > MAX_DOCUMENT_ATTACHMENTS) {
      throw validationError('files', `cannot contain more than ${MAX_DOCUMENT_ATTACHMENTS} files`);
    }

    let totalBytes = 0;
    for (const f of rawFiles) {
      if (f.contents.length === 0) throw validationError('file', 'must not be empty');
      if (f.contents.length > MAX_DOCUMENT_FILE_SIZE_BYTES) {
        throw new AppError(413, 'FILE_TOO_LARGE', 'The file exceeds the 15 MB upload limit.');
      }
      totalBytes += f.contents.length;
    }
    if (totalBytes > MAX_COMBINED_DOCUMENT_SIZE_BYTES) {
      throw new AppError(413, 'FILES_TOO_LARGE', 'The combined files exceed the 45 MB upload limit.');
    }

    if (rawFiles.length > 1) {
      for (const f of rawFiles) {
        const type = fileTypeFor(sanitizedFileName(f.originalFileName), f.mimeType, f.contents);
        if (type.fileKind !== 'image') {
          throw new AppError(415, 'UNSUPPORTED_FILE_TYPE', 'Multi-page preview supports images only (JPG, JPEG, PNG).');
        }
      }
    }

    try {
      const textChunks: string[] = [];
      const pages: PublicDocumentOcrPage[] = [];
      let engine: OcrEngineName = 'tesseract.js';
      let lastPageError: unknown;
      for (let i = 0; i < rawFiles.length; i++) {
        const file = rawFiles[i];
        if (!file) continue;
        const originalFileName = sanitizedFileName(file.originalFileName);
        const type = fileTypeFor(originalFileName, file.mimeType, file.contents);
        const sha256 = createHash('sha256').update(file.contents).digest('hex');
        try {
          const extracted = await this.extractContents({ ...type, contents: file.contents });
          engine = extracted.engine;
          const pageText = extracted.rawText.trim();
          if (pageText.length > 0) {
            pages.push({
              pageNumber: i + 1,
              originalFileName,
              mimeType: type.mimeType,
              status: 'ready',
              rawText: pageText,
            });
            textChunks.push(rawFiles.length > 1 ? `--- Page ${i + 1} ---\n${pageText}` : pageText);
            this.recordPreviewPageOcr(sha256, {
              status: 'ready',
              rawText: pageText,
              engine: extracted.engine,
              originalFileName,
              mimeType: type.mimeType,
            });
          } else {
            pages.push({
              pageNumber: i + 1,
              originalFileName,
              mimeType: type.mimeType,
              status: 'failed',
            });
            this.recordPreviewPageOcr(sha256, {
              status: 'failed',
              engine: extracted.engine,
              originalFileName,
              mimeType: type.mimeType,
            });
          }
        } catch (pageError) {
          if (
            rawFiles.length === 1 ||
            (pageError instanceof OcrEngineError && pageError.reason === 'busy') ||
            (pageError instanceof AppError &&
              (pageError.code === 'OCR_BUSY' || pageError.code === 'OCR_TEXT_TOO_LARGE'))
          ) {
            throw pageError;
          }
          lastPageError = pageError;
          pages.push({
            pageNumber: i + 1,
            originalFileName,
            mimeType: type.mimeType,
            status: 'failed',
          });
          this.recordPreviewPageOcr(sha256, {
            status: 'failed',
            engine,
            originalFileName,
            mimeType: type.mimeType,
          });
        }
      }
      const combinedText = textChunks.join('\n\n');
      if (combinedText.length === 0) {
        if (lastPageError !== undefined) {
          if (lastPageError instanceof AppError) throw lastPageError;
          throw mappedOcrError(lastPageError);
        }
        throw new AppError(422, 'OCR_NO_TEXT_FOUND', 'No readable text was found.');
      }
      if (combinedText.length > OCR_MAX_TEXT_LENGTH) {
        throw new AppError(422, 'OCR_TEXT_TOO_LARGE', 'The extracted text is too large to save.');
      }
      return this.withSuggestions(
        {
          status: 'ready',
          rawText: combinedText,
          reviewedText: combinedText,
          engine,
          pages,
        },
        true,
        requestId,
      );
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
    if (
      'isBusy' in this.ocrEngine &&
      typeof (this.ocrEngine as { isBusy?: () => boolean }).isBusy === 'function' &&
      (this.ocrEngine as { isBusy: () => boolean }).isBusy()
    ) {
      throw new AppError(
        503,
        'OCR_BUSY',
        'The server is busy processing another document. Please try again in a few moments.',
      );
    }

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

    const attachments =
      document.attachments && document.attachments.length > 0
        ? document.attachments
        : [
            {
              id: '1',
              originalFileName: document.originalFileName,
              objectKey: document.objectKey,
              mimeType: document.mimeType,
              fileKind: document.fileKind as 'image' | 'pdf',
              extension: document.extension,
              sizeBytes: document.sizeBytes,
              order: 0,
            },
          ];

    try {
      const textChunks: string[] = [];
      const pages: PublicDocumentOcrPage[] = [];
      let lastPageError: unknown;
      for (let i = 0; i < attachments.length; i++) {
        const att = attachments[i];
        if (!att) continue;
        const stream = await this.storage.get(att.objectKey);
        const contents = await readableToBoundedBuffer(stream, MAX_DOCUMENT_FILE_SIZE_BYTES);
        try {
          const extracted = await this.extractContents({
            contents,
            mimeType: att.mimeType,
            fileKind: att.fileKind,
            documentId: document._id.toHexString(),
          });
          const pageText = extracted.rawText.trim();
          if (pageText.length > 0) {
            pages.push({
              pageNumber: i + 1,
              originalFileName: att.originalFileName,
              mimeType: att.mimeType,
              status: 'ready',
              rawText: pageText,
            });
            textChunks.push(
              attachments.length > 1 ? `--- Page ${i + 1} ---\n${pageText}` : pageText,
            );
          } else {
            pages.push({
              pageNumber: i + 1,
              originalFileName: att.originalFileName,
              mimeType: att.mimeType,
              status: 'failed',
            });
          }
        } catch (pageError) {
          if (
            attachments.length === 1 ||
            (pageError instanceof OcrEngineError && pageError.reason === 'busy') ||
            (pageError instanceof AppError &&
              (pageError.code === 'OCR_BUSY' || pageError.code === 'OCR_TEXT_TOO_LARGE'))
          ) {
            throw pageError;
          }
          lastPageError = pageError;
          pages.push({
            pageNumber: i + 1,
            originalFileName: att.originalFileName,
            mimeType: att.mimeType,
            status: 'failed',
          });
        }
      }
      const combinedText = textChunks.join('\n\n');
      if (combinedText.length === 0) {
        if (lastPageError !== undefined) {
          if (lastPageError instanceof AppError) throw lastPageError;
          throw mappedOcrError(lastPageError);
        }
        throw new AppError(422, 'OCR_NO_TEXT_FOUND', 'No readable text was found.');
      }
      if (combinedText.length > OCR_MAX_TEXT_LENGTH) {
        throw new AppError(422, 'OCR_TEXT_TOO_LARGE', 'The extracted text is too large to save.');
      }
      const completed = await repositories.documents.completeOcr(
        ownerId,
        document._id,
        processingId,
        {
          rawText: combinedText,
          engine,
          processedAt: new Date(),
          pages,
        },
      );
      if (completed === null) throw ocrUnavailable();
      return this.withSuggestions(publicOcr(completed));
    } catch (error) {
      const isBusy =
        (error instanceof OcrEngineError && error.reason === 'busy') ||
        (error instanceof AppError && error.code === 'OCR_BUSY');

      if (isBusy) {
        try {
          await repositories.documents.releaseOcrClaim(
            ownerId,
            document._id,
            processingId,
            document.ocr?.status,
          );
        } catch {
          // Preserve the extraction error; release state is best-effort only.
        }
        throw new AppError(
          503,
          'OCR_BUSY',
          'The server is busy processing another document. Please try again in a few moments.',
        );
      }

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
    if (extracted.pages?.some((page) => page.status === 'unresolved')) {
      throw new AppError(422, 'COMPILED_UNRESOLVED_PAGES', 'Some PDF pages could not be read. Retry or review this PDF before saving extracted text.');
    }
    if (extracted.rawText.length === 0) {
      throw new AppError(422, 'OCR_NO_TEXT_FOUND', 'No readable text was found.');
    }
    if (extracted.rawText.length > OCR_MAX_TEXT_LENGTH) {
      throw new AppError(422, 'OCR_TEXT_TOO_LARGE', 'The extracted text is too large to save.');
    }
    return extracted;
  }

  private async withSuggestions(ocr: PublicDocumentOcr, analyze = false, requestId?: string): Promise<PublicDocumentOcr> {
    if (ocr.status !== 'ready') return ocr;
    let categories: readonly PublicDocumentCategory[] = [];
    try {
      categories = await this.listCategories();
    } catch {
      // An unavailable category list must not discard successful OCR. Text fields
      // remain useful; no category or folder will be invented as a fallback.
    }
    // Paid AI analysis is only invoked by the authenticated, rate-limited preview.
    if (analyze) return { ...ocr, ...await this.metadata.recommend(ocr, categories, requestId) };
    return { ...ocr, metadataSuggestions: suggestDocumentMetadata(ocr, categories) };
  }

  async updateMetadata(
    ownerId: Types.ObjectId,
    documentId: string,
    input: {
      readonly categoryKey?: string;
      readonly folderKey?: string;
      readonly title?: string;
      readonly documentDate?: string;
      readonly description?: string;
      readonly reflection?: string;
      readonly scholastic?: ScholasticDetails;
    },
  ): Promise<PublicDocument> {
    const document = await this.ownedDocument(ownerId, documentId);
    const repositories = this.repositories();

    let categoryKey = document.categoryKey;
    let folderKey = document.folderKey;

    if (input.categoryKey !== undefined) {
      categoryKey = normalizedRequired(input.categoryKey, 'categoryKey', 100);
      const category = await repositories.documentCategories.findByKey(categoryKey);
      if (category === null || !category.active) {
        throw validationError('categoryKey', 'must identify an active document category');
      }
      if (input.folderKey !== undefined) {
        folderKey = normalizedRequired(input.folderKey, 'folderKey', 100);
      }
      if (!category.folders.some((folder) => folder.active && folder.key === folderKey)) {
        throw validationError('folderKey', 'must belong to the selected document category');
      }
    } else if (input.folderKey !== undefined) {
      folderKey = normalizedRequired(input.folderKey, 'folderKey', 100);
      const category = await repositories.documentCategories.findByKey(categoryKey);
      if (
        category === null ||
        !category.active ||
        !category.folders.some((folder) => folder.active && folder.key === folderKey)
      ) {
        throw validationError('folderKey', 'must belong to the selected document category');
      }
    }

    const title = input.title !== undefined ? normalizedRequired(input.title, 'title', 250) : document.title;
    const date = input.documentDate !== undefined ? documentDate(input.documentDate) : document.documentDate;
    const description = input.description !== undefined ? normalizedOptional(input.description, 'description', 2_000) : document.description;
    const reflection = input.reflection !== undefined ? (normalizedOptional(input.reflection, 'reflection', 5_000) ?? '') : document.reflection;
    const scholastic = validateScholasticDetails(input.scholastic ?? document.scholastic);
    requireTorReflection(categoryKey, folderKey, reflection, scholastic);

    const updated = await repositories.documents.updateByIdForOwner(ownerId, document._id, {
      categoryKey,
      folderKey,
      title,
      documentDate: date,
      ...(description !== undefined ? { description } : {}),
      ...(reflection !== undefined ? { reflection } : {}),
      ...(scholastic !== undefined ? { scholastic } : {}),
    });
    if (updated === null) throw documentUnavailable();
    return publicDocument(updated);
  }

  async delete(ownerId: Types.ObjectId, documentId: string): Promise<void> {
    const document = await this.ownedDocument(ownerId, documentId);
    const keysToDelete = new Set<string>();
    if (document.objectKey) keysToDelete.add(document.objectKey);
    if (document.attachments) {
      for (const att of document.attachments) {
        if (att.objectKey) keysToDelete.add(att.objectKey);
      }
    }
    for (const key of keysToDelete) {
      try {
        await this.storage.delete(key);
      } catch (error) {
        throw documentUnavailable(error);
      }
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
