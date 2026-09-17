import { randomUUID } from 'node:crypto';
import { Readable } from 'node:stream';
import type { FastifyBaseLogger } from 'fastify';
import type { Types } from 'mongoose';
import { AppError } from '../../common/errors/app-error.js';
import { normalizePersonalName } from '../../common/validation/personal-name.js';
import { PROFILE_OPTIONS } from './profile-options.js';
import type { User } from '../../database/models/index.js';
import { createRepositories } from '../../database/repositories/index.js';
import type {
  SafeUserRecord,
  UpdateUserProfileInput,
} from '../../database/repositories/user.repository.js';
import type { DatabaseConnection } from '../../infrastructure/database/database-connection.js';
import type { ObjectStorage } from '../../infrastructure/storage/object-storage.js';

const UNAUTHORIZED = new AppError(
  401,
  'UNAUTHORIZED',
  'Authentication is required to access this resource.',
);

export const MAX_AVATAR_FILE_SIZE_BYTES = 5 * 1024 * 1024; // 5 MB

export function validateAvatarImage(contents: Buffer): { extension: 'jpg' | 'png' | 'webp'; mimeType: string } {
  if (contents.length === 0) {
    throw new AppError(400, 'VALIDATION_ERROR', 'The request is invalid.', { avatar: ['image file is empty'] });
  }
  if (contents.length > MAX_AVATAR_FILE_SIZE_BYTES) {
    throw new AppError(413, 'FILE_TOO_LARGE', 'The profile image exceeds the 5 MB upload limit.');
  }

  // Magic bytes check
  const isJpeg = contents.length >= 3 && contents[0] === 0xff && contents[1] === 0xd8 && contents[2] === 0xff;
  const isPng = contents.length >= 8 && contents[0] === 0x89 && contents[1] === 0x50 && contents[2] === 0x4e && contents[3] === 0x47;
  const isWebp = contents.length >= 12 &&
    contents[0] === 0x52 && contents[1] === 0x49 && contents[2] === 0x46 && contents[3] === 0x46 && // RIFF
    contents[8] === 0x57 && contents[9] === 0x45 && contents[10] === 0x42 && contents[11] === 0x50; // WEBP

  if (isJpeg) {
    return { extension: 'jpg', mimeType: 'image/jpeg' };
  }
  if (isPng) {
    return { extension: 'png', mimeType: 'image/png' };
  }
  if (isWebp) {
    return { extension: 'webp', mimeType: 'image/webp' };
  }

  throw new AppError(400, 'VALIDATION_ERROR', 'The request is invalid.', {
    avatar: ['must be a valid JPEG, PNG, or WEBP image'],
  });
}

export interface CurrentUserProfile {
  readonly id: string;
  readonly email: string;
  readonly firstName: string;
  readonly lastName: string;
  readonly program: string;
  readonly yearLevel: string;
  readonly school: string;
  readonly status: User['status'];
  readonly emailVerifiedAt: string | null;
  readonly hasAvatar: boolean;
}

export interface CurrentUserIdentity {
  readonly userId: Types.ObjectId;
  readonly profile: CurrentUserProfile;
}

export interface UpdateCurrentUserProfileInput {
  readonly firstName?: string;
  readonly lastName?: string;
  readonly program?: string;
  readonly yearLevel?: string;
  readonly school?: string;
}

function publicProfile(user: SafeUserRecord): CurrentUserProfile {
  return {
    id: user._id.toString(),
    email: user.email,
    firstName: user.firstName,
    lastName: user.lastName,
    program: user.program,
    yearLevel: user.yearLevel,
    school: user.school,
    status: user.status,
    emailVerifiedAt: user.emailVerifiedAt?.toISOString() ?? null,
    hasAvatar: typeof user.avatarObjectKey === 'string' && user.avatarObjectKey.trim().length > 0,
  };
}

function normalizeRequiredName(value: string, field: 'firstName' | 'lastName'): string {
  return normalizePersonalName(value, field);
}

function normalizeOptionalText(value: string, field: string, maximum: number): string {
  const normalized = value.trim();
  if (normalized.length > maximum) {
    throw new AppError(400, 'VALIDATION_ERROR', 'The request is invalid.', {
      [field]: [`must contain at most ${maximum} characters`],
    });
  }
  return normalized;
}

function normalizePatch(input: UpdateCurrentUserProfileInput): UpdateUserProfileInput {
  return {
    ...(input.firstName === undefined
      ? {}
      : { firstName: normalizeRequiredName(input.firstName, 'firstName') }),
    ...(input.lastName === undefined
      ? {}
      : { lastName: normalizeRequiredName(input.lastName, 'lastName') }),
    ...(input.program === undefined
      ? {}
      : { program: normalizeOptionalText(input.program, 'program', 200) }),
    ...(input.yearLevel === undefined
      ? {}
      : { yearLevel: normalizeOptionalText(input.yearLevel, 'yearLevel', 50) }),
    ...(input.school === undefined
      ? {}
      : { school: normalizeOptionalText(input.school, 'school', 200) }),
  };
}

export class CurrentUserService {
  constructor(
    private readonly database: DatabaseConnection,
    private readonly storage?: ObjectStorage,
    private readonly logger?: Pick<FastifyBaseLogger, 'warn' | 'error' | 'info'>,
  ) {}

