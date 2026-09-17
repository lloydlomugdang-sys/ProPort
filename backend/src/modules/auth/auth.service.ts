import { randomUUID } from 'node:crypto';
import type { FastifyBaseLogger } from 'fastify';
import type { ClientSession, Types } from 'mongoose';
import { AppError } from '../../common/errors/app-error.js';
import { normalizePersonalName } from '../../common/validation/personal-name.js';
import { PROFILE_OPTIONS } from '../users/profile-options.js';
import type { AppConfig } from '../../config/env.types.js';
import type { OneTimeCodeType, User } from '../../database/models/index.js';
import {
  createRepositories,
  type GradPortRepositories,
} from '../../database/repositories/index.js';
import { SessionRotationConflictError } from '../../database/repositories/session.repository.js';
import type { PersistedRecord } from '../../database/repositories/repository.types.js';
import type { SafeUserRecord } from '../../database/repositories/user.repository.js';
import type { DatabaseConnection } from '../../infrastructure/database/database-connection.js';
import { registerModels } from '../../infrastructure/database/model-registry.js';
import type { EmailSender } from '../../infrastructure/email/email-sender.js';
import {
  generateOpaqueToken,
  generateSixDigitCode,
  hashOneTimeCode,
  hashOpaqueToken,
  hashesEqual,
  hashPassword,
  verifyPassword,
} from './auth.crypto.js';

const INVALID_CREDENTIALS = new AppError(
  401,
  'INVALID_CREDENTIALS',
  'The email or password is incorrect.',
);
const INVALID_CODE = new AppError(
  400,
  'INVALID_OR_EXPIRED_CODE',
  'The verification code is invalid or has expired.',
);
const INVALID_RESET_TOKEN = new AppError(
  400,
  'INVALID_OR_EXPIRED_RESET_TOKEN',
  'The password reset token is invalid or has expired.',
);
const INVALID_REFRESH_TOKEN = new AppError(
  401,
  'INVALID_REFRESH_TOKEN',
  'The refresh token is invalid or has expired.',
);

export interface AccessTokenSigner {
  sign(payload: { readonly sub: string; readonly sid: string }): string;
}

