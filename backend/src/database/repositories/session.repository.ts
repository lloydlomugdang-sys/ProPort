import type { ClientSession, Model, Types } from 'mongoose';
import { Types as MongooseTypes } from 'mongoose';
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

export class SessionRotationConflictError extends Error {
  override readonly name = 'SessionRotationConflictError';
}

function safeSession(value: unknown): SafeSessionRecord {
  const { refreshTokenHash: _refreshTokenHash, ...safe } = value as Record<string, unknown>;
  return asPersistedRecord<SafeSession>(safe);
}

export class SessionRepository {
  constructor(private readonly model: Model<Session>) {}

  async create(input: CreateSessionInput, session?: ClientSession): Promise<SafeSessionRecord> {
    const created = session === undefined ? await this.model.create(input)
      : (await this.model.create([input], { session }))[0]!;
    return safeSession(created.toObject());
  }

  async findByRefreshTokenHash(refreshTokenHash: string): Promise<SafeSessionRecord | null> {
    const found = await this.model
      .findOne({ refreshTokenHash })
      .select('-refreshTokenHash')
      .lean()
      .exec();
    return found === null ? null : safeSession(found);
  }

  async rotate(
    currentId: Types.ObjectId,
    replacement: CreateSessionInput,
    rotatedAt: Date,
  ): Promise<SafeSessionRecord> {
    const databaseSession = await this.model.db.startSession();
    const replacementId = new MongooseTypes.ObjectId();
    let created: SafeSessionRecord | undefined;

    try {
      await databaseSession.withTransaction(async () => {
        const updated = await this.model
          .findOneAndUpdate(
            {
              _id: currentId,
              revokedAt: { $exists: false },
              expiresAt: { $gt: rotatedAt },
            },
            {
              $set: {
                revokedAt: rotatedAt,
                revokeReason: 'rotated',
                replacedBySessionId: replacementId,
                lastUsedAt: rotatedAt,
              },
            },
            { session: databaseSession, returnDocument: 'after' },
          )
          .lean()
          .exec();
        if (updated === null) {
          throw new SessionRotationConflictError('Refresh token is no longer active.');
        }

        const documents = await this.model.create(
          [{ _id: replacementId, ...replacement }],
          { session: databaseSession },
        );
        created = safeSession(documents[0]!.toObject());
      });
    } finally {
      await databaseSession.endSession();
    }

    if (created === undefined) {
      throw new SessionRotationConflictError('Refresh token rotation did not complete.');
    }
    return created;
  }

  async revokeByRefreshTokenHash(
    refreshTokenHash: string,
    revokedAt: Date,
    reason: string,
  ): Promise<void> {
    await this.model
      .updateOne(
        { refreshTokenHash, revokedAt: { $exists: false } },
        { $set: { revokedAt, revokeReason: reason } },
      )
      .exec();
  }

  async revokeFamily(familyId: string, revokedAt: Date, reason: string): Promise<number> {
    const result = await this.model
      .updateMany(
        { familyId, revokedAt: { $exists: false } },
        { $set: { revokedAt, revokeReason: reason } },
      )
      .exec();
    return result.modifiedCount;
  }

  async revokeAllForUser(userId: Types.ObjectId, revokedAt: Date, reason: string, session?: ClientSession): Promise<number> {
    const result = await this.model
      .updateMany(
        { userId, revokedAt: { $exists: false } },
        { $set: { revokedAt, revokeReason: reason } },
        session === undefined ? {} : { session },
      )
      .exec();
    return result.modifiedCount;
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
