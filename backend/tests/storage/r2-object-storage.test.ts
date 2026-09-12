import { Readable } from 'node:stream';
import { describe, expect, it } from 'vitest';
import type { R2Config } from '../../src/config/env.types.js';
import {
  R2ObjectStorage,
  type R2StorageTransport,
} from '../../src/infrastructure/storage/r2-object-storage.js';

const R2_CONFIG: R2Config = {
  endpoint: 'https://test-account.r2.cloudflarestorage.com',
  accessKeyId: 'test-only-r2-access-key',
  secretAccessKey: 'test-only-r2-secret-key',
  bucket: 'gradport-test',
  region: 'auto',
};

class FakeR2Transport implements R2StorageTransport {
  readonly objects = new Map<string, Buffer>();
  healthError: Error | undefined;

  async putObject(input: { readonly bucket: string; readonly key: string; readonly body: Buffer }) {
    expect(input.bucket).toBe(R2_CONFIG.bucket);
    this.objects.set(input.key, Buffer.from(input.body));
  }

  async getObject(input: { readonly bucket: string; readonly key: string }): Promise<Readable> {
    const value = this.objects.get(input.key);
    if (value === undefined) throw new Error('Fake object is missing.');
    return Readable.from([value]);
  }

  async deleteObject(input: { readonly bucket: string; readonly key: string }) {
    this.objects.delete(input.key);
  }

  async objectExists(input: { readonly bucket: string; readonly key: string }) {
    return this.objects.has(input.key);
  }

  async bucketExists(bucket: string) {
    expect(bucket).toBe(R2_CONFIG.bucket);
    if (this.healthError !== undefined) throw this.healthError;
  }
}

async function readAll(stream: Readable): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk as Uint8Array));
  }
  return Buffer.concat(chunks);
}

describe('R2ObjectStorage', () => {
  it('stores, streams, checks, and deletes a private object through an injected transport', async () => {
    const transport = new FakeR2Transport();
    const storage = new R2ObjectStorage(R2_CONFIG, transport);
    const key = 'users/507f1f77bcf86cd799439011/documents/test-file.pdf';
    const contents = Buffer.from('private document bytes');

    await expect(storage.put(key, Readable.from([contents]))).resolves.toEqual({
      key,
      sizeBytes: contents.length,
    });
    await expect(storage.exists(key)).resolves.toBe(true);
    expect(await readAll(await storage.get(key))).toEqual(contents);

    await storage.delete(key);
    await expect(storage.exists(key)).resolves.toBe(false);
  });

  it.each(['', '/absolute.pdf', '../escape.pdf', 'users//file.pdf', 'users\\file.pdf'])(
    'rejects unsafe object key %j before calling R2',
    async (key) => {
      const transport = new FakeR2Transport();
      const storage = new R2ObjectStorage(R2_CONFIG, transport);
      await expect(storage.put(key, Readable.from(['no']))).rejects.toThrow('Invalid storage key');
      expect(transport.objects.size).toBe(0);
    },
  );

  it('reports sanitized cloud-storage readiness without exposing configuration', async () => {
    const transport = new FakeR2Transport();
    const storage = new R2ObjectStorage(R2_CONFIG, transport);
    await expect(storage.healthCheck()).resolves.toEqual({
      status: 'up',
      detail: 'Cloud object storage is available.',
    });

    transport.healthError = new Error('provider detail containing private endpoint');
    const health = await storage.healthCheck();
    expect(health).toEqual({
      status: 'down',
      detail: 'Cloud object storage is unavailable.',
    });
    expect(JSON.stringify(health)).not.toContain(R2_CONFIG.endpoint);
    expect(JSON.stringify(health)).not.toContain(R2_CONFIG.accessKeyId);
    expect(JSON.stringify(health)).not.toContain(R2_CONFIG.secretAccessKey);
  });
});