export interface AuthUser {
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

export interface TokenBundle {
  readonly tokenType: 'Bearer';
  readonly accessToken: string;
  readonly accessTokenExpiresAt: string;
  readonly refreshToken: string;
  readonly refreshTokenExpiresAt: string;
}

export interface AuthSessionResult {
  readonly user: AuthUser;
  readonly tokens: TokenBundle;
}

export interface VerificationDelivery {
  readonly required: true;
  readonly codeExpiresAt: string;
  readonly resendAvailableAt: string;
}

export interface RegisterInput {
  readonly firstName: string;
  readonly lastName: string;
  readonly email: string;
  readonly password: string;
}

interface CodeDeliveryResult {
  readonly codeExpiresAt: Date;
  readonly resendAvailableAt: Date;
}

interface PersistenceContext {
  readonly repositories: GradPortRepositories;
  readonly connection: NonNullable<DatabaseConnection['mongooseConnection']>;
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function authUser(record: SafeUserRecord | PersistedRecord<User>): AuthUser {
  return {
    id: record._id.toString(),
    email: record.email,
    firstName: record.firstName,
    lastName: record.lastName,
    program: record.program,
    yearLevel: record.yearLevel,
    school: record.school,
    status: record.status,
    emailVerifiedAt: record.emailVerifiedAt?.toISOString() ?? null,
    hasAvatar: typeof record.avatarObjectKey === 'string' && record.avatarObjectKey.trim().length > 0,
  };
}

function addSeconds(value: Date, seconds: number): Date {
  return new Date(value.getTime() + seconds * 1000);
}

function isDuplicateKeyError(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    (error as { readonly code?: unknown }).code === 11000
  );
}

function assertStrongPassword(password: string, field = 'password'): void {
  const valid =
    password.length >= 8 &&
    password.length <= 128 &&
    /[a-z]/.test(password) &&
    /[A-Z]/.test(password) &&
    /[0-9]/.test(password);
  if (!valid) {
    throw new AppError(400, 'VALIDATION_ERROR', 'The request is invalid.', {
      [field]: [
        'must be 8-128 characters and include an uppercase letter, lowercase letter, and number',
      ],
    });
  }
}

function rateLimited(retryAfterSeconds: number): AppError {
  return new AppError(
    429,
    'RATE_LIMITED',
    'Too many requests. Please try again later.',
    undefined,
    { 'retry-after': String(Math.max(1, Math.ceil(retryAfterSeconds))) },
  );
}

function authCodeEmail(
  type: 'emailVerification' | 'passwordReset',
  code: string,
  expiresInMinutes: number,
): { readonly subject: string; readonly text: string; readonly html: string } {
  const isVerification = type === 'emailVerification';
  const purpose = isVerification ? 'email verification' : 'password reset';
  const subject = isVerification
    ? 'Verify your GradPort email'
    : 'Reset your GradPort password';
  const text = [
    `Your GradPort ${purpose} code is ${code}.`,
    `It expires in ${expiresInMinutes} minutes.`,
    'If you did not request this code, you can ignore this email.',
  ].join('\n\n');
  const html = `<!doctype html>
<html lang="en">
  <body style="margin:0;padding:24px;background:#f4f8fa;color:#16324f;font-family:Arial,sans-serif">
    <div style="max-width:520px;margin:0 auto;padding:24px;background:#ffffff;border-radius:12px">
      <h1 style="margin:0 0 16px;font-size:22px">${subject}</h1>
      <p style="margin:0 0 16px">Use this six-digit code to complete your ${purpose}:</p>
      <p style="margin:0 0 16px;font-size:32px;font-weight:700;letter-spacing:8px">${code}</p>
      <p style="margin:0 0 16px">This code expires in ${expiresInMinutes} minutes.</p>
      <p style="margin:0;color:#526777;font-size:13px">If you did not request this code, you can ignore this email.</p>
    </div>
  </body>
</html>`;
  return { subject, text, html };
}

export class AuthService {
  private dummyPasswordHashPromise: Promise<string> | undefined;

  constructor(
    private readonly config: AppConfig,
    private readonly database: DatabaseConnection,
    private readonly email: EmailSender,
    private readonly accessTokens: AccessTokenSigner,
    private readonly logger: FastifyBaseLogger,
  ) {}

  async register(input: RegisterInput): Promise<{
    readonly user: AuthUser;
    readonly verification: VerificationDelivery;
  }> {
    assertStrongPassword(input.password);
    const firstName = normalizePersonalName(input.firstName, 'firstName');
    const lastName = normalizePersonalName(input.lastName, 'lastName');
    const now = new Date();
    const email = normalizeEmail(input.email);
    const passwordHash = await hashPassword(input.password);
    const { repositories } = this.persistence();

    let user: SafeUserRecord;
    try {
      user = await repositories.users.create({
        email,
        passwordHash,
        firstName,
        lastName,
        program: '',
        yearLevel: '',
        school: PROFILE_OPTIONS.school,
        status: 'pendingVerification',
      });
    } catch (error) {
      if (isDuplicateKeyError(error)) {
        const existing = await repositories.users.findByEmailWithPassword(email);
        if (existing?.status === 'pendingVerification' && await verifyPassword(existing.passwordHash, input.password)) {
          // Resume only with valid existing credentials. Never overwrite the
          // account or send another code as a side effect of registration.
          throw new AppError(403, 'EMAIL_NOT_VERIFIED', 'Your email still needs verification.');
        }
        throw new AppError(
          409,
          'EMAIL_ALREADY_REGISTERED',
          'An account with this email already exists.',
        );
      }
      throw error;
    }

    const delivery = await this.issueCode(
      repositories,
      user._id,
      user.email,
      'emailVerification',
      now,
      false,
    );
    return {
      user: authUser(user),
      verification: {
        required: true,
        codeExpiresAt: delivery.codeExpiresAt.toISOString(),
        resendAvailableAt: delivery.resendAvailableAt.toISOString(),
      },
    };
  }

