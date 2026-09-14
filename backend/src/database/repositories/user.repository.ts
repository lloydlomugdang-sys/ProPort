import type { ClientSession, Model, Types } from 'mongoose';
import type { User } from '../models/index.js';
import {
  asPersistedRecord,
  boundedLimit,
  type CreateRecord,
  type PersistedRecord,
  type UpdateRecord,
} from './repository.types.js';

export type SafeUser = Omit<User, 'passwordHash'>;
export type SafeUserRecord = PersistedRecord<SafeUser>;
export type CreateUserInput = CreateRecord<User>;
export type UpdateUserInput = UpdateRecord<User>;
export type UpdateUserProfileInput = Readonly<
  Partial<Pick<User, 'firstName' | 'lastName' | 'program' | 'yearLevel' | 'school'>>
>;
export type CredentialUserRecord = PersistedRecord<User>;

function safeUser(value: unknown): SafeUserRecord {
  const { passwordHash: _passwordHash, ...safe } = value as Record<string, unknown>;
  return asPersistedRecord<SafeUser>(safe);
}

export class UserRepository {
  constructor(private readonly model: Model<User>) {}

  async create(input: CreateUserInput): Promise<SafeUserRecord> {
    const created = await this.model.create(input);
    return safeUser(created.toObject());
  }

  async findById(id: Types.ObjectId): Promise<SafeUserRecord | null> {
    const found = await this.model.findById(id).select('-passwordHash').lean().exec();
    return found === null ? null : safeUser(found);
  }

  async findByEmail(email: string): Promise<SafeUserRecord | null> {
    const found = await this.model
      .findOne({ email: email.trim().toLowerCase() })
      .select('-passwordHash')
      .lean()
      .exec();
    return found === null ? null : safeUser(found);
  }

  /** Authentication-only lookup. Callers must never return or log this record. */
  async findByEmailWithPassword(email: string): Promise<CredentialUserRecord | null> {
    const found = await this.model
      .findOne({ email: email.trim().toLowerCase() })
      .select('+passwordHash')
      .lean()
      .exec();
    return found === null ? null : asPersistedRecord<User>(found);
  }

  async findByIdWithPassword(id: Types.ObjectId): Promise<CredentialUserRecord | null> {
    const found = await this.model.findById(id).select('+passwordHash').lean().exec();
    return found === null ? null : asPersistedRecord<User>(found);
  }

  /** Compare-and-set prevents an older password-change request overwriting a reset. */
  async replacePasswordHash(id: Types.ObjectId, expectedHash: string, passwordHash: string, session: ClientSession): Promise<boolean> {
    const result = await this.model.updateOne(
      { _id: id, status: 'active', passwordHash: expectedHash },
      { $set: { passwordHash } },
      { session, runValidators: true, strict: 'throw' },
    ).exec();
    return result.modifiedCount === 1;
  }

  async markEmailVerified(id: Types.ObjectId, verifiedAt: Date, session?: ClientSession): Promise<SafeUserRecord | null> {
    const updated = await this.model
      .findOneAndUpdate(
        { _id: id, status: 'pendingVerification' },
        { $set: { status: 'active', emailVerifiedAt: verifiedAt } },
        { returnDocument: 'after', runValidators: true, strict: 'throw', session: session ?? null },
      )
      .select('-passwordHash')
      .lean()
      .exec();
    return updated === null ? null : safeUser(updated);
  }

  async recordSuccessfulLogin(id: Types.ObjectId, loggedInAt: Date): Promise<void> {
    await this.model.updateOne({ _id: id }, { $set: { lastLoginAt: loggedInAt } }).exec();
  }

  async updatePasswordHash(id: Types.ObjectId, passwordHash: string): Promise<boolean> {
    const result = await this.model
      .updateOne({ _id: id }, { $set: { passwordHash } }, { runValidators: true, strict: 'throw' })
      .exec();
    return result.matchedCount === 1;
  }

  async list(limit = 50): Promise<readonly SafeUserRecord[]> {
    const found = await this.model
      .find()
      .select('-passwordHash')
      .sort({ createdAt: -1 })
      .limit(boundedLimit(limit))
      .lean()
      .exec();
    return found.map(safeUser);
  }

  async updateById(id: Types.ObjectId, patch: UpdateUserInput): Promise<SafeUserRecord | null> {
    const updated = await this.model
      .findByIdAndUpdate(
        id,
        { $set: patch },
        { returnDocument: 'after', runValidators: true, strict: 'throw' },
      )
      .select('-passwordHash')
      .lean()
      .exec();
    return updated === null ? null : safeUser(updated);
  }

  async updateProfileById(
    id: Types.ObjectId,
    patch: UpdateUserProfileInput,
  ): Promise<SafeUserRecord | null> {
    const updated = await this.model
      .findByIdAndUpdate(
        id,
        { $set: patch },
        { returnDocument: 'after', runValidators: true, strict: 'throw' },
      )
      .select('-passwordHash')
      .lean()
      .exec();
    return updated === null ? null : safeUser(updated);
  }

  async deleteById(id: Types.ObjectId): Promise<boolean> {
    const result = await this.model.deleteOne({ _id: id });
    return result.deletedCount === 1;
  }
}
