import { resolve } from 'node:path';
import type { FastifyBaseLogger } from 'fastify';
import type { AppConfig } from '../config/env.types.js';
import type { DatabaseConnection } from './database/database-connection.js';
import { MockDatabaseConnection } from './database/mock-database.js';
import { MongooseDatabaseConnection } from './database/mongoose-database.js';
import { ConsoleEmailSender } from './email/console-email-sender.js';
import type { EmailSender } from './email/email-sender.js';
import { LocalObjectStorage } from './storage/local-object-storage.js';
import type { ObjectStorage } from './storage/object-storage.js';

export interface AppServices {
  readonly database: DatabaseConnection;
  readonly storage: ObjectStorage;
  readonly email: EmailSender;
}

export function createServices(config: AppConfig, logger: FastifyBaseLogger): AppServices {
  const database = createDatabase(config);
  const storage = new LocalObjectStorage(resolve(process.cwd(), config.localStoragePath));
  const email = new ConsoleEmailSender(logger);
  return { database, storage, email };
}

function createDatabase(config: AppConfig): DatabaseConnection {
  if (config.databaseDriver === 'mock') {
    return new MockDatabaseConnection();
  }

  if (config.mongodbUri === undefined) {
    throw new Error('Validated MongoDB configuration did not provide a URI.');
  }

  return new MongooseDatabaseConnection({
    uri: config.mongodbUri,
    databaseName: config.mongodbDbName,
    serverSelectionTimeoutMs: config.mongodbServerSelectionTimeoutMs,
    connectTimeoutMs: config.mongodbConnectTimeoutMs,
    maxPoolSize: config.mongodbMaxPoolSize,
  });
}
