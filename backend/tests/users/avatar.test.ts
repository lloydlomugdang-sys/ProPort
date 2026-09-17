import { Readable } from 'node:stream';
import { Types } from 'mongoose';
import { describe, expect, it, vi } from 'vitest';
import { AppError } from '../../src/common/errors/app-error.js';
import type { DatabaseConnection } from '../../src/infrastructure/database/database-connection.js';
import type { ObjectStorage, StoredObject } from '../../src/infrastructure/storage/object-storage.js';
import {
  CurrentUserService,
  MAX_AVATAR_FILE_SIZE_BYTES,
  validateAvatarImage,
} from '../../src/modules/users/user.service.js';

const VALID_JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);
const VALID_PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00]);
const VALID_WEBP = Buffer.concat([
  Buffer.from('RIFF'),
  Buffer.alloc(4),
  Buffer.from('WEBPVP8 '),
]);

class MockStorage implements ObjectStorage {
  readonly files = new Map<string, Buffer>();
  readonly deletedKeys: string[] = [];

  async put(key: string, contents: Readable): Promise<StoredObject> {
    const chunks: Buffer[] = [];
    for await (const chunk of contents) {
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    }
    const buf = Buffer.concat(chunks);
    this.files.set(key, buf);
    return { key, sizeBytes: buf.length };
  }

  async get(key: string): Promise<Readable> {
    const data = this.files.get(key);
    if (!data) throw new Error('Not found');
    return Readable.from([data]);
  }

  async delete(key: string): Promise<void> {
    this.deletedKeys.push(key);
    this.files.delete(key);
  }

  async exists(key: string): Promise<boolean> {
    return this.files.has(key);
  }

  async healthCheck() {
    return { status: 'up' as const };
  }
}

describe('Avatar image validation', () => {
  it('accepts valid JPEG, PNG, and WEBP image data', () => {
    expect(validateAvatarImage(VALID_JPEG)).toEqual({ extension: 'jpg', mimeType: 'image/jpeg' });
    expect(validateAvatarImage(VALID_PNG)).toEqual({ extension: 'png', mimeType: 'image/png' });
    expect(validateAvatarImage(VALID_WEBP)).toEqual({ extension: 'webp', mimeType: 'image/webp' });
  });

  it('rejects empty, oversized, or non-image buffers', () => {
    expect(() => validateAvatarImage(Buffer.alloc(0))).toThrow(AppError);
    expect(() => validateAvatarImage(Buffer.alloc(MAX_AVATAR_FILE_SIZE_BYTES + 1))).toThrow(AppError);
    expect(() => validateAvatarImage(Buffer.from('hello plain text not an image'))).toThrow(AppError);
  });
});

