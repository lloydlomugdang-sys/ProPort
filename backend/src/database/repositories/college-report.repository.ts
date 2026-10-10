import type { Model, Types } from 'mongoose';
import type { CollegeReport } from '../models/index.js';
import {
  asPersistedRecord,
  boundedLimit,
  type CreateRecord,
  type PersistedRecord,
  type UpdateRecord,
} from './repository.types.js';

export type CollegeReportRecord = PersistedRecord<CollegeReport>;
export type CreateCollegeReportInput = CreateRecord<CollegeReport>;
export type UpdateCollegeReportInput = UpdateRecord<CollegeReport>;

export class CollegeReportRepository {
  constructor(private readonly model: Model<CollegeReport>) {}

  async findCurrentForOwner(ownerId: Types.ObjectId, templateId: Types.ObjectId): Promise<CollegeReportRecord | null> {
    const found = await this.model.findOne({ ownerId, templateId, academicYear: 'current' }).lean().exec();
    return found === null ? null : asPersistedRecord<CollegeReport>(found);
  }

  async hasLegacyForOwner(ownerId: Types.ObjectId, templateId?: Types.ObjectId): Promise<boolean> {
    return (await this.model.exists({ ownerId, ...(templateId ? { templateId: { $ne: templateId } } : {}) })) !== null;
  }

  async saveCurrentForOwner(
    ownerId: Types.ObjectId, templateId: Types.ObjectId,
    patch: Pick<CollegeReport, 'answers' | 'essay' | 'questionnaireVersion'>,
  ): Promise<CollegeReportRecord> {
    const filter = { ownerId, templateId, academicYear: 'current' };
    const update = { $set: patch, $setOnInsert: { ...filter, status: 'draft' } };
    try {
      const saved = await this.model.findOneAndUpdate(filter, update,
        { upsert: true, returnDocument: 'after', runValidators: true, strict: 'throw' }).lean().exec();
      return asPersistedRecord<CollegeReport>(saved!);
    } catch (error) {
      // Concurrent initial saves still share the existing owner/template/year index.
      if (!(typeof error === 'object' && error !== null && 'code' in error && error.code === 11000)) throw error;
      const saved = await this.model.findOneAndUpdate(filter, update,
        { returnDocument: 'after', runValidators: true, strict: 'throw' }).lean().exec();
      if (!saved) throw error;
      return asPersistedRecord<CollegeReport>(saved);
    }
  }

  async create(input: CreateCollegeReportInput): Promise<CollegeReportRecord> {
    const created = await this.model.create(input);
    return asPersistedRecord<CollegeReport>(created.toObject());
  }

  async findByIdForOwner(
    ownerId: Types.ObjectId,
    id: Types.ObjectId,
  ): Promise<CollegeReportRecord | null> {
    const found = await this.model.findOne({ _id: id, ownerId }).lean().exec();
    return found === null ? null : asPersistedRecord<CollegeReport>(found);
  }

  async listForOwner(
    ownerId: Types.ObjectId,
    limit = 50,
  ): Promise<readonly CollegeReportRecord[]> {
    const found = await this.model
      .find({ ownerId })
      .sort({ createdAt: -1 })
      .limit(boundedLimit(limit))
      .lean()
      .exec();
    return found.map((value) => asPersistedRecord<CollegeReport>(value));
  }

  async updateByIdForOwner(
    ownerId: Types.ObjectId,
    id: Types.ObjectId,
    patch: UpdateCollegeReportInput,
  ): Promise<CollegeReportRecord | null> {
    const updated = await this.model
      .findOneAndUpdate(
        { _id: id, ownerId },
        { $set: patch },
        { returnDocument: 'after', runValidators: true, strict: 'throw' },
      )
      .lean()
      .exec();
    return updated === null ? null : asPersistedRecord<CollegeReport>(updated);
  }

  async deleteByIdForOwner(ownerId: Types.ObjectId, id: Types.ObjectId): Promise<boolean> {
    const result = await this.model.deleteOne({ _id: id, ownerId });
    return result.deletedCount === 1;
  }
}
