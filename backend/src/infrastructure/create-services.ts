import { resolve } from 'node:path';
import type { FastifyBaseLogger } from 'fastify';
import type { AppConfig } from '../config/env.types.js';
import { GeminiMetadataProvider } from './ai/gemini-metadata-provider.js';
import { AiMetadataService } from '../modules/documents/ai-metadata.service.js';
import type { DatabaseConnection } from './database/database-connection.js';
import { MockDatabaseConnection } from './database/mock-database.js';
import { MongooseDatabaseConnection } from './database/mongoose-database.js';
import { BrevoEmailSender } from './email/brevo-email-sender.js';
import { ConsoleEmailSender } from './email/console-email-sender.js';
import type { EmailSender } from './email/email-sender.js';
import { SmtpEmailSender } from './email/smtp-email-sender.js';
import {
  LocalOcrEngine,
  OCR_PROCESSING_TIMEOUT_MS,
} from './ocr/local-ocr-engine.js';
import type { OcrEngine } from './ocr/ocr-engine.js';
import { LocalObjectStorage } from './storage/local-object-storage.js';
import type { ObjectStorage } from './storage/object-storage.js';
import { R2ObjectStorage } from './storage/r2-object-storage.js';

export interface AppServices {
  readonly database: DatabaseConnection;
  readonly storage: ObjectStorage;
  readonly email: EmailSender;
  readonly ocr: OcrEngine;
  readonly metadata?: AiMetadataService;
}

export function createServices(config: AppConfig, logger: FastifyBaseLogger): AppServices {
  const database = createDatabase(config);
  const storage = createStorage(config);
  const email = createEmail(config, logger);
  const ocr = new LocalOcrEngine(
    OCR_PROCESSING_TIMEOUT_MS,
    config.ocrMaxConcurrentJobs,
  );
  const metadata = new AiMetadataService(config.gemini === undefined ? undefined : new GeminiMetadataProvider(config.gemini));
  return { database, storage, email, ocr, metadata };
}

function createStorage(config: AppConfig): ObjectStorage {
  if (config.storageDriver === 'local') {
    return new LocalObjectStorage(resolve(process.cwd(), config.localStoragePath));
  }
  if (config.r2 === undefined) {
    throw new Error('Validated R2 configuration was not provided.');
  }
  return new R2ObjectStorage(config.r2);
}

function createEmail(config: AppConfig, logger: FastifyBaseLogger): EmailSender {
  if (config.emailDriver === 'console') {
    return new ConsoleEmailSender(logger, config.consoleEmailPreview);
  }
  if (config.emailDriver === 'smtp') {
    if (config.smtp === undefined) {
      throw new Error('Validated SMTP configuration was not provided.');
    }
    return new SmtpEmailSender(config.smtp);
  }
  if (config.brevo === undefined) {
    throw new Error('Validated Brevo configuration was not provided.');
  }
  return new BrevoEmailSender(config.brevo);
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