  async verifyEmail(email: string, code: string): Promise<AuthSessionResult> {
    const now = new Date();
    const { repositories, connection } = this.persistence();
    const user = await repositories.users.findByEmail(normalizeEmail(email));
    if (user === null || user.status !== 'pendingVerification') {
      throw INVALID_CODE;
    }

    // Bad attempts persist independently; valid consumption, activation and
    // ordinary session creation commit together, so transient failures can retry.
    const stored = await this.checkNumericCode(repositories, user._id, 'emailVerification', code, now);
    const databaseSession = await connection.startSession();
    try {
      const result = await databaseSession.withTransaction(async () => {
        if (!await repositories.oneTimeCodes.consume(user._id, stored._id, new Date(), this.config.authCodeMaxAttempts, databaseSession)) {
          throw INVALID_CODE;
        }
        const verified = await repositories.users.markEmailVerified(user._id, now, databaseSession);
        if (verified === null) throw INVALID_CODE;
        return this.createSession(repositories, verified, now, databaseSession);
      });
      if (result === undefined) throw INVALID_CODE;
      return result;
    } finally {
      await databaseSession.endSession();
    }
  }

  async resendEmailVerification(email: string): Promise<void> {
    const now = new Date();
    const { repositories } = this.persistence();
    const user = await repositories.users.findByEmail(normalizeEmail(email));
    if (user === null || user.status !== 'pendingVerification') {
      this.performDummyCodeWork(email, 'emailVerification');
      return;
    }
    await this.issueCode(
      repositories,
      user._id,
      user.email,
      'emailVerification',
      now,
      true,
    );
  }

  async login(email: string, password: string): Promise<AuthSessionResult> {
    const now = new Date();
    const { repositories } = this.persistence();
    const user = await repositories.users.findByEmailWithPassword(normalizeEmail(email));

    if (user === null) {
      await verifyPassword(await this.dummyPasswordHash(), password);
      throw INVALID_CREDENTIALS;
    }
    if (!(await verifyPassword(user.passwordHash, password))) {
      throw INVALID_CREDENTIALS;
    }
    if (user.status === 'pendingVerification') {
      throw new AppError(
        403,
        'EMAIL_NOT_VERIFIED',
        'Verify your email before signing in.',
      );
    }
    if (user.status === 'disabled') {
      throw new AppError(403, 'ACCOUNT_DISABLED', 'This account is disabled.');
    }

    const result = await this.createSession(repositories, user, now);
    await repositories.users.recordSuccessfulLogin(user._id, now);
    return result;
  }

  async requestPasswordReset(emailInput: string): Promise<void> {
    const now = new Date();
    const email = normalizeEmail(emailInput);
    const { repositories } = this.persistence();
    const user = await repositories.users.findByEmail(email);
    if (user === null || user.status !== 'active') {
      this.performDummyCodeWork(email, 'passwordReset');
      return;
    }

    try {
      await this.issueCode(repositories, user._id, user.email, 'passwordReset', now, true, true);
    } catch (error) {
      if (error instanceof AppError && error.code === 'RATE_LIMITED') {
        return;
      }
      this.logger.error(
        { err: error, userId: user._id.toString() },
        'Password reset delivery failed',
      );
    }
  }

