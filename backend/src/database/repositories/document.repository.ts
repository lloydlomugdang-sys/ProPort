import type { Model, Types } from 'mongoose';
import type { Document, OcrEngineName, OcrStatus } from '../models/index.js';
import {
  asPersistedRecord,
  boundedLimit,
  RepositoryInputError,
  type CreateRecord,
  type PersistedRecord,
  type UpdateRecord,
} from './repository.types.js';

export type DocumentRecord = PersistedRecord<Document>;
export type CreateDocumentInput = CreateRecord<Document>;
export type UpdateDocumentInput = UpdateRecord<Document>;

export interface DocumentCountSummary {
  readonly totalCount: number;
  readonly categoryCounts: Readonly<Record<string, number>>;
  readonly folderCounts: Readonly<Record<string, number>>;
}

export interface OcrProcessingClaim {
  readonly processingId: string;
  readonly engine: OcrEngineName;
  readonly now: Date;
  readonly expiresAt: Date;
}

const FORBIDDEN_CONTENT_KEYS = new Set([
  'base64',
  'base64data',
  'binary',
  'chunks',
  'content',
  'dataurl',
  'filebytes',
  'filedata',
  'gridfsid',
]);

function normalizedKey(key: string): string {
  return key.replace(/[-_]/g, '').toLowerCase();
}

function assertNoEmbeddedContent(value: unknown, seen = new Set<object>()): void {
  if (Buffer.isBuffer(value) || value instanceof ArrayBuffer || ArrayBuffer.isView(value)) {
    throw new RepositoryInputError('Document records cannot contain binary file content.');
  }
  if (typeof value === 'string' && value.trimStart().toLowerCase().startsWith('data:')) {
    throw new RepositoryInputError('Document records cannot contain data URLs.');
  }
  if (Array.isArray(value)) {
    for (const entry of value) {
      assertNoEmbeddedContent(entry, seen);
    }
    return;
  }
  if (typeof value !== 'object' || value === null || value instanceof Date || seen.has(value)) {
    return;
  }
  const prototype = Object.getPrototypeOf(value) as object | null;
  if (prototype !== Object.prototype && prototype !== null) {
    return;
  }
  seen.add(value);
  for (const [key, nested] of Object.entries(value)) {
    if (FORBIDDEN_CONTENT_KEYS.has(normalizedKey(key))) {
      throw new RepositoryInputError(`Document field ${key} cannot store file content.`);
    }
    assertNoEmbeddedContent(nested, seen);
  }
}

export class DocumentRepository {
  constructor(private readonly model: Model<Document>) {}

  async create(input: CreateDocumentInput): Promise<DocumentRecord> {
    assertNoEmbeddedContent(input);
    const created = await this.model.create(input);
    return asPersistedRecord<Document>(created.toObject());
  }

  async findByIdForOwner(
    ownerId: Types.ObjectId,
    id: Types.ObjectId,
  ): Promise<DocumentRecord | null> {
    const found = await this.model.findOne({ _id: id, ownerId }).lean().exec();
    return found === null ? null : asPersistedRecord<Document>(found);
  }

  async listForOwner(ownerId: Types.ObjectId, limit = 100): Promise<readonly DocumentRecord[]> {
    const found = await this.model
      .find({ ownerId })
      .sort({ createdAt: -1 })
      .limit(boundedLimit(limit))
      .lean()
      .exec();
    return found.map((value) => asPersistedRecord<Document>(value));
  }

  async countForOwner(ownerId: Types.ObjectId): Promise<DocumentCountSummary> {
    const rows = await this.model
      .aggregate<{
        readonly categoryKey: string;
        readonly folderKey: string;
        readonly count: number;
      }>([
        { $match: { ownerId } },
        {
          $group: {
            _id: { categoryKey: '$categoryKey', folderKey: '$folderKey' },
            count: { $sum: 1 },
          },
        },
        {
          $project: {
            _id: 0,
            categoryKey: '$_id.categoryKey',
            folderKey: '$_id.folderKey',
            count: 1,
          },
        },
      ])
      .exec();
    const categoryCounts: Record<string, number> = {};
    const folderCounts: Record<string, number> = {};
    let totalCount = 0;
    for (const row of rows) {
      totalCount += row.count;
      categoryCounts[row.categoryKey] = (categoryCounts[row.categoryKey] ?? 0) + row.count;
      const folder = `${row.categoryKey}/${row.folderKey}`;
      folderCounts[folder] = (folderCounts[folder] ?? 0) + row.count;
    }
    return { totalCount, categoryCounts, folderCounts };
  }

