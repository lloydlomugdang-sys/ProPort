import type { Types } from 'mongoose';
import { AppError } from '../../common/errors/app-error.js';
import type { User } from '../../database/models/index.js';
import { createRepositories } from '../../database/repositories/index.js';
import type {
  SafeUserRecord,
  UpdateUserProfileInput,
} from '../../database/repositories/user.repository.js';
import type { DatabaseConnection } from '../../infrastructure/database/database-connection.js';

const UNAUTHORIZED = new AppError(
  401,
  'UNAUTHORIZED',
  'Authentication is required to access this resource.',
);

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
  };
}

function normalizeRequiredName(value: string, field: 'firstName' | 'lastName'): string {
  const normalized = value.trim();
  if (normalized.length < 2 || normalized.length > 100) {
    throw new AppError(400, 'VALIDATION_ERROR', 'The request is invalid.', {
      [field]: ['must contain 2-100 non-whitespace characters'],
    });
  }
  return normalized;
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
  constructor(private readonly database: DatabaseConnection) {}

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
    const updated = await this.repositories().users.updateProfileById(userId, normalizePatch(input));
    if (updated === null || updated.status !== 'active') {
      throw UNAUTHORIZED;
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
