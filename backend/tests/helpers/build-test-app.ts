import { Readable } from 'node:stream';
import { buildApp } from '../../src/app.js';
import type { ServiceHealth } from '../../src/common/types/service-health.js';
import { loadConfig } from '../../src/config/env.js';
import type { AppServices } from '../../src/infrastructure/create-services.js';
import type {
  DatabaseConnection,
  DatabaseStatus,
} from '../../src/infrastructure/database/database-connection.js';
import type {
  EmailMessage,
  EmailSendResult,
  EmailSender,
} from '../../src/infrastructure/email/email-sender.js';
import type {
  ObjectStorage,
  StoredObject,
} from '../../src/infrastructure/storage/object-storage.js';

class TestDatabase implements DatabaseConnection {
  status: DatabaseStatus = 'connected';

  constructor(private readonly health: ServiceHealth) {}

  async connect(): Promise<void> {
    this.status = 'connected';
  }

  async disconnect(): Promise<void> {
    this.status = 'disconnected';
  }

  async ping(): Promise<ServiceHealth> {
    return this.health;
  }
}

class TestStorage implements ObjectStorage {
  constructor(private readonly health: ServiceHealth) {}

  async put(key: string, _contents: Readable): Promise<StoredObject> {
    return { key, sizeBytes: 0 };
  }

  async get(_key: string): Promise<Readable> {
    return Readable.from([]);
  }

  async delete(_key: string): Promise<void> {}

  async exists(_key: string): Promise<boolean> {
    return false;
  }

  async healthCheck(): Promise<ServiceHealth> {
    return this.health;
  }
}

class TestEmail implements EmailSender {
  constructor(private readonly health: ServiceHealth) {}

  async send(_message: EmailMessage): Promise<EmailSendResult> {
    return { messageId: 'test-message' };
  }

  async healthCheck(): Promise<ServiceHealth> {
    return this.health;
  }
}

export interface TestHealthOverrides {
  readonly database?: ServiceHealth;
  readonly storage?: ServiceHealth;
  readonly email?: ServiceHealth;
}

export function createTestServices(overrides: TestHealthOverrides = {}): AppServices {
  return {
    database: new TestDatabase(overrides.database ?? { status: 'mock' }),
    storage: new TestStorage(overrides.storage ?? { status: 'local' }),
    email: new TestEmail(overrides.email ?? { status: 'console' }),
  };
}

export async function buildTestApp(overrides: TestHealthOverrides = {}) {
  return buildApp({
    config: loadConfig({ NODE_ENV: 'test', LOG_LEVEL: 'silent' }),
    services: createTestServices(overrides),
  });
}
