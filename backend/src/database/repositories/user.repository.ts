import type { Model, Types } from 'mongoose';
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

  async deleteById(id: Types.ObjectId): Promise<boolean> {
    const result = await this.model.deleteOne({ _id: id });
    return result.deletedCount === 1;
  }
}
