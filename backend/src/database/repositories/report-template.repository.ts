import type { Model, Types } from 'mongoose';
import type { ReportTemplate } from '../models/index.js';
import {
  asPersistedRecord,
  type CreateRecord,
  type PersistedRecord,
  type UpdateRecord,
} from './repository.types.js';

export type ReportTemplateRecord = PersistedRecord<ReportTemplate>;
export type CreateReportTemplateInput = CreateRecord<ReportTemplate>;
export type UpdateReportTemplateInput = UpdateRecord<ReportTemplate>;

export class ReportTemplateRepository {
  constructor(private readonly model: Model<ReportTemplate>) {}

  async create(input: CreateReportTemplateInput): Promise<ReportTemplateRecord> {
    const created = await this.model.create(input);
    return asPersistedRecord<ReportTemplate>(created.toObject());
  }

  async findById(id: Types.ObjectId): Promise<ReportTemplateRecord | null> {
    const found = await this.model.findById(id).lean().exec();
    return found === null ? null : asPersistedRecord<ReportTemplate>(found);
  }

  async findByKeyVersion(key: string, version: number): Promise<ReportTemplateRecord | null> {
    const found = await this.model.findOne({ key, version }).lean().exec();
    return found === null ? null : asPersistedRecord<ReportTemplate>(found);
  }

  async listActive(): Promise<readonly ReportTemplateRecord[]> {
    const found = await this.model.find({ active: true }).sort({ key: 1, version: -1 }).lean().exec();
    return found.map((value) => asPersistedRecord<ReportTemplate>(value));
  }

  async updateById(
    id: Types.ObjectId,
    patch: UpdateReportTemplateInput,
  ): Promise<ReportTemplateRecord | null> {
    const updated = await this.model
      .findByIdAndUpdate(
        id,
        { $set: patch },
        { returnDocument: 'after', runValidators: true, strict: 'throw' },
      )
      .lean()
      .exec();
    return updated === null ? null : asPersistedRecord<ReportTemplate>(updated);
  }

  async deleteById(id: Types.ObjectId): Promise<boolean> {
    const result = await this.model.deleteOne({ _id: id });
    return result.deletedCount === 1;
  }
}
