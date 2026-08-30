import type { Types } from 'mongoose';

export type PersistedRecord<T> = T & { readonly _id: Types.ObjectId };
export type CreateRecord<T> = Omit<T, 'createdAt' | 'updatedAt'>;
export type UpdateRecord<T> = Partial<CreateRecord<T>>;

export class RepositoryInputError extends Error {
  override readonly name = 'RepositoryInputError';
}

export function boundedLimit(limit: number): number {
  if (!Number.isSafeInteger(limit) || limit < 1) {
    throw new RepositoryInputError('Repository list limit must be a positive integer.');
  }
  return Math.min(limit, 100);
}

export function asPersistedRecord<T>(value: unknown): PersistedRecord<T> {
  return value as PersistedRecord<T>;
}
