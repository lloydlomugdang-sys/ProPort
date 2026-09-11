import type { Model, Types } from 'mongoose';
import type { Portfolio } from '../models/index.js';
import {
  asPersistedRecord,
  boundedLimit,
  type CreateRecord,
  type PersistedRecord,
  type UpdateRecord,
} from './repository.types.js';

export type PortfolioRecord = PersistedRecord<Portfolio>;
export type CreatePortfolioInput = CreateRecord<Portfolio>;
export type UpdatePortfolioInput = UpdateRecord<Portfolio>;

export class PortfolioRepository {
  constructor(private readonly model: Model<Portfolio>) {}

  async create(input: CreatePortfolioInput): Promise<PortfolioRecord> {
    const created = await this.model.create(input);
    return asPersistedRecord<Portfolio>(created.toObject());
  }

  async listForOwner(
    ownerId: Types.ObjectId,
    limit = 100,
  ): Promise<readonly PortfolioRecord[]> {
    const found = await this.model
      .find({ ownerId })
      .sort({ updatedAt: -1 })
      .limit(boundedLimit(limit))
      .lean()
      .exec();
    return found.map((value) => asPersistedRecord<Portfolio>(value));
  }

  async findByIdForOwner(
    ownerId: Types.ObjectId,
    id: Types.ObjectId,
  ): Promise<PortfolioRecord | null> {
    const found = await this.model.findOne({ _id: id, ownerId }).lean().exec();
    return found === null ? null : asPersistedRecord<Portfolio>(found);
  }

  async updateByIdForOwner(
    ownerId: Types.ObjectId,
    id: Types.ObjectId,
    patch: UpdatePortfolioInput,
  ): Promise<PortfolioRecord | null> {
    const updated = await this.model
      .findOneAndUpdate(
        { _id: id, ownerId },
        { $set: patch },
        { returnDocument: 'after', runValidators: true, strict: 'throw' },
      )
      .lean()
      .exec();
    return updated === null ? null : asPersistedRecord<Portfolio>(updated);
  }

  async deleteByIdForOwner(ownerId: Types.ObjectId, id: Types.ObjectId): Promise<boolean> {
    const result = await this.model.deleteOne({ _id: id, ownerId });
    return result.deletedCount === 1;
  }
}
