import { constants as fsConstants, createReadStream, createWriteStream } from 'node:fs';
import { access, mkdir, rm, stat } from 'node:fs/promises';
import { dirname, isAbsolute, resolve, sep } from 'node:path';
import { pipeline } from 'node:stream/promises';
import type { Readable } from 'node:stream';
import type { ServiceHealth } from '../../common/types/service-health.js';
import type { ObjectStorage, StoredObject } from './object-storage.js';

export class LocalObjectStorage implements ObjectStorage {
  private readonly root: string;

  constructor(rootPath: string) {
    this.root = resolve(rootPath);
  }

  async put(key: string, contents: Readable): Promise<StoredObject> {
    const target = this.resolveKey(key);
    await mkdir(dirname(target), { recursive: true });
    try {
      await pipeline(contents, createWriteStream(target, { flags: 'wx' }));
    } catch (error) {
      await rm(target, { force: true });
      throw error;
    }
    const metadata = await stat(target);
    return { key, sizeBytes: metadata.size };
  }

  async get(key: string): Promise<Readable> {
    const target = this.resolveKey(key);
    await access(target, fsConstants.R_OK);
    return createReadStream(target);
  }

  async delete(key: string): Promise<void> {
    await rm(this.resolveKey(key), { force: true });
  }

  async exists(key: string): Promise<boolean> {
    try {
      await access(this.resolveKey(key), fsConstants.F_OK);
      return true;
    } catch {
      return false;
    }
  }

  async healthCheck(): Promise<ServiceHealth> {
    try {
      await mkdir(this.root, { recursive: true });
      await access(this.root, fsConstants.R_OK | fsConstants.W_OK);
      return { status: 'local', detail: 'Local development storage is available.' };
    } catch {
      return { status: 'down', detail: 'Local development storage is unavailable.' };
    }
  }

  private resolveKey(key: string): string {
    const normalized = key.replaceAll('\\', '/');
    const segments = normalized.split('/');
    if (
      normalized.length === 0 ||
      isAbsolute(normalized) ||
      segments.some((segment) => segment.length === 0 || segment === '.' || segment === '..')
    ) {
      throw new Error('Invalid storage key.');
    }

    const target = resolve(this.root, ...segments);
    if (!target.startsWith(`${this.root}${sep}`)) {
      throw new Error('Storage key escapes the configured root.');
    }
    return target;
  }
}