  async updateByIdForOwner(
    ownerId: Types.ObjectId,
    id: Types.ObjectId,
    patch: UpdateDocumentInput,
  ): Promise<DocumentRecord | null> {
    assertNoEmbeddedContent(patch);
    const updated = await this.model
      .findOneAndUpdate(
        { _id: id, ownerId },
        { $set: patch },
        { returnDocument: 'after', runValidators: true, strict: 'throw' },
      )
      .lean()
      .exec();
    return updated === null ? null : asPersistedRecord<Document>(updated);
  }

  async claimOcrForProcessing(
    ownerId: Types.ObjectId,
    id: Types.ObjectId,
    claim: OcrProcessingClaim,
  ): Promise<boolean> {
    const result = await this.model.updateOne(
      {
        _id: id,
        ownerId,
        $or: [
          { 'ocr.status': { $ne: 'processing' } },
          { 'ocr.processingExpiresAt': { $lte: claim.now } },
        ],
      },
      {
        $set: {
          'ocr.status': 'processing',
          'ocr.engine': claim.engine,
          'ocr.updatedAt': claim.now,
          'ocr.processingId': claim.processingId,
          'ocr.processingExpiresAt': claim.expiresAt,
        },
      },
      { runValidators: true, strict: 'throw' },
    );
    return result.matchedCount === 1;
  }

  async completeOcr(
    ownerId: Types.ObjectId,
    id: Types.ObjectId,
    processingId: string,
    input: {
      readonly rawText: string;
      readonly engine: OcrEngineName;
      readonly processedAt: Date;
    },
  ): Promise<DocumentRecord | null> {
    const updated = await this.model
      .findOneAndUpdate(
        { _id: id, ownerId, 'ocr.status': 'processing', 'ocr.processingId': processingId },
        {
          $set: {
            ocr: {
              status: 'ready',
              rawText: input.rawText,
              reviewedText: input.rawText,
              engine: input.engine,
              processedAt: input.processedAt,
              updatedAt: input.processedAt,
            },
          },
        },
        { returnDocument: 'after', runValidators: true, strict: 'throw' },
      )
      .lean()
      .exec();
    return updated === null ? null : asPersistedRecord<Document>(updated);
  }

  async failOcr(
    ownerId: Types.ObjectId,
    id: Types.ObjectId,
    processingId: string,
    engine: OcrEngineName,
    failedAt: Date,
  ): Promise<void> {
    await this.model.updateOne(
      { _id: id, ownerId, 'ocr.status': 'processing', 'ocr.processingId': processingId },
      { $set: { ocr: { status: 'failed', engine, updatedAt: failedAt } } },
      { runValidators: true, strict: 'throw' },
    );
  }

  async releaseOcrClaim(
    ownerId: Types.ObjectId,
    id: Types.ObjectId,
    processingId: string,
    previousStatus?: OcrStatus,
  ): Promise<void> {
    if (previousStatus === 'ready') {
      await this.model.updateOne(
        { _id: id, ownerId, 'ocr.status': 'processing', 'ocr.processingId': processingId },
        {
          $set: {
            'ocr.status': 'ready',
            'ocr.updatedAt': new Date(),
          },
          $unset: {
            'ocr.processingId': 1,
            'ocr.processingExpiresAt': 1,
          },
        },
        { runValidators: true, strict: 'throw' },
      );
    } else {
      await this.model.updateOne(
        { _id: id, ownerId, 'ocr.status': 'processing', 'ocr.processingId': processingId },
        {
          $unset: {
            ocr: 1,
          },
        },
        { runValidators: true, strict: 'throw' },
      );
    }
  }

  async updateReviewedOcrText(
    ownerId: Types.ObjectId,
    id: Types.ObjectId,
    reviewedText: string,
    updatedAt: Date,
  ): Promise<DocumentRecord | null> {
    const updated = await this.model
      .findOneAndUpdate(
        { _id: id, ownerId, 'ocr.status': 'ready' },
        { $set: { 'ocr.reviewedText': reviewedText, 'ocr.updatedAt': updatedAt } },
        { returnDocument: 'after', runValidators: true, strict: 'throw' },
      )
      .lean()
      .exec();
    return updated === null ? null : asPersistedRecord<Document>(updated);
  }

  async deleteByIdForOwner(ownerId: Types.ObjectId, id: Types.ObjectId): Promise<boolean> {
    const result = await this.model.deleteOne({ _id: id, ownerId });
    return result.deletedCount === 1;
  }
}
