import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Readable } from 'node:stream';
import { afterEach, describe, expect, it } from 'vitest';
import { LocalObjectStorage } from '../../src/infrastructure/storage/local-object-storage.js';

describe('LocalObjectStorage', () => {
  const roots: string[] = [];

  afterEach(async () => {
    await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
  });

  it('stores, reads, and deletes bytes beneath its configured root', async () => {
    const root = await mkdtemp(join(tmpdir(), 'gradport-storage-test-'));
    roots.push(root);
    const storage = new LocalObjectStorage(root);
    const contents = Buffer.from('stored document');

    await expect(storage.put('users/user/documents/file.pdf', Readable.from([contents]))).resolves
      .toMatchObject({ key: 'users/user/documents/file.pdf', sizeBytes: contents.length });
    expect(await readFile(join(root, 'users', 'user', 'documents', 'file.pdf'))).toEqual(contents);
    expect(await storage.exists('users/user/documents/file.pdf')).toBe(true);

    await storage.delete('users/user/documents/file.pdf');
    expect(await storage.exists('users/user/documents/file.pdf')).toBe(false);
  });

  it.each(['', '../outside.pdf', 'users/../outside.pdf', '/absolute.pdf', 'users//file.pdf'])(
    'rejects unsafe storage key %j',
    async (key) => {
      const root = await mkdtemp(join(tmpdir(), 'gradport-storage-test-'));
      roots.push(root);
      const storage = new LocalObjectStorage(root);
      await expect(storage.put(key, Readable.from(['no']))).rejects.toThrow(/Invalid storage key/);
    },
  );

  it('removes a partial object when the input stream fails', async () => {
    const root = await mkdtemp(join(tmpdir(), 'gradport-storage-test-'));
    roots.push(root);
    const storage = new LocalObjectStorage(root);
    const failedStream = new Readable({
      read() {
        this.push('partial');
        this.destroy(new Error('stream failed'));
      },
    });

    await expect(storage.put('documents/partial.pdf', failedStream)).rejects.toThrow(
      'stream failed',
    );
    expect(await storage.exists('documents/partial.pdf')).toBe(false);
  });
});