describe('Avatar service lifecycle and failure safety', () => {
  function createMockContext(initialAvatarKey?: string) {
    const userId = new Types.ObjectId();
    const sessionId = new Types.ObjectId();
    let currentAvatarKey = initialAvatarKey;
    let currentAvatarMime = initialAvatarKey ? 'image/jpeg' : undefined;

    const mockUser = {
      _id: userId,
      email: 'student@example.com',
      firstName: 'John',
      lastName: 'Lloyd',
      program: 'BSIT',
      yearLevel: '4th Year',
      school: 'College of Information Technology',
      status: 'active' as const,
      avatarObjectKey: currentAvatarKey,
      avatarMimeType: currentAvatarMime,
      createdAt: new Date(),
      updatedAt: new Date(),
    };

    const mockSession = {
      _id: sessionId,
      userId,
      revokedAt: undefined,
      expiresAt: new Date(Date.now() + 3600000),
    };

    const storage = new MockStorage();
    if (initialAvatarKey) {
      storage.files.set(initialAvatarKey, VALID_JPEG);
    }

    const repositories = {
      users: {
        findById: vi.fn().mockImplementation(async (id: Types.ObjectId) => {
          if (id.equals(userId)) {
            return {
              ...mockUser,
              avatarObjectKey: currentAvatarKey,
              avatarMimeType: currentAvatarMime,
            };
          }
          return null;
        }),
        updateById: vi.fn().mockImplementation(async (id: Types.ObjectId, patch: Record<string, unknown>) => {
          if (id.equals(userId)) {
            currentAvatarKey = patch.avatarObjectKey as string;
            currentAvatarMime = patch.avatarMimeType as string;
            return {
              ...mockUser,
              avatarObjectKey: currentAvatarKey,
              avatarMimeType: currentAvatarMime,
            };
          }
          return null;
        }),
      },
      sessions: {
        findByIdForUser: vi.fn().mockResolvedValue(mockSession),
      },
    };

    const database = {
      status: 'connected' as const,
      mongooseConnection: {
        readyState: 1,
      } as unknown as NonNullable<DatabaseConnection['mongooseConnection']>,
    } as unknown as DatabaseConnection;

    const logger = {
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    };

    const service = new CurrentUserService(database, storage, logger);
    // Inject mock repositories
    (service as unknown as { repositories: () => typeof repositories }).repositories = () => repositories;

    return { userId, storage, service, repositories, logger };
  }

  it('uploads initial avatar and sets hasAvatar: true', async () => {
    const { userId, storage, service } = createMockContext();
    const result = await service.uploadAvatar(userId, { contents: VALID_PNG });

    expect(result.hasAvatar).toBe(true);
    expect(storage.files.size).toBe(1);
    const uploadedKey = Array.from(storage.files.keys())[0]!;
    expect(uploadedKey).toMatch(new RegExp(`^users/${userId.toString()}/avatar/[a-f0-9-]+\\.png$`));
  });

  it('replaces existing avatar and cleans up previous R2 object', async () => {
    const oldKey = 'users/123/avatar/old-avatar.jpg';
    const { userId, storage, service } = createMockContext(oldKey);

    const result = await service.uploadAvatar(userId, { contents: VALID_JPEG });

    expect(result.hasAvatar).toBe(true);
    expect(storage.deletedKeys).toContain(oldKey);
    expect(storage.files.has(oldKey)).toBe(false);
    expect(storage.files.size).toBe(1);
  });

  it('cleans up newly uploaded object if database update fails, preserving previous avatar', async () => {
    const oldKey = 'users/123/avatar/old-avatar.jpg';
    const { userId, storage, service, repositories } = createMockContext(oldKey);

    repositories.users.updateById.mockRejectedValueOnce(new Error('Simulated DB write failure'));

    await expect(service.uploadAvatar(userId, { contents: VALID_PNG })).rejects.toMatchObject({
      code: 'DATABASE_ERROR',
    });

    // Previous avatar must still exist
    expect(storage.files.has(oldKey)).toBe(true);
    // New object must have been deleted (no orphan)
    expect(storage.files.size).toBe(1);
    expect(storage.deletedKeys.length).toBe(1);
    expect(storage.deletedKeys[0]).not.toBe(oldKey);
  });

  it('does not roll back new avatar if deleting the old object fails', async () => {
    const oldKey = 'users/123/avatar/old-avatar.jpg';
    const { userId, storage, service, logger } = createMockContext(oldKey);

    vi.spyOn(storage, 'delete').mockImplementationOnce(async () => {
      throw new Error('R2 delete network timeout');
    });

    const result = await service.uploadAvatar(userId, { contents: VALID_JPEG });

    expect(result.hasAvatar).toBe(true);
    expect(logger.warn).toHaveBeenCalledWith(
      expect.objectContaining({ previousKey: oldKey }),
      expect.any(String),
    );
  });

  it('retrieves avatar stream and handles 404 when no avatar exists', async () => {
    const { userId, service } = createMockContext();
    await expect(service.getAvatar(userId)).rejects.toMatchObject({
      code: 'AVATAR_NOT_FOUND',
      statusCode: 404,
    });

    await service.uploadAvatar(userId, { contents: VALID_JPEG });
    const avatar = await service.getAvatar(userId);
    expect(avatar.mimeType).toBe('image/jpeg');
    expect(avatar.stream).toBeInstanceOf(Readable);
  });

  it('deletes avatar, clears database fields, and removes object from storage', async () => {
    const initialKey = 'users/123/avatar/initial.jpg';
    const { userId, storage, service } = createMockContext(initialKey);

    const result = await service.deleteAvatar(userId);
    expect(result.hasAvatar).toBe(false);
    expect(storage.deletedKeys).toContain(initialKey);
    expect(storage.files.has(initialKey)).toBe(false);
  });
});
