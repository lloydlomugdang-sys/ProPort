import { randomUUID } from 'node:crypto';
import { Readable } from 'node:stream';
import type { FastifyInstance, LightMyRequestResponse } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config/env.js';
import { COLLECTION_NAMES } from '../../src/database/collection-names.js';
import { runMigrations } from '../../src/database/migrations/migration-runner.js';
import type { AppServices } from '../../src/infrastructure/create-services.js';
import type {
  EmailMessage,
  EmailSendResult,
  EmailSender,
} from '../../src/infrastructure/email/email-sender.js';
import type {
  ObjectStorage,
  StoredObject,
} from '../../src/infrastructure/storage/object-storage.js';
import { createTestServices } from '../helpers/build-test-app.js';
import {
  createDisposableMongoDatabase,
  type DisposableMongoDatabase,
} from '../helpers/disposable-mongodb.js';

interface ErrorEnvelope {
  readonly error: {
    readonly code: string;
    readonly message: string;
    readonly requestId: string;
    readonly fields?: Readonly<Record<string, readonly string[]>>;
  };
}

interface SessionCredentials {
  readonly userId: string;
  readonly accessToken: string;
  readonly refreshToken: string;
}

interface CurrentUserEnvelope {
  readonly data: {
    readonly user: {
      readonly id: string;
      readonly email: string;
      readonly firstName: string;
      readonly lastName: string;
      readonly program: string;
      readonly yearLevel: string;
      readonly school: string;
      readonly status: string;
      readonly emailVerifiedAt: string | null;
    };
  };
  readonly meta: { readonly requestId: string };
}

class CapturingEmailSender implements EmailSender {
  readonly messages: EmailMessage[] = [];

  async send(message: EmailMessage): Promise<EmailSendResult> {
    this.messages.push(message);
    return { messageId: `test-${this.messages.length}` };
  }

  async healthCheck() {
    return { status: 'console' as const };
  }

  latestCode(): string {
    const code = this.messages.at(-1)?.text?.match(/\b\d{6}\b/)?.[0];
    if (code === undefined) {
      throw new Error('The test email did not contain a six-digit code.');
    }
    return code;
  }
}

function bearer(accessToken: string): { readonly authorization: string } {
  return { authorization: `Bearer ${accessToken}` };
}

function expectError(
  response: LightMyRequestResponse,
  statusCode: number,
  code: string,
): ErrorEnvelope {
  expect(response.statusCode).toBe(statusCode);
  const body = response.json<ErrorEnvelope>();
  expect(body.error).toMatchObject({ code, requestId: response.headers['x-request-id'] });
  return body;
}

async function registerVerifiedUser(
  app: FastifyInstance,
  email: string,
  firstName: string,
): Promise<SessionCredentials> {
  const password = 'ProfilePassword8';
  const registration = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: { firstName, lastName: 'Student', email, password },
  });
  expect(registration.statusCode).toBe(201);

  const verification = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/email-verification/verify',
    payload: { email, code: emailSender.latestCode() },
  });
  expect(verification.statusCode).toBe(200);

  const login = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/login',
    payload: { email, password },
  });
  expect(login.statusCode).toBe(200);
  const session = login.json<{
    readonly data: {
      readonly user: { readonly id: string };
      readonly tokens: { readonly accessToken: string; readonly refreshToken: string };
    };
  }>();
  return {
    userId: session.data.user.id,
    accessToken: session.data.tokens.accessToken,
    refreshToken: session.data.tokens.refreshToken,
  };
}

class InMemoryTestStorage implements ObjectStorage {
  readonly items = new Map<string, Buffer>();

  async put(key: string, contents: Readable): Promise<StoredObject> {
    const chunks: Buffer[] = [];
    for await (const chunk of contents) {
      chunks.push(typeof chunk === 'string' ? Buffer.from(chunk) : chunk);
    }
    const buf = Buffer.concat(chunks);
    this.items.set(key, buf);
    return { key, sizeBytes: buf.length };
  }

  async get(key: string): Promise<Readable> {
    const data = this.items.get(key);
    if (!data) throw new Error(`Object not found in test storage: ${key}`);
    return Readable.from([data]);
  }