  async authenticate(
    userId: Types.ObjectId,
    sessionId: Types.ObjectId,
  ): Promise<CurrentUserIdentity> {
    const repositories = this.repositories();
    const [session, user] = await Promise.all([
      repositories.sessions.findByIdForUser(userId, sessionId),
      repositories.users.findById(userId),
    ]);
    const now = new Date();

    if (
      session === null ||
      session.revokedAt !== undefined ||
      session.expiresAt.getTime() <= now.getTime() ||
      user === null ||
      user.status !== 'active'
    ) {
      throw UNAUTHORIZED;
    }

    return { userId, profile: publicProfile(user) };
  }

  async updateProfile(
    userId: Types.ObjectId,
    input: UpdateCurrentUserProfileInput,
  ): Promise<CurrentUserProfile> {
    const repositories = this.repositories();
    const existing = await repositories.users.findById(userId);
    if (existing === null || existing.status !== 'active') throw UNAUTHORIZED;
    const patch = normalizePatch(input);
    for (const field of ['program', 'yearLevel', 'school'] as const) {
      const value = patch[field];
      // Preserve legacy stored values on unrelated edits, without offering them
      // as new choices or silently migrating/overwriting the account.
      if (value === undefined || value === existing[field].trim()) continue;
      const choices = field === 'program' ? PROFILE_OPTIONS.programs
        : field === 'yearLevel' ? PROFILE_OPTIONS.yearLevels : [PROFILE_OPTIONS.school];
      if (!choices.includes(value) && !(field !== 'school' && value === '')) {
        throw new AppError(400, 'VALIDATION_ERROR', 'The request is invalid.', { [field]: ['must be a supported profile value'] });
      }
    }
    const updated = await repositories.users.updateProfileById(userId, patch);
    if (updated === null || updated.status !== 'active') {
      throw UNAUTHORIZED;
    }
    return publicProfile(updated);
  }

  async uploadAvatar(
    userId: Types.ObjectId,
    file: { contents: Buffer; mimeType?: string },
  ): Promise<CurrentUserProfile> {
    if (!this.storage) {
      throw new AppError(503, 'STORAGE_UNAVAILABLE', 'Storage service is unavailable.');
    }
    const { extension, mimeType } = validateAvatarImage(file.contents);
    const repositories = this.repositories();
    const existing = await repositories.users.findById(userId);
    if (existing === null || existing.status !== 'active') throw UNAUTHORIZED;

    const previousKey = existing.avatarObjectKey;
    const newKey = `users/${userId.toString()}/avatar/${randomUUID()}.${extension}`;

    // 1. Upload new avatar first
    try {
      await this.storage.put(newKey, Readable.from([file.contents]));
    } catch {
      throw new AppError(503, 'STORAGE_ERROR', 'Unable to upload profile picture. Please try again.');
    }

    // 2. Update user profile in database
    let updated: SafeUserRecord | null;
    try {
      updated = await repositories.users.updateById(userId, {
        avatarObjectKey: newKey,
        avatarMimeType: mimeType,
      });
      if (updated === null || updated.status !== 'active') {
        throw UNAUTHORIZED;
      }
    } catch (error) {
      // Clean up newly uploaded object so it does not become an orphan
      await this.storage.delete(newKey).catch(() => undefined);
      if (error instanceof AppError) throw error;
      throw new AppError(500, 'DATABASE_ERROR', 'Failed to update profile picture record.');
    }

    // 3. Delete previous R2 avatar only after new reference has been persisted
    if (previousKey && previousKey !== newKey) {
      try {
        await this.storage.delete(previousKey);
      } catch (err) {
        // Safe logging; do not roll back the valid new avatar
        this.logger?.warn({ err, previousKey }, 'Failed to delete previous avatar object after successful update');
      }
    }

    return publicProfile(updated);
  }

  async getAvatar(userId: Types.ObjectId): Promise<{ stream: Readable; mimeType: string }> {
    if (!this.storage) {
      throw new AppError(503, 'STORAGE_UNAVAILABLE', 'Storage service is unavailable.');
    }
    const repositories = this.repositories();
    const user = await repositories.users.findById(userId);
    if (user === null || user.status !== 'active') throw UNAUTHORIZED;

    if (!user.avatarObjectKey || user.avatarObjectKey.trim().length === 0) {
      throw new AppError(404, 'AVATAR_NOT_FOUND', 'The user does not have a profile picture.');
    }

    try {
      const stream = await this.storage.get(user.avatarObjectKey);
      return { stream, mimeType: user.avatarMimeType || 'image/jpeg' };
    } catch {
      throw new AppError(404, 'AVATAR_NOT_FOUND', 'Profile picture is no longer available.');
    }
  }

  async deleteAvatar(userId: Types.ObjectId): Promise<CurrentUserProfile> {
    const repositories = this.repositories();
    const existing = await repositories.users.findById(userId);
    if (existing === null || existing.status !== 'active') throw UNAUTHORIZED;

    const previousKey = existing.avatarObjectKey;
    const updated = await repositories.users.updateById(userId, {
      avatarObjectKey: '',
      avatarMimeType: '',
    });
    if (updated === null) throw UNAUTHORIZED;

    if (this.storage && previousKey && previousKey.trim().length > 0) {
      try {
        await this.storage.delete(previousKey);
      } catch (err) {
        this.logger?.warn({ err, previousKey }, 'Failed to delete avatar object during deletion');
      }
    }

    return publicProfile(updated);
  }

  private repositories() {
    const connection = this.database.mongooseConnection;
    if (this.database.status !== 'connected' || connection === undefined) {
      throw new AppError(
        503,
        'AUTH_UNAVAILABLE',
        'Authentication is temporarily unavailable. Please try again.',
      );
    }
    return createRepositories(connection);
  }
}
