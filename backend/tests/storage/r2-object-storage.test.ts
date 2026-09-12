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
  readonly operations: Array<{
    readonly type: 'put' | 'head' | 'delete';
    readonly key: string;
    readonly body?: Buffer;
  }> = [];
  putError: Error | undefined;
  headError: Error | undefined;
  deleteError: Error | undefined;

  async putObject(input: { readonly bucket: string; readonly key: string; readonly body: Buffer }) {
    expect(input.bucket).toBe(R2_CONFIG.bucket);
    this.operations.push({ type: 'put', key: input.key, body: Buffer.from(input.body) });
    if (this.putError !== undefined) throw this.putError;
    this.objects.set(input.key, Buffer.from(input.body));
  }

  async getObject(input: { readonly bucket: string; readonly key: string }): Promise<Readable> {
    const value = this.objects.get(input.key);
    if (value === undefined) throw new Error('Fake object is missing.');
    return Readable.from([value]);
  }

  async deleteObject(input: { readonly bucket: string; readonly key: string }) {
    expect(input.bucket).toBe(R2_CONFIG.bucket);
    this.operations.push({ type: 'delete', key: input.key });
    if (this.deleteError !== undefined) throw this.deleteError;
    this.objects.delete(input.key);
  }

  async objectExists(input: { readonly bucket: string; readonly key: string }) {
    expect(input.bucket).toBe(R2_CONFIG.bucket);
    this.operations.push({ type: 'head', key: input.key });
    if (this.headError !== undefined) throw this.headError;
    return this.objects.has(input.key);
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

  it('probes cloud-storage readiness with a unique temporary object and cleans it up', async () => {
    const transport = new FakeR2Transport();
    const storage = new R2ObjectStorage(R2_CONFIG, transport);
    await expect(storage.healthCheck()).resolves.toEqual({
      status: 'up',
      detail: 'Cloud object storage is available.',
    });

    expect(transport.operations.map(({ type }) => type)).toEqual(['put', 'head', 'delete']);
    const [put, head, remove] = transport.operations;
    expect(put?.key).toMatch(/^_healthcheck\/[0-9a-f-]+\.txt$/);
    expect(put?.body?.toString('utf8')).toBe('ok');
    expect(head?.key).toBe(put?.key);
    expect(remove?.key).toBe(put?.key);
    expect(transport.objects.size).toBe(0);

    await storage.healthCheck();
    expect(transport.operations[3]?.key).not.toBe(put?.key);
  });

  it('attempts cleanup and reports sanitized readiness when the object HEAD fails', async () => {
    const transport = new FakeR2Transport();
    const storage = new R2ObjectStorage(R2_CONFIG, transport);
    transport.headError = new Error('provider detail containing private endpoint');

    const health = await storage.healthCheck();
    expect(health).toEqual({
      status: 'down',
      detail: 'Cloud object storage is unavailable.',
    });
    expect(transport.operations.map(({ type }) => type)).toEqual(['put', 'head', 'delete']);
    expect(transport.objects.size).toBe(0);
    expect(JSON.stringify(health)).not.toContain(R2_CONFIG.endpoint);
    expect(JSON.stringify(health)).not.toContain(R2_CONFIG.accessKeyId);
    expect(JSON.stringify(health)).not.toContain(R2_CONFIG.secretAccessKey);
  });

  it('reports readiness as down when temporary-object cleanup fails', async () => {
    const transport = new FakeR2Transport();
    const storage = new R2ObjectStorage(R2_CONFIG, transport);
    transport.deleteError = new Error('delete denied');

    await expect(storage.healthCheck()).resolves.toEqual({
      status: 'down',
      detail: 'Cloud object storage is unavailable.',
    });
    expect(transport.operations.map(({ type }) => type)).toEqual(['put', 'head', 'delete']);
  });
});