  async delete(key: string): Promise<void> {
    this.items.delete(key);
  }

  async exists(key: string): Promise<boolean> {
    return this.items.has(key);
  }

  async healthCheck() {
    return { status: 'up' as const };
  }
}

const samplePng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64',
);
const sampleJpeg = Buffer.from(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/AH//2Q==',
  'base64',
);

function multipartAvatarUpload(
  file: { readonly name: string; readonly mimeType: string; readonly contents: Buffer },
) {
  const boundary = `gradport-avatar-${randomUUID()}`;
  const chunks: Buffer[] = [
    Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${file.name}"\r\nContent-Type: ${file.mimeType}\r\n\r\n`,
    ),
    file.contents,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ];
  return {
    headers: { 'content-type': `multipart/form-data; boundary=${boundary}` },
    payload: Buffer.concat(chunks),
  };
}

let app: FastifyInstance | undefined;
let disposable: DisposableMongoDatabase | undefined;
let firstUser: SessionCredentials | undefined;
let secondUser: SessionCredentials | undefined;
const emailSender = new CapturingEmailSender();
const testStorage = new InMemoryTestStorage();

describe('authenticated current-user API with disposable MongoDB', () => {
  beforeAll(async () => {
    disposable = await createDisposableMongoDatabase();
    await runMigrations(disposable.connection.db!);
    const baseServices = createTestServices();
    const services: AppServices = {
      ...baseServices,
      database: disposable.database,
      email: emailSender,
      storage: testStorage,
    };
    app = await buildApp({
      config: loadConfig({ NODE_ENV: 'test', LOG_LEVEL: 'silent' }),
      services,
      connectDatabase: false,
    });
    firstUser = await registerVerifiedUser(app, 'profile.one@example.edu', 'Profile');
    secondUser = await registerVerifiedUser(app, 'profile.two@example.edu', 'Second');
  }, 120_000);

  afterAll(async () => {
    if (disposable !== undefined) {
      await disposable.stop();
    }
    if (app !== undefined) {
      await app.close();
    }
  }, 120_000);

  it('rejects unauthenticated GET and PATCH requests with the standard envelope', async () => {
    const getResponse = await app!.inject({ method: 'GET', url: '/api/v1/users/me' });
    expectError(getResponse, 401, 'UNAUTHORIZED');

    const patchResponse = await app!.inject({
      method: 'PATCH',
      url: '/api/v1/users/me',
      payload: { program: 'Not authorized' },
    });
    expectError(patchResponse, 401, 'UNAUTHORIZED');
  });

  it('returns only the authenticated user safe profile projection', async () => {
    const response = await app!.inject({
      method: 'GET',
      url: '/api/v1/users/me',
      headers: bearer(firstUser!.accessToken),
    });
    expect(response.statusCode).toBe(200);
    const body = response.json<CurrentUserEnvelope>();
    expect(body.data.user).toMatchObject({
      id: firstUser!.userId,
      email: 'profile.one@example.edu',
      firstName: 'Profile',
      lastName: 'Student',
      program: '',
      yearLevel: '',
      school: 'New Era University',
      status: 'active',
    });
    expect(body.meta.requestId).toBe(response.headers['x-request-id']);

    const serialized = JSON.stringify(body);
    for (const forbidden of [
      'passwordHash',
      'refreshTokenHash',
      'codeHash',
      'avatarObjectKey',
      'avatarMimeType',
      'lastLoginAt',
      'createdAt',
      'updatedAt',
      'session',
    ]) {
      expect(serialized).not.toContain(forbidden);
    }
  });

  it('normalizes and persists allowed profile edits', async () => {
    const response = await app!.inject({
      method: 'PATCH',
      url: '/api/v1/users/me',
      headers: bearer(firstUser!.accessToken),
      payload: {
        firstName: '  Updated  ',
        lastName: '  Learner  ',
        program: '  Bachelor of Science in Information Technology  ',
        yearLevel: '  3rd Year  ',
        school: '  New Era University  ',
      },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json<CurrentUserEnvelope>().data.user).toMatchObject({
      id: firstUser!.userId,
      email: 'profile.one@example.edu',
      firstName: 'Updated',
      lastName: 'Learner',
      program: 'Bachelor of Science in Information Technology',
      yearLevel: '3rd Year',
      school: 'New Era University',
    });

    const persisted = await disposable!.connection.db!
      .collection<Record<string, unknown>>(COLLECTION_NAMES.users)
      .findOne({ email: 'profile.one@example.edu' });
    expect(persisted).toMatchObject({
      firstName: 'Updated',
      lastName: 'Learner',
      program: 'Bachelor of Science in Information Technology',
      yearLevel: '3rd Year',
      school: 'New Era University',
    });
  });

  it('rejects invalid and unsupported profile fields without changing ownership', async () => {
    const whitespaceName = await app!.inject({
      method: 'PATCH',
      url: '/api/v1/users/me',
      headers: bearer(firstUser!.accessToken),
      payload: { firstName: '   ' },
    });
    const nameError = expectError(whitespaceName, 400, 'VALIDATION_ERROR');
    expect(nameError.error.fields?.firstName).toBeDefined();

    for (const payload of [
      {},
      { email: 'changed@example.edu' },
      { userId: secondUser!.userId, program: 'Ownership violation' },
      { status: 'disabled' },
      { avatarObjectKey: 'users/other/avatar.png' },
    ]) {
      const response = await app!.inject({
        method: 'PATCH',
        url: '/api/v1/users/me',
        headers: bearer(firstUser!.accessToken),
        payload,
      });
      expectError(response, 400, 'VALIDATION_ERROR');
    }

    const clientSelectedOwner = await app!.inject({
      method: 'GET',
      url: `/api/v1/users/me?userId=${secondUser!.userId}`,
      headers: bearer(firstUser!.accessToken),
    });
    expectError(clientSelectedOwner, 400, 'VALIDATION_ERROR');

    const secondProfile = await app!.inject({
      method: 'GET',
      url: '/api/v1/users/me',
      headers: bearer(secondUser!.accessToken),
    });
    expect(secondProfile.statusCode).toBe(200);
    expect(secondProfile.json<CurrentUserEnvelope>().data.user).toMatchObject({
      id: secondUser!.userId,
      email: 'profile.two@example.edu',
      firstName: 'Second',
      program: '',
    });
  });

  it('rejects an otherwise valid access token after its session is revoked', async () => {
    const logout = await app!.inject({
      method: 'POST',
      url: '/api/v1/auth/logout',
      payload: { refreshToken: firstUser!.refreshToken },
    });
    expect(logout.statusCode).toBe(200);

    const response = await app!.inject({
      method: 'GET',
      url: '/api/v1/users/me',
      headers: bearer(firstUser!.accessToken),
    });
    expectError(response, 401, 'UNAUTHORIZED');
  });

  it('rejects unauthenticated avatar requests', async () => {
    const getAvatar = await app!.inject({ method: 'GET', url: '/api/v1/users/me/avatar' });
    expectError(getAvatar, 401, 'UNAUTHORIZED');

    const postAvatar = await app!.inject({ method: 'POST', url: '/api/v1/users/me/avatar' });
    expectError(postAvatar, 401, 'UNAUTHORIZED');

    const deleteAvatar = await app!.inject({ method: 'DELETE', url: '/api/v1/users/me/avatar' });
    expectError(deleteAvatar, 401, 'UNAUTHORIZED');
  });

  it('manages avatar lifecycle: upload, isolated retrieval, replacement, and deletion', async () => {
    // 1. Initially secondUser has no avatar -> 404 NOT_FOUND
    const initialGet = await app!.inject({
      method: 'GET',
      url: '/api/v1/users/me/avatar',
      headers: bearer(secondUser!.accessToken),
    });
    expectError(initialGet, 404, 'AVATAR_NOT_FOUND');

    // 2. Upload invalid image format -> 400 VALIDATION_ERROR
    const invalidUpload = multipartAvatarUpload({
      name: 'corrupt.png',
      mimeType: 'image/png',
      contents: Buffer.from('Not a real PNG image file!'),
    });
    const invalidResponse = await app!.inject({
      method: 'POST',
      url: '/api/v1/users/me/avatar',
      headers: { ...bearer(secondUser!.accessToken), ...invalidUpload.headers },
      payload: invalidUpload.payload,
    });
    expectError(invalidResponse, 400, 'VALIDATION_ERROR');

    // 3. Upload valid PNG -> 200 OK with hasAvatar: true
    const validUpload = multipartAvatarUpload({
      name: 'avatar.png',
      mimeType: 'image/png',
      contents: samplePng,
    });
    const uploadResponse = await app!.inject({
      method: 'POST',
      url: '/api/v1/users/me/avatar',
      headers: { ...bearer(secondUser!.accessToken), ...validUpload.headers },
      payload: validUpload.payload,
    });
    expect(uploadResponse.statusCode).toBe(200);
    const uploadBody = uploadResponse.json<{ data: { user: { id: string; hasAvatar: boolean } } }>();
    expect(uploadBody.data.user.id).toBe(secondUser!.userId);
    expect(uploadBody.data.user.hasAvatar).toBe(true);

    // Verify raw secrets/keys not exposed
    const serializedUpload = JSON.stringify(uploadBody);
    expect(serializedUpload).not.toContain('avatarObjectKey');

    // 4. Retrieve avatar -> 200 image/png matching samplePng
    const retrievedAvatar = await app!.inject({
      method: 'GET',
      url: '/api/v1/users/me/avatar',
      headers: bearer(secondUser!.accessToken),
    });
    expect(retrievedAvatar.statusCode).toBe(200);
    expect(retrievedAvatar.headers['content-type']).toBe('image/png');
    expect(retrievedAvatar.rawPayload).toEqual(samplePng);

    // 5. GET /api/v1/users/me reports hasAvatar: true
    const profileResponse = await app!.inject({
      method: 'GET',
      url: '/api/v1/users/me',
      headers: bearer(secondUser!.accessToken),
    });
    expect(profileResponse.statusCode).toBe(200);
    const profileBody = profileResponse.json<{ data: { user: { hasAvatar: boolean } } }>();
    expect(profileBody.data.user.hasAvatar).toBe(true);

    // 6. User isolation: Re-register or login a 3rd user without avatar, cannot access secondUser's avatar
    const thirdUser = await registerVerifiedUser(app!, 'profile.three@example.edu', 'Third');
    const thirdUserAvatar = await app!.inject({
      method: 'GET',
      url: '/api/v1/users/me/avatar',
      headers: bearer(thirdUser.accessToken),
    });
    expectError(thirdUserAvatar, 404, 'AVATAR_NOT_FOUND');

    // 7. Replace avatar with JPEG -> 200 OK
    const replaceUpload = multipartAvatarUpload({
      name: 'avatar.jpg',
      mimeType: 'image/jpeg',
      contents: sampleJpeg,
    });
    const replaceResponse = await app!.inject({
      method: 'POST',
      url: '/api/v1/users/me/avatar',
      headers: { ...bearer(secondUser!.accessToken), ...replaceUpload.headers },
      payload: replaceUpload.payload,
    });
    expect(replaceResponse.statusCode).toBe(200);

    const updatedAvatar = await app!.inject({
      method: 'GET',
      url: '/api/v1/users/me/avatar',
      headers: bearer(secondUser!.accessToken),
    });
    expect(updatedAvatar.statusCode).toBe(200);
    expect(updatedAvatar.headers['content-type']).toBe('image/jpeg');
    expect(updatedAvatar.rawPayload).toEqual(sampleJpeg);

    // 8. Delete avatar -> 200 OK with hasAvatar: false
    const deleteResponse = await app!.inject({
      method: 'DELETE',
      url: '/api/v1/users/me/avatar',
      headers: bearer(secondUser!.accessToken),
    });
    expect(deleteResponse.statusCode).toBe(200);
    const deleteBody = deleteResponse.json<{ data: { user: { hasAvatar: boolean } } }>();
    expect(deleteBody.data.user.hasAvatar).toBe(false);

    // 9. Now GET avatar returns 404 and storage is empty
    const finalGet = await app!.inject({
      method: 'GET',
      url: '/api/v1/users/me/avatar',
      headers: bearer(secondUser!.accessToken),
    });
    expectError(finalGet, 404, 'AVATAR_NOT_FOUND');
    expect(testStorage.items.size).toBe(0);
  });
});
