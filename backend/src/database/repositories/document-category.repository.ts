import type { Model, Types } from 'mongoose';
import type { DocumentCategory } from '../models/index.js';
import {
  asPersistedRecord,
  type CreateRecord,
  type PersistedRecord,
  type UpdateRecord,
} from './repository.types.js';

export type DocumentCategoryRecord = PersistedRecord<DocumentCategory>;
export type CreateDocumentCategoryInput = CreateRecord<DocumentCategory>;
export type UpdateDocumentCategoryInput = UpdateRecord<DocumentCategory>;

export class DocumentCategoryRepository {
  constructor(private readonly model: Model<DocumentCategory>) {}

  async create(input: CreateDocumentCategoryInput): Promise<DocumentCategoryRecord> {
    const created = await this.model.create(input);
    return asPersistedRecord<DocumentCategory>(created.toObject());
  }

  async findById(id: Types.ObjectId): Promise<DocumentCategoryRecord | null> {
    const found = await this.model.findById(id).lean().exec();
    return found === null ? null : asPersistedRecord<DocumentCategory>(found);
  }

  async findByKey(key: string): Promise<DocumentCategoryRecord | null> {
    const found = await this.model.findOne({ key }).lean().exec();
    return found === null ? null : asPersistedRecord<DocumentCategory>(found);
  }

  async listActive(): Promise<readonly DocumentCategoryRecord[]> {
    const found = await this.model.find({ active: true }).sort({ sortOrder: 1 }).lean().exec();
    return found.map((value) => asPersistedRecord<DocumentCategory>(value));
  }

  async updateById(
    id: Types.ObjectId,
    patch: UpdateDocumentCategoryInput,
  ): Promise<DocumentCategoryRecord | null> {
    const updated = await this.model
      .findByIdAndUpdate(
        id,
        { $set: patch },
        { returnDocument: 'after', runValidators: true, strict: 'throw' },
      )
      .lean()
      .exec();
    return updated === null ? null : asPersistedRecord<DocumentCategory>(updated);
  }

  async deleteById(id: Types.ObjectId): Promise<boolean> {
    const result = await this.model.deleteOne({ _id: id });
    return result.deletedCount === 1;
  }
}
