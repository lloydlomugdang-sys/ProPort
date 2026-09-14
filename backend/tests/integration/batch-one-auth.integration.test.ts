import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config/env.js';
import { COLLECTION_NAMES } from '../../src/database/collection-names.js';
import { runMigrations } from '../../src/database/migrations/migration-runner.js';
import { UserRepository } from '../../src/database/repositories/user.repository.js';
import { SessionRepository } from '../../src/database/repositories/session.repository.js';
import { hashOpaqueToken, verifyPassword } from '../../src/modules/auth/auth.crypto.js';
import { PROFILE_OPTIONS } from '../../src/modules/users/profile-options.js';
import { createTestServices } from '../helpers/build-test-app.js';
import { createDisposableMongoDatabase, type DisposableMongoDatabase } from '../helpers/disposable-mongodb.js';

interface SessionBody { data: { user: { id: string }; tokens: { accessToken: string; refreshToken: string } } }

describe.sequential('Batch 1 authenticated workflows (disposable MongoDB only)', () => {
  let database: DisposableMongoDatabase;
  let app: FastifyInstance;
  let latestCode = '';
  let deliveries = 0;
  let requestNumber = 0;
  const email = 'batch@example.test';
  const password = ' OriginalPassword9 ';
  const newPassword = ' ChangedPassword8 ';
  let session: SessionBody['data'];
  const post = (path: string, payload: Record<string, string>, token?: string) => app.inject({
    method: 'POST', url: `/api/v1/auth/${path}`, payload,
    remoteAddress: `127.0.0.${++requestNumber}`, // Independent test clients; real limits remain enabled.
    ...(token === undefined ? {} : { headers: { authorization: `Bearer ${token}` } }),
  });
  beforeAll(async () => {
    database = await createDisposableMongoDatabase();
    await runMigrations(database.connection.db!);
    app = await buildApp({ config: loadConfig({ NODE_ENV: 'test', LOG_LEVEL: 'silent' }), connectDatabase: false,
      services: { ...createTestServices(), database: database.database, email: {
        async send(message) {
          latestCode = message.text?.match(/code is ([0-9]{6})\./)?.[1] ?? '';
          deliveries++;
          return { messageId: 'test-only' };
        },
        async healthCheck() { return { status: 'console' as const }; },
      } },
    });
    await app.ready();
  });
  afterAll(async () => { vi.restoreAllMocks(); await database?.stop(); await app?.close(); });

  it('rejects numeric names and resumes only a credential-matched pending signup without resending', async () => {
    const invalid = await post('register', { email, firstName: 'John123', lastName: 'Student', password });
    expect(invalid.statusCode).toBe(400);
    expect(invalid.json()).toMatchObject({ error: { fields: { firstName: ['Names cannot contain numbers.'] } } });
    const payload = { email, firstName: 'José', lastName: "O'Connor", password };
    expect((await post('register', payload)).statusCode).toBe(201);
    expect((await post('register', payload)).json()).toMatchObject({ error: { code: 'EMAIL_NOT_VERIFIED' } });
    expect((await post('register', { ...payload, password: 'IncorrectPassword8' })).statusCode).toBe(409);
    expect(deliveries).toBe(1);
    expect(await database.connection.db!.collection(COLLECTION_NAMES.users).countDocuments({ email })).toBe(1);
    expect(await database.connection.db!.collection(COLLECTION_NAMES.sessions).countDocuments()).toBe(0);
  });

  it('invalid OTP cannot authenticate; a session-write failure rolls back verification; valid OTP issues restorable tokens once', async () => {
    const wrong = latestCode === '000000' ? '111111' : '000000';
    expect((await post('email-verification/verify', { email, code: wrong })).statusCode).toBe(400);
    expect(await database.connection.db!.collection(COLLECTION_NAMES.sessions).countDocuments()).toBe(0);
    const write = vi.spyOn(SessionRepository.prototype, 'create').mockRejectedValueOnce(new Error('test write failure'));
    const failed = await post('email-verification/verify', { email, code: latestCode });
    expect(failed.statusCode).toBe(500);
    expect(failed.body).not.toContain('test write failure');
    write.mockRestore();
    expect(await database.connection.db!.collection(COLLECTION_NAMES.users).findOne({ email })).toMatchObject({ status: 'pendingVerification' });
    const verified = await post('email-verification/verify', { email, code: latestCode });
    expect(verified.statusCode).toBe(200);
    session = verified.json<SessionBody>().data;
    expect(session.tokens.accessToken).toBeTruthy();
    expect(verified.body).not.toMatch(/passwordHash|codeHash|refreshTokenHash/);
    expect((await post('email-verification/verify', { email, code: latestCode })).statusCode).toBe(400);
    const restored = await post('refresh', { refreshToken: session.tokens.refreshToken });
    expect(restored.statusCode).toBe(200);
    session = restored.json<SessionBody>().data;
  });

  it('validates shared profile choices and preserves legacy values without changing ownership', async () => {
    const headers = { authorization: `Bearer ${session.tokens.accessToken}` };
    const me = await app.inject({ method: 'GET', url: '/api/v1/users/me', headers });
    expect(me.json()).toMatchObject({ data: { profileOptions: PROFILE_OPTIONS, user: { school: PROFILE_OPTIONS.school } } });
    for (const payload of [{ program: 'Invented degree' }, { yearLevel: '9th Year' }, { school: 'Another School' }, { firstName: 'Name9' }]) {
      expect((await app.inject({ method: 'PATCH', url: '/api/v1/users/me', headers, payload })).statusCode).toBe(400);
    }
    await database.connection.db!.collection(COLLECTION_NAMES.users).updateOne({ email }, { $set: { school: 'Legacy School', program: 'Legacy Program' } });
    const saved = await app.inject({ method: 'PATCH', url: '/api/v1/users/me', headers,
      payload: { firstName: 'John Lloyd', program: 'Legacy Program', school: 'Legacy School', yearLevel: '4th Year' } });
    expect(saved.statusCode).toBe(200);
    expect(saved.json()).toMatchObject({ data: { user: { id: session.user.id, school: 'Legacy School', yearLevel: '4th Year' } } });
  });

  it('changes the real Argon2id hash atomically; logout/new login succeeds and old password fails', async () => {
    const loggedIn = await post('login', { email, password });
    expect(loggedIn.statusCode).toBe(200);
    session = loggedIn.json<SessionBody>().data;
    const token = session.tokens.accessToken;
    expect((await post('password/change', { currentPassword: password, newPassword })).statusCode).toBe(401);
    expect((await post('password/change', { currentPassword: 'wrong', newPassword }, token)).statusCode).toBe(400);
    const write = vi.spyOn(UserRepository.prototype, 'replacePasswordHash').mockResolvedValueOnce(false);
    expect((await post('password/change', { currentPassword: password, newPassword }, token)).statusCode).toBe(400);
    write.mockRestore();
    expect((await post('login', { email, password })).statusCode).toBe(200);
    expect((await post('password/change', { currentPassword: password, newPassword }, token)).statusCode).toBe(200);
    const raw = await database.connection.db!.collection<{ passwordHash: string }>(COLLECTION_NAMES.users).findOne({ email });
    expect(raw?.passwordHash).toMatch(/^\$argon2id\$/);
    expect(await verifyPassword(raw!.passwordHash, newPassword)).toBe(true);
    expect(await verifyPassword(raw!.passwordHash, password)).toBe(false);
    expect(JSON.stringify(raw)).not.toContain(newPassword);
    const sessions = database.connection.db!.collection(COLLECTION_NAMES.sessions);
    expect(await sessions.countDocuments({ revokedAt: { $exists: false } })).toBe(0);
    expect(await sessions.findOne({ refreshTokenHash: hashOpaqueToken(session.tokens.refreshToken) })).toMatchObject({ revokeReason: 'passwordChange' });
    expect((await post('logout', { refreshToken: session.tokens.refreshToken })).statusCode).toBe(200);
    expect((await post('refresh', { refreshToken: session.tokens.refreshToken })).statusCode).toBe(401);
    expect((await post('login', { email, password: newPassword })).statusCode).toBe(200);
    expect((await post('login', { email, password })).statusCode).toBe(401);
    expect((await post('login', { email, password: newPassword.trim() })).statusCode).toBe(401);
  });

  it('password reset also persists and rejects the replaced password', async () => {
    expect((await post('password-reset/request', { email })).statusCode).toBe(202);
    const verified = await post('password-reset/verify', { email, code: latestCode });
    const { resetToken } = verified.json<{ data: { resetToken: string } }>().data;
    const resetPassword = 'ResetPassword7';
    expect((await post('password-reset/complete', { resetToken, newPassword: resetPassword })).statusCode).toBe(200);
    expect((await post('password-reset/complete', { resetToken, newPassword: resetPassword })).statusCode).toBe(400);
    expect((await post('login', { email, password: resetPassword })).statusCode).toBe(200);
    expect((await post('login', { email, password: newPassword })).statusCode).toBe(401);
  });
});
