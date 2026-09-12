import {
  DeleteObjectCommand,
  GetObjectCommand,
  HeadBucketCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { Readable } from 'node:stream';
import type { ServiceHealth } from '../../common/types/service-health.js';
import type { R2Config } from '../../config/env.types.js';
import type { ObjectStorage, StoredObject } from './object-storage.js';

const MAX_OBJECT_BYTES = 15 * 1024 * 1024;

interface R2ObjectInput {
  readonly bucket: string;
  readonly key: string;
}

interface R2PutInput extends R2ObjectInput {
  readonly body: Buffer;
}

export interface R2StorageTransport {
  putObject(input: R2PutInput): Promise<void>;
  getObject(input: R2ObjectInput): Promise<Readable>;
  deleteObject(input: R2ObjectInput): Promise<void>;
  objectExists(input: R2ObjectInput): Promise<boolean>;
  bucketExists(bucket: string): Promise<void>;
}

function isNotFound(error: unknown): boolean {
  if (typeof error !== 'object' || error === null) return false;
  const candidate = error as {
    readonly name?: unknown;
    readonly $metadata?: { readonly httpStatusCode?: unknown };
  };
  return (
    candidate.name === 'NoSuchKey' ||
    candidate.name === 'NotFound' ||
    candidate.$metadata?.httpStatusCode === 404
  );
}

function createR2StorageTransport(config: R2Config): R2StorageTransport {
  const client = new S3Client({
    endpoint: config.endpoint,
    region: config.region,
    credentials: {
      accessKeyId: config.accessKeyId,
      secretAccessKey: config.secretAccessKey,
    },
  });

  return {
    async putObject(input) {
      await client.send(
        new PutObjectCommand({
          Bucket: input.bucket,
          Key: input.key,
          Body: input.body,
          ContentLength: input.body.length,
        }),
      );
    },
    async getObject(input) {
      const output = await client.send(
        new GetObjectCommand({ Bucket: input.bucket, Key: input.key }),
      );
      const body = output.Body;
      if (body instanceof Readable) return body;
      if (body !== undefined && Symbol.asyncIterator in Object(body)) {
        return Readable.from(body as AsyncIterable<Uint8Array>);
      }
      throw new Error('Cloud object response did not contain a readable body.');
    },
    async deleteObject(input) {
      await client.send(
        new DeleteObjectCommand({ Bucket: input.bucket, Key: input.key }),
      );
    },
    async objectExists(input) {
      try {
        await client.send(
          new HeadObjectCommand({ Bucket: input.bucket, Key: input.key }),
        );
        return true;
      } catch (error) {
        if (isNotFound(error)) return false;
        throw error;
      }
    },
    async bucketExists(bucket) {
      await client.send(new HeadBucketCommand({ Bucket: bucket }));
    },
  };
}

async function readBounded(contents: Readable): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let sizeBytes = 0;
  for await (const chunk of contents) {
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk as Uint8Array);
    sizeBytes += bytes.length;
    if (sizeBytes > MAX_OBJECT_BYTES) {
      throw new Error('Cloud object exceeds the supported size limit.');
    }
    chunks.push(bytes);
  }
  return Buffer.concat(chunks, sizeBytes);
}

function assertSafeKey(key: string): void {
  const segments = key.split('/');
  if (
    key.length === 0 ||
    key.startsWith('/') ||
    key.includes('\\') ||
    segments.some((segment) => segment.length === 0 || segment === '.' || segment === '..')
  ) {
    throw new Error('Invalid storage key.');
  }
}

export class R2ObjectStorage implements ObjectStorage {
  private readonly transport: R2StorageTransport;

  constructor(
    private readonly config: R2Config,
    transport?: R2StorageTransport,
  ) {
    this.transport = transport ?? createR2StorageTransport(config);
  }

  async put(key: string, contents: Readable): Promise<StoredObject> {
    assertSafeKey(key);
    const body = await readBounded(contents);
    await this.transport.putObject({ bucket: this.config.bucket, key, body });
    return { key, sizeBytes: body.length };
  }

  async get(key: string): Promise<Readable> {
    assertSafeKey(key);
    return this.transport.getObject({ bucket: this.config.bucket, key });
  }

  async delete(key: string): Promise<void> {
    assertSafeKey(key);
    await this.transport.deleteObject({ bucket: this.config.bucket, key });
  }

  async exists(key: string): Promise<boolean> {
    assertSafeKey(key);
    return this.transport.objectExists({ bucket: this.config.bucket, key });
  }

  async healthCheck(): Promise<ServiceHealth> {
    try {
      await this.transport.bucketExists(this.config.bucket);
      return { status: 'up', detail: 'Cloud object storage is available.' };
    } catch {
      return { status: 'down', detail: 'Cloud object storage is unavailable.' };
    }
  }
}