  async verifyPasswordReset(
    email: string,
    code: string,
  ): Promise<{ readonly resetToken: string; readonly resetTokenExpiresAt: string }> {
    const now = new Date();
    const { repositories } = this.persistence();
    const user = await repositories.users.findByEmail(normalizeEmail(email));
    if (user === null || user.status !== 'active') {
      throw INVALID_CODE;
    }

    await this.consumeNumericCode(repositories, user._id, 'passwordReset', code, now);
    const resetToken = generateOpaqueToken();
    const resetTokenExpiresAt = addSeconds(now, this.config.authResetGrantTtlSeconds);
    await repositories.oneTimeCodes.invalidateActiveForUserAndType(
      user._id,
      'passwordResetGrant',
      now,
    );
    await repositories.oneTimeCodes.create({
      userId: user._id,
      type: 'passwordResetGrant',
      codeHash: hashOpaqueToken(resetToken),
      attempts: 0,
      expiresAt: resetTokenExpiresAt,
    });
    return { resetToken, resetTokenExpiresAt: resetTokenExpiresAt.toISOString() };
  }

  async completePasswordReset(resetToken: string, newPassword: string): Promise<void> {
    assertStrongPassword(newPassword, 'newPassword');
    const now = new Date();
    const passwordHash = await hashPassword(newPassword);
    const { connection } = this.persistence();
    const models = registerModels(connection);
    const databaseSession = await connection.startSession();

    try {
      await databaseSession.withTransaction(async () => {
        const grant = await models.OneTimeCode.findOneAndUpdate(
          {
            type: 'passwordResetGrant',
            codeHash: hashOpaqueToken(resetToken),
            consumedAt: { $exists: false },
            expiresAt: { $gt: now },
          },
          { $set: { consumedAt: now } },
          { session: databaseSession, returnDocument: 'after' },
        )
          .select('-codeHash')
          .lean()
          .exec();
        if (grant === null) {
          throw INVALID_RESET_TOKEN;
        }

        const updated = await models.User.updateOne(
          { _id: grant.userId, status: 'active' },
          { $set: { passwordHash } },
          { session: databaseSession, runValidators: true, strict: 'throw' },
        ).exec();
        if (updated.matchedCount !== 1) {
          throw INVALID_RESET_TOKEN;
        }
        await models.Session.updateMany(
          { userId: grant.userId, revokedAt: { $exists: false } },
          { $set: { revokedAt: now, revokeReason: 'passwordReset' } },
          { session: databaseSession },
        ).exec();
      });
    } finally {
      await databaseSession.endSession();
    }
  }

  async changePassword(userId: Types.ObjectId, sessionId: Types.ObjectId, currentPassword: string, newPassword: string): Promise<void> {
    assertStrongPassword(newPassword, 'newPassword');
    const invalidCurrent = new AppError(400, 'INVALID_CURRENT_PASSWORD', 'Current password is incorrect.');
    const { repositories, connection } = this.persistence();
    const user = await repositories.users.findByIdWithPassword(userId);
    if (user === null || user.status !== 'active' || !await verifyPassword(user.passwordHash, currentPassword)) {
      throw invalidCurrent;
    }
    const passwordHash = await hashPassword(newPassword);
    const models = registerModels(connection);
    const databaseSession = await connection.startSession();
    try {
      await databaseSession.withTransaction(async () => {
        const now = new Date();
        const session = await models.Session.exists({
          _id: sessionId, userId, revokedAt: { $exists: false }, expiresAt: { $gt: now },
        }).session(databaseSession);
        if (session === null) throw new AppError(401, 'UNAUTHORIZED', 'Authentication is required.');
        if (!await repositories.users.replacePasswordHash(userId, user.passwordHash, passwordHash, databaseSession)) {
          throw invalidCurrent;
        }
        await repositories.sessions.revokeAllForUser(userId, now, 'passwordChange', databaseSession);
        await models.OneTimeCode.updateMany(
          { userId, type: { $in: ['passwordReset', 'passwordResetGrant'] }, consumedAt: { $exists: false } },
          { $set: { consumedAt: now } }, { session: databaseSession },
        ).exec();
      });
    } finally {
      await databaseSession.endSession();
    }
  }

