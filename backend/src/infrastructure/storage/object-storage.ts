import type { Readable } from 'node:stream';
import type { ServiceHealth } from '../../common/types/service-health.js';

export interface StoredObject {
  readonly key: string;
  readonly sizeBytes: number;
}

export interface ObjectStorage {
  put(key: string, contents: Readable): Promise<StoredObject>;
  get(key: string): Promise<Readable>;
  delete(key: string): Promise<void>;
  exists(key: string): Promise<boolean>;
  healthCheck(): Promise<ServiceHealth>;
}
