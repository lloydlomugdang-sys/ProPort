import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { COLLECTION_NAMES } from '../../src/database/collection-names.js';
import { APPLICATION_INDEXES } from '../../src/database/indexes/index-definitions.js';
import { verifyApplicationIndexes } from '../../src/database/indexes/verify-indexes.js';
import { runMigrations } from '../../src/database/migrations/migration-runner.js';
import { createRepositories } from '../../src/database/repositories/index.js';
import type { GradPortRepositories } from '../../src/database/repositories/index.js';
import {
  hashOneTimeCode,
  hashOpaqueToken,
  hashPassword,
  verifyPassword,
} from '../../src/modules/auth/auth.crypto.js';
import {
  createDisposableMongoDatabase,
  type DisposableMongoDatabase,
} from '../helpers/disposable-mongodb.js';

const RAW_PASSWORD = 'NeverPersistThis9';
const RAW_VERIFICATION_CODE = '381947';
const RAW_REFRESH_TOKEN = 'raw-refresh-token-never-persist';
const RAW_REPLACEMENT_TOKEN = 'raw-replacement-token-never-persist';
const RAW_RESET_GRANT = 'raw-reset-grant-never-persist';
const RAW_ACCESS_TOKEN = 'raw-access-token-never-persist';
const CODE_PEPPER = 'test-only-code-pepper-at-least-32-bytes';

function requireContext(
  disposable: DisposableMongoDatabase | undefined,
  repositories: GradPortRepositories | undefined,
): { disposable: DisposableMongoDatabase; repositories: GradPortRepositories } {
  if (disposable === undefined || disposable.connection.db === undefined || repositories === undefined) {
    throw new Error('Disposable authentication test database is unavailable.');
  }
  return { disposable, repositories };
}

