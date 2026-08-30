import type { Model, Types } from 'mongoose';
import type { Session } from '../models/index.js';
import {
  asPersistedRecord,
  boundedLimit,
  type CreateRecord,
  type PersistedRecord,
  type UpdateRecord,
} from './repository.types.js';

export type SafeSession = Omit<Session, 'refreshTokenHash'>;
export type SafeSessionRecord = PersistedRecord<SafeSession>;
export type CreateSessionInput = CreateRecord<Session>;
export type UpdateSessionInput = UpdateRecord<Session>;

function safeSession(value: unknown): SafeSessionRecord {
  const { refreshTokenHash: _refreshTokenHash, ...safe } = value as Record<string, unknown>;
  return asPersistedRecord<SafeSession>(safe);
}

export class SessionRepository {
  constructor(private readonly model: Model<Session>) {}

  async create(input: CreateSessionInput): Promise<SafeSessionRecord> {
    const created = await this.model.create(input);
    return safeSession(created.toObject());
  }

  async findByIdForUser(
    userId: Types.ObjectId,
    id: Types.ObjectId,
  ): Promise<SafeSessionRecord | null> {
    const found = await this.model
      .findOne({ _id: id, userId })
      .select('-refreshTokenHash')
      .lean()
      .exec();
    return found === null ? null : safeSession(found);
  }

  async listForUser(userId: Types.ObjectId, limit = 50): Promise<readonly SafeSessionRecord[]> {
    const found = await this.model
      .find({ userId })
      .select('-refreshTokenHash')
      .sort({ createdAt: -1 })
      .limit(boundedLimit(limit))
      .lean()
      .exec();
    return found.map(safeSession);
  }

  async updateByIdForUser(
    userId: Types.ObjectId,
    id: Types.ObjectId,
    patch: UpdateSessionInput,
  ): Promise<SafeSessionRecord | null> {
    const updated = await this.model
      .findOneAndUpdate(
        { _id: id, userId },
        { $set: patch },
        { returnDocument: 'after', runValidators: true, strict: 'throw' },
      )
      .select('-refreshTokenHash')
      .lean()
      .exec();
    return updated === null ? null : safeSession(updated);
  }

  async deleteByIdForUser(userId: Types.ObjectId, id: Types.ObjectId): Promise<boolean> {
    const result = await this.model.deleteOne({ _id: id, userId });
    return result.deletedCount === 1;
  }
}
