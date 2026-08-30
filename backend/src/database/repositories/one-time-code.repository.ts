import type { Model, Types } from 'mongoose';
import type { OneTimeCode } from '../models/index.js';
import {
  asPersistedRecord,
  boundedLimit,
  type CreateRecord,
  type PersistedRecord,
  type UpdateRecord,
} from './repository.types.js';

export type SafeOneTimeCode = Omit<OneTimeCode, 'codeHash'>;
export type SafeOneTimeCodeRecord = PersistedRecord<SafeOneTimeCode>;
export type CreateOneTimeCodeInput = CreateRecord<OneTimeCode>;
export type UpdateOneTimeCodeInput = UpdateRecord<OneTimeCode>;

function safeOneTimeCode(value: unknown): SafeOneTimeCodeRecord {
  const { codeHash: _codeHash, ...safe } = value as Record<string, unknown>;
  return asPersistedRecord<SafeOneTimeCode>(safe);
}

export class OneTimeCodeRepository {
  constructor(private readonly model: Model<OneTimeCode>) {}

  async create(input: CreateOneTimeCodeInput): Promise<SafeOneTimeCodeRecord> {
    const created = await this.model.create(input);
    return safeOneTimeCode(created.toObject());
  }

  async findByIdForUser(
    userId: Types.ObjectId,
    id: Types.ObjectId,
  ): Promise<SafeOneTimeCodeRecord | null> {
    const found = await this.model
      .findOne({ _id: id, userId })
      .select('-codeHash')
      .lean()
      .exec();
    return found === null ? null : safeOneTimeCode(found);
  }

  async listForUser(
    userId: Types.ObjectId,
    limit = 50,
  ): Promise<readonly SafeOneTimeCodeRecord[]> {
    const found = await this.model
      .find({ userId })
      .select('-codeHash')
      .sort({ createdAt: -1 })
      .limit(boundedLimit(limit))
      .lean()
      .exec();
    return found.map(safeOneTimeCode);
  }

  async updateByIdForUser(
    userId: Types.ObjectId,
    id: Types.ObjectId,
    patch: UpdateOneTimeCodeInput,
  ): Promise<SafeOneTimeCodeRecord | null> {
    const updated = await this.model
      .findOneAndUpdate(
        { _id: id, userId },
        { $set: patch },
        { returnDocument: 'after', runValidators: true, strict: 'throw' },
      )
      .select('-codeHash')
      .lean()
      .exec();
    return updated === null ? null : safeOneTimeCode(updated);
  }

  async deleteByIdForUser(userId: Types.ObjectId, id: Types.ObjectId): Promise<boolean> {
    const result = await this.model.deleteOne({ _id: id, userId });
    return result.deletedCount === 1;
  }
}
