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
