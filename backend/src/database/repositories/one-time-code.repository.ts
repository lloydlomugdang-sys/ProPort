import type { ClientSession, Model, Types } from 'mongoose';
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
export type SensitiveOneTimeCodeRecord = PersistedRecord<OneTimeCode>;

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

  async findLatestForUserAndType(
    userId: Types.ObjectId,
    type: OneTimeCode['type'],
  ): Promise<SafeOneTimeCodeRecord | null> {
    const found = await this.model
      .findOne({ userId, type })
      .select('-codeHash')
      .sort({ createdAt: -1 })
      .lean()
      .exec();
    return found === null ? null : safeOneTimeCode(found);
  }

  /** Authentication-only lookup. Callers must never return or log this record. */
  async findLatestActiveWithHash(
    userId: Types.ObjectId,
    type: OneTimeCode['type'],
    now: Date,
    maximumAttempts: number,
  ): Promise<SensitiveOneTimeCodeRecord | null> {
    const found = await this.model
      .findOne({
        userId,
        type,
        consumedAt: { $exists: false },
        expiresAt: { $gt: now },
        attempts: { $lt: maximumAttempts },
      })
      .select('+codeHash')
      .sort({ createdAt: -1 })
      .lean()
      .exec();
    return found === null ? null : asPersistedRecord<OneTimeCode>(found);
  }

  async incrementAttempts(
    userId: Types.ObjectId,
    id: Types.ObjectId,
    now: Date,
    maximumAttempts: number,
  ): Promise<boolean> {
    const result = await this.model
      .updateOne(
        {
          _id: id,
          userId,
          consumedAt: { $exists: false },
          expiresAt: { $gt: now },
          attempts: { $lt: maximumAttempts },
        },
        { $inc: { attempts: 1 } },
      )
      .exec();
    return result.modifiedCount === 1;
  }

  async consume(
    userId: Types.ObjectId,
    id: Types.ObjectId,
    now: Date,
    maximumAttempts: number,
    session?: ClientSession,
  ): Promise<boolean> {
    const result = await this.model
      .updateOne(
        {
          _id: id,
          userId,
          consumedAt: { $exists: false },
          expiresAt: { $gt: now },
          attempts: { $lt: maximumAttempts },
        },
        { $set: { consumedAt: now } },
        session === undefined ? {} : { session },
      )
      .exec();
    return result.modifiedCount === 1;
  }

  async consumeActiveByHash(
    type: OneTimeCode['type'],
    codeHash: string,
    now: Date,
  ): Promise<SafeOneTimeCodeRecord | null> {
    const consumed = await this.model
      .findOneAndUpdate(
        {
          type,
          codeHash,
          consumedAt: { $exists: false },
          expiresAt: { $gt: now },
        },
        { $set: { consumedAt: now } },
        { returnDocument: 'after' },
      )
      .select('-codeHash')
      .lean()
      .exec();
    return consumed === null ? null : safeOneTimeCode(consumed);
  }

  async invalidateActiveForUserAndType(
    userId: Types.ObjectId,
    type: OneTimeCode['type'],
    invalidatedAt: Date,
  ): Promise<number> {
    const result = await this.model
      .updateMany(
        { userId, type, consumedAt: { $exists: false } },
        { $set: { consumedAt: invalidatedAt } },
      )
      .exec();
    return result.modifiedCount;
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
