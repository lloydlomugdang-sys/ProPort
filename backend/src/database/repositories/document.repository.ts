import type { Model, Types } from 'mongoose';
import type { Document } from '../models/index.js';
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

  async listForOwner(ownerId: Types.ObjectId, limit = 50): Promise<readonly DocumentRecord[]> {
    const found = await this.model
      .find({ ownerId })
      .sort({ createdAt: -1 })
      .limit(boundedLimit(limit))
      .lean()
      .exec();
    return found.map((value) => asPersistedRecord<Document>(value));
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

  async deleteByIdForOwner(ownerId: Types.ObjectId, id: Types.ObjectId): Promise<boolean> {
    const result = await this.model.deleteOne({ _id: id, ownerId });
    return result.deletedCount === 1;
  }
}