  async refresh(refreshToken: string): Promise<AuthSessionResult> {
    const now = new Date();
    const { repositories } = this.persistence();
    const refreshTokenHash = hashOpaqueToken(refreshToken);
    const current = await repositories.sessions.findByRefreshTokenHash(refreshTokenHash);
    if (current === null) {
      throw INVALID_REFRESH_TOKEN;
    }

    if (current.revokedAt !== undefined) {
      if (current.replacedBySessionId !== undefined || current.revokeReason === 'rotated') {
        await repositories.sessions.revokeFamily(current.familyId, now, 'refreshTokenReplay');
      }
      throw INVALID_REFRESH_TOKEN;
    }
    if (current.expiresAt.getTime() <= now.getTime()) {
      await repositories.sessions.revokeByRefreshTokenHash(refreshTokenHash, now, 'expired');
      throw INVALID_REFRESH_TOKEN;
    }

    const user = await repositories.users.findById(current.userId);
    if (user === null || user.status !== 'active') {
      await repositories.sessions.revokeFamily(current.familyId, now, 'accountUnavailable');
      throw INVALID_REFRESH_TOKEN;
    }

    const nextRefreshToken = generateOpaqueToken();
    const refreshTokenExpiresAt = addSeconds(now, this.config.authRefreshTokenTtlSeconds);
    let replacement;
    try {
      replacement = await repositories.sessions.rotate(
        current._id,
        {
          userId: user._id,
          familyId: current.familyId,
          refreshTokenHash: hashOpaqueToken(nextRefreshToken),
          expiresAt: refreshTokenExpiresAt,
        },
        now,
      );
    } catch (error) {
      if (error instanceof SessionRotationConflictError) {
        await repositories.sessions.revokeFamily(current.familyId, now, 'refreshTokenReplay');
        throw INVALID_REFRESH_TOKEN;
      }
      throw error;
    }

    return {
      user: authUser(user),
      tokens: this.tokenBundle(user._id, replacement._id, nextRefreshToken, refreshTokenExpiresAt, now),
    };
  }

  async logout(refreshToken: string): Promise<void> {
    const { repositories } = this.persistence();
    await repositories.sessions.revokeByRefreshTokenHash(
      hashOpaqueToken(refreshToken),
      new Date(),
      'logout',
    );
  }

  private persistence(): PersistenceContext {
    const connection = this.database.mongooseConnection;
    if (this.database.status !== 'connected' || connection === undefined) {
      throw new AppError(503, 'AUTH_UNAVAILABLE', 'Authentication is temporarily unavailable.');
    }
    return { repositories: createRepositories(connection), connection };
  }

  private async createSession(
    repositories: GradPortRepositories,
    user: SafeUserRecord | PersistedRecord<User>,
    now: Date,
    databaseSession?: ClientSession,
  ): Promise<AuthSessionResult> {
    const refreshToken = generateOpaqueToken();
    const refreshTokenExpiresAt = addSeconds(now, this.config.authRefreshTokenTtlSeconds);
    const session = await repositories.sessions.create({
      userId: user._id,
      familyId: randomUUID(),
      refreshTokenHash: hashOpaqueToken(refreshToken),
      expiresAt: refreshTokenExpiresAt,
    }, databaseSession);
    return {
      user: authUser(user),
      tokens: this.tokenBundle(user._id, session._id, refreshToken, refreshTokenExpiresAt, now),
    };
  }

  private tokenBundle(
    userId: Types.ObjectId,
    sessionId: Types.ObjectId,
    refreshToken: string,
    refreshTokenExpiresAt: Date,
    now: Date,
  ): TokenBundle {
    return {
      tokenType: 'Bearer',
      accessToken: this.accessTokens.sign({ sub: userId.toString(), sid: sessionId.toString() }),
      accessTokenExpiresAt: addSeconds(now, this.config.authAccessTokenTtlSeconds).toISOString(),
      refreshToken,
      refreshTokenExpiresAt: refreshTokenExpiresAt.toISOString(),
    };
  }