describe.sequential('authentication persistence', () => {
  let disposable: DisposableMongoDatabase | undefined;
  let repositories: GradPortRepositories | undefined;
  let userId: Awaited<ReturnType<GradPortRepositories['users']['create']>>['_id'];

  beforeAll(async () => {
    disposable = await createDisposableMongoDatabase();
    await runMigrations(disposable.connection.db!);
    repositories = createRepositories(disposable.connection);
  });

  afterAll(async () => {
    if (disposable !== undefined) {
      await disposable.stop();
    }
  });

  it('enforces auth indexes and normalized email uniqueness', async () => {
    const context = requireContext(disposable, repositories);
    const verification = await verifyApplicationIndexes(context.disposable.connection.db!);
    expect(verification.ok).toBe(true);

    const expectedAuthIndexes = APPLICATION_INDEXES.filter(
      ({ collection }) =>
        collection === COLLECTION_NAMES.users ||
        collection === COLLECTION_NAMES.sessions ||
        collection === COLLECTION_NAMES.oneTimeCodes,
    );
    const actualNames = new Set<string>();
    for (const collectionName of [
      COLLECTION_NAMES.users,
      COLLECTION_NAMES.sessions,
      COLLECTION_NAMES.oneTimeCodes,
    ]) {
      for (const index of await context.disposable.connection.db!.collection(collectionName).indexes()) {
        if (index.name !== undefined) {
          actualNames.add(index.name);
        }
      }
    }
    for (const expected of expectedAuthIndexes) {
      expect(actualNames.has(expected.name), `missing MongoDB index ${expected.name}`).toBe(true);
    }

    const passwordHash = await hashPassword(RAW_PASSWORD);
    const user = await context.repositories.users.create({
      email: '  Auth.Student@Example.EDU  ',
      passwordHash,
      firstName: 'Auth',
      lastName: 'Student',
      program: '',
      yearLevel: '',
      school: '',
      status: 'active',
      emailVerifiedAt: new Date(),
    });
    userId = user._id;

    expect(user.email).toBe('auth.student@example.edu');
    expect(user).not.toHaveProperty('passwordHash');
    await expect(
      context.repositories.users.create({
        email: 'AUTH.STUDENT@EXAMPLE.EDU',
        passwordHash: await hashPassword('AnotherSafe9'),
        firstName: 'Other',
        lastName: 'Student',
        program: '',
        yearLevel: '',
        school: '',
        status: 'active',
      }),
    ).rejects.toMatchObject({ code: 11000 });

    const rawUser = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.users)
      .findOne({ _id: user._id });
    expect(rawUser?.email).toBe('auth.student@example.edu');
    expect(rawUser?.passwordHash).toBe(passwordHash);
    expect(rawUser?.passwordHash).not.toBe(RAW_PASSWORD);
    expect(rawUser).not.toHaveProperty('password');
    await expect(verifyPassword(String(rawUser?.passwordHash), RAW_PASSWORD)).resolves.toBe(true);
  });

  it('hashes, expires, counts attempts, invalidates, and atomically consumes one-time codes', async () => {
    const context = requireContext(disposable, repositories);
    const now = new Date();
    const codeHash = hashOneTimeCode(
      CODE_PEPPER,
      userId.toString(),
      'emailVerification',
      RAW_VERIFICATION_CODE,
    );
    const verificationCode = await context.repositories.oneTimeCodes.create({
      userId,
      type: 'emailVerification',
      targetEmail: 'auth.student@example.edu',
      codeHash,
      attempts: 0,
      expiresAt: new Date(now.getTime() + 600_000),
    });
    expect(verificationCode).not.toHaveProperty('codeHash');

    const rawCode = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.oneTimeCodes)
      .findOne({ _id: verificationCode._id });
    expect(rawCode?.codeHash).toBe(codeHash);
    expect(rawCode?.codeHash).not.toBe(RAW_VERIFICATION_CODE);
    expect(rawCode).not.toHaveProperty('code');
    expect(rawCode).not.toHaveProperty('otp');

    for (let attempt = 0; attempt < 5; attempt += 1) {
      await expect(
        context.repositories.oneTimeCodes.incrementAttempts(
          userId,
          verificationCode._id,
          now,
          5,
        ),
      ).resolves.toBe(true);
    }
    await expect(
      context.repositories.oneTimeCodes.incrementAttempts(userId, verificationCode._id, now, 5),
    ).resolves.toBe(false);
    const attemptedCode = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.oneTimeCodes)
      .findOne({ _id: verificationCode._id });
    expect(attemptedCode?.attempts).toBe(5);
    await expect(
      context.repositories.oneTimeCodes.findLatestActiveWithHash(
        userId,
        'emailVerification',
        now,
        5,
      ),
    ).resolves.toBeNull();

    const expiredCode = await context.repositories.oneTimeCodes.create({
      userId,
      type: 'passwordReset',
      targetEmail: 'auth.student@example.edu',
      codeHash: hashOneTimeCode(CODE_PEPPER, userId.toString(), 'passwordReset', '492018'),
      attempts: 0,
      expiresAt: new Date(now.getTime() - 1),
    });
    await expect(
      context.repositories.oneTimeCodes.consume(userId, expiredCode._id, now, 5),
    ).resolves.toBe(false);
    await expect(
      context.repositories.oneTimeCodes.findLatestActiveWithHash(
        userId,
        'passwordReset',
        now,
        5,
      ),
    ).resolves.toBeNull();

    const firstResendCode = await context.repositories.oneTimeCodes.create({
      userId,
      type: 'emailVerification',
      targetEmail: 'auth.student@example.edu',
      codeHash: hashOneTimeCode(CODE_PEPPER, userId.toString(), 'emailVerification', '105739'),
      attempts: 0,
      expiresAt: new Date(now.getTime() + 600_000),
    });
    await expect(
      context.repositories.oneTimeCodes.invalidateActiveForUserAndType(
        userId,
        'emailVerification',
        now,
      ),
    ).resolves.toBeGreaterThanOrEqual(1);
    const invalidated = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.oneTimeCodes)
      .findOne({ _id: firstResendCode._id });
    expect(invalidated?.consumedAt).toEqual(now);

    const replacementCode = await context.repositories.oneTimeCodes.create({
      userId,
      type: 'emailVerification',
      targetEmail: 'auth.student@example.edu',
      codeHash: hashOneTimeCode(CODE_PEPPER, userId.toString(), 'emailVerification', '775321'),
      attempts: 0,
      expiresAt: new Date(now.getTime() + 600_000),
    });
    const consumptionResults = await Promise.all([
      context.repositories.oneTimeCodes.consume(userId, replacementCode._id, now, 5),
      context.repositories.oneTimeCodes.consume(userId, replacementCode._id, now, 5),
    ]);
    expect(consumptionResults.filter(Boolean)).toHaveLength(1);
  });

  it('stores reset grants only as hashes and consumes them once', async () => {
    const context = requireContext(disposable, repositories);
    const now = new Date();
    const resetGrantHash = hashOpaqueToken(RAW_RESET_GRANT);
    await context.repositories.oneTimeCodes.create({
      userId,
      type: 'passwordResetGrant',
      targetEmail: 'auth.student@example.edu',
      codeHash: resetGrantHash,
      attempts: 0,
      expiresAt: new Date(now.getTime() + 600_000),
    });

    const results = await Promise.all([
      context.repositories.oneTimeCodes.consumeActiveByHash(
        'passwordResetGrant',
        resetGrantHash,
        now,
      ),
      context.repositories.oneTimeCodes.consumeActiveByHash(
        'passwordResetGrant',
        resetGrantHash,
        now,
      ),
    ]);
    expect(results.filter((result) => result !== null)).toHaveLength(1);
    expect(results.find((result) => result !== null)).not.toHaveProperty('codeHash');
  });

  it('creates, rotates, replay-revokes, logs out, and globally revokes hashed sessions', async () => {
    const context = requireContext(disposable, repositories);
    const now = new Date();
    const familyId = 'rotation-family';
    const original = await context.repositories.sessions.create({
      userId,
      familyId,
      refreshTokenHash: hashOpaqueToken(RAW_REFRESH_TOKEN),
      expiresAt: new Date(now.getTime() + 2_592_000_000),
    });
    expect(original).not.toHaveProperty('refreshTokenHash');

    const rawOriginal = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.sessions)
      .findOne({ _id: original._id });
    expect(rawOriginal?.refreshTokenHash).toBe(hashOpaqueToken(RAW_REFRESH_TOKEN));
    expect(rawOriginal?.refreshTokenHash).not.toBe(RAW_REFRESH_TOKEN);
    expect(rawOriginal).not.toHaveProperty('refreshToken');
    expect(rawOriginal).not.toHaveProperty('accessToken');

    const replacement = await context.repositories.sessions.rotate(
      original._id,
      {
        userId,
        familyId,
        refreshTokenHash: hashOpaqueToken(RAW_REPLACEMENT_TOKEN),
        expiresAt: new Date(now.getTime() + 2_592_000_000),
      },
      now,
    );
    const rotatedOriginal = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.sessions)
      .findOne({ _id: original._id });
    const rawReplacement = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.sessions)
      .findOne({ _id: replacement._id });
    expect(rotatedOriginal).toMatchObject({
      familyId,
      revokeReason: 'rotated',
      replacedBySessionId: replacement._id,
    });
    expect(rotatedOriginal?.revokedAt).toEqual(now);
    expect(rawReplacement?.familyId).toBe(familyId);
    expect(rawReplacement?.refreshTokenHash).toBe(hashOpaqueToken(RAW_REPLACEMENT_TOKEN));

    await expect(
      context.repositories.sessions.revokeFamily(familyId, new Date(now.getTime() + 1), 'replay'),
    ).resolves.toBe(1);
    const replayRevoked = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.sessions)
      .find({ familyId })
      .toArray();
    expect(replayRevoked).toHaveLength(2);
    expect(replayRevoked.every((session) => session.revokedAt instanceof Date)).toBe(true);

    const logoutToken = 'logout-refresh-token-never-persist';
    const logoutSession = await context.repositories.sessions.create({
      userId,
      familyId: 'logout-family',
      refreshTokenHash: hashOpaqueToken(logoutToken),
      expiresAt: new Date(now.getTime() + 2_592_000_000),
    });
    await context.repositories.sessions.revokeByRefreshTokenHash(
      hashOpaqueToken(logoutToken),
      now,
      'logout',
    );
    const loggedOut = await context.disposable.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.sessions)
      .findOne({ _id: logoutSession._id });
    expect(loggedOut).toMatchObject({ revokedAt: now, revokeReason: 'logout' });

    await context.repositories.sessions.create({
      userId,
      familyId: 'password-reset-family-1',
      refreshTokenHash: hashOpaqueToken('password-reset-session-one'),
      expiresAt: new Date(now.getTime() + 2_592_000_000),
    });
    await context.repositories.sessions.create({
      userId,
      familyId: 'password-reset-family-2',
      refreshTokenHash: hashOpaqueToken('password-reset-session-two'),
      expiresAt: new Date(now.getTime() + 2_592_000_000),
    });
    const resetAt = new Date(now.getTime() + 2);
    await expect(
      context.repositories.sessions.revokeAllForUser(userId, resetAt, 'passwordReset'),
    ).resolves.toBeGreaterThanOrEqual(2);
    const stillActive = await context.disposable.connection.db!
      .collection(COLLECTION_NAMES.sessions)
      .countDocuments({ userId, revokedAt: { $exists: false } });
    expect(stillActive).toBe(0);
  });

  it('never persists plaintext authentication secrets in any auth collection', async () => {
    const context = requireContext(disposable, repositories);
    const serializedDocuments: string[] = [];
    for (const collectionName of [
      COLLECTION_NAMES.users,
      COLLECTION_NAMES.sessions,
      COLLECTION_NAMES.oneTimeCodes,
    ]) {
      const documents = await context.disposable.connection.db!
        .collection(collectionName)
        .find()
        .toArray();
      serializedDocuments.push(JSON.stringify(documents));
    }
    const persisted = serializedDocuments.join('\n');
    for (const secret of [
      RAW_PASSWORD,
      RAW_VERIFICATION_CODE,
      RAW_REFRESH_TOKEN,
      RAW_REPLACEMENT_TOKEN,
      RAW_RESET_GRANT,
      RAW_ACCESS_TOKEN,
    ]) {
      expect(persisted).not.toContain(secret);
    }
  });
});