  private async issueCode(
    repositories: GradPortRepositories,
    userId: Types.ObjectId,
    targetEmail: string,
    type: 'emailVerification' | 'passwordReset',
    now: Date,
    enforceCooldown: boolean,
    suppressDeliveryErrors = false,
  ): Promise<CodeDeliveryResult> {
    if (enforceCooldown) {
      const latest = await repositories.oneTimeCodes.findLatestForUserAndType(userId, type);
      if (latest !== null) {
        const availableAt = addSeconds(
          latest.createdAt,
          this.config.authCodeResendCooldownSeconds,
        );
        if (availableAt.getTime() > now.getTime()) {
          throw rateLimited((availableAt.getTime() - now.getTime()) / 1000);
        }
      }
    }

    const code = generateSixDigitCode();
    const codeExpiresAt = addSeconds(now, this.config.authCodeTtlSeconds);
    const resendAvailableAt = addSeconds(now, this.config.authCodeResendCooldownSeconds);
    await repositories.oneTimeCodes.invalidateActiveForUserAndType(userId, type, now);
    await repositories.oneTimeCodes.create({
      userId,
      type,
      targetEmail,
      codeHash: hashOneTimeCode(this.config.authCodePepper, userId.toString(), type, code),
      attempts: 0,
      expiresAt: codeExpiresAt,
    });

    try {
      const message = authCodeEmail(
        type,
        code,
        Math.ceil(this.config.authCodeTtlSeconds / 60),
      );
      await this.email.send({
        to: targetEmail,
        template: type,
        ...message,
      });
    } catch (error) {
      if (suppressDeliveryErrors) {
        this.logger.error({ err: error, userId: userId.toString(), type }, 'Email delivery failed');
      } else {
        throw new AppError(503, 'EMAIL_UNAVAILABLE', 'Email delivery is temporarily unavailable.');
      }
    }
    return { codeExpiresAt, resendAvailableAt };
  }

  private async checkNumericCode(
    repositories: GradPortRepositories,
    userId: Types.ObjectId,
    type: 'emailVerification' | 'passwordReset',
    code: string,
    now: Date,
  ) {
    const stored = await repositories.oneTimeCodes.findLatestActiveWithHash(
      userId,
      type,
      now,
      this.config.authCodeMaxAttempts,
    );
    if (stored === null) {
      throw INVALID_CODE;
    }

    const submittedHash = hashOneTimeCode(
      this.config.authCodePepper,
      userId.toString(),
      type,
      code,
    );
    if (!hashesEqual(submittedHash, stored.codeHash)) {
      await repositories.oneTimeCodes.incrementAttempts(
        userId,
        stored._id,
        now,
        this.config.authCodeMaxAttempts,
      );
      throw INVALID_CODE;
    }
    return stored;
  }

  private async consumeNumericCode(
    repositories: GradPortRepositories,
    userId: Types.ObjectId,
    type: 'emailVerification' | 'passwordReset',
    code: string,
    now: Date,
  ): Promise<void> {
    const stored = await this.checkNumericCode(repositories, userId, type, code, now);
    const consumed = await repositories.oneTimeCodes.consume(
      userId,
      stored._id,
      now,
      this.config.authCodeMaxAttempts,
    );
    if (!consumed) {
      throw INVALID_CODE;
    }
  }

  private performDummyCodeWork(email: string, type: OneTimeCodeType): void {
    hashOneTimeCode(this.config.authCodePepper, hashOpaqueToken(email), type, '000000');
  }

  private dummyPasswordHash(): Promise<string> {
    this.dummyPasswordHashPromise ??= hashPassword('GradPortDummyPassword1');
    return this.dummyPasswordHashPromise;
  }
}
