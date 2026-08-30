import { Readable } from 'node:stream';
import { Types } from 'mongoose';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config/env.js';
import { COLLECTION_NAMES } from '../../src/database/collection-names.js';
import {
  APPLICATION_INDEX_CHECKSUM,
  APPLICATION_INDEXES,
} from '../../src/database/indexes/index-definitions.js';
import { verifyApplicationIndexes } from '../../src/database/indexes/verify-indexes.js';
import {
  getMigrationStatus,
  MigrationError,
  runMigrations,
} from '../../src/database/migrations/migration-runner.js';
import {
  createRepositories,
  RepositoryInputError,
} from '../../src/database/repositories/index.js';
import { seedDatabase, verifySeedData } from '../../src/database/seeds/seed-database.js';
import type { AppServices } from '../../src/infrastructure/create-services.js';
import { registerModels } from '../../src/infrastructure/database/model-registry.js';
import { MongooseDatabaseConnection } from '../../src/infrastructure/database/mongoose-database.js';
import type { EmailMessage } from '../../src/infrastructure/email/email-sender.js';
import type { StoredObject } from '../../src/infrastructure/storage/object-storage.js';
import {
  createDisposableMongoDatabase,
  type DisposableMongoDatabase,
} from '../helpers/disposable-mongodb.js';

function requireDatabase(database: DisposableMongoDatabase | undefined): DisposableMongoDatabase {
  if (database === undefined || database.connection.db === undefined) {
    throw new Error('Disposable MongoDB test context is unavailable.');
  }
  return database;
}

function expectNoSensitiveHash(value: unknown): void {
  expect(value).not.toHaveProperty('passwordHash');
  expect(value).not.toHaveProperty('refreshTokenHash');
  expect(value).not.toHaveProperty('codeHash');
}

describe.sequential('MongoDB persistence', () => {
  let disposable: DisposableMongoDatabase | undefined;

  beforeAll(async () => {
    disposable = await createDisposableMongoDatabase();
  });

  afterAll(async () => {
    if (disposable !== undefined) {
      await disposable.stop();
    }
  });

  it('connects, pings, and reports a real MongoDB connection', async () => {
    const context = requireDatabase(disposable);
    expect(context.database.status).toBe('connected');
    await expect(context.database.ping()).resolves.toEqual({ status: 'up' });
    expect(context.connection.name).toBe(context.databaseName);
  });

  it('applies migrations repeatedly and protects migration history and locking', async () => {
    const context = requireDatabase(disposable);
    const db = context.connection.db!;

    const first = await runMigrations(db);
    const second = await runMigrations(db);
    expect(first).toEqual({ appliedVersions: [1], pendingCount: 0 });
    expect(second).toEqual({ appliedVersions: [], pendingCount: 0 });

    const status = await getMigrationStatus(db);
    expect(status.applied).toHaveLength(1);
    expect(status.pending).toHaveLength(0);

    const migrationRecords = db.collection<{ _id: number; checksum: string }>(
      COLLECTION_NAMES.migrations,
    );
    const migrationLocks = db.collection<{
      _id: string;
      ownerId: string;
      expiresAt: Date;
    }>(COLLECTION_NAMES.migrationLock);
    await migrationRecords
      .updateOne({ _id: 1 }, { $set: { checksum: 'tampered' } });
    await expect(getMigrationStatus(db)).rejects.toThrow(/has changed/);
    await migrationRecords
      .updateOne({ _id: 1 }, { $set: { checksum: APPLICATION_INDEX_CHECKSUM } });

    await migrationRecords.deleteOne({ _id: 1 });
    await migrationLocks.insertOne({
      _id: 'database-migrations',
      ownerId: 'another-runner',
      expiresAt: new Date(Date.now() + 60_000),
    });
    await expect(runMigrations(db)).rejects.toBeInstanceOf(MigrationError);
    await migrationLocks.deleteOne({ _id: 'database-migrations' });
    await expect(runMigrations(db)).resolves.toEqual({ appliedVersions: [1], pendingCount: 0 });
  });

  it('creates every declared index with the required options', async () => {
    const context = requireDatabase(disposable);
    const result = await verifyApplicationIndexes(context.connection.db!);

    expect(result.ok).toBe(true);
    expect(result.expectedCount).toBe(17);
    expect(result.verifiedCount).toBe(APPLICATION_INDEXES.length);
    expect(result.missing).toEqual([]);
    expect(result.mismatched).toEqual([]);
  });

  it('seeds categories and the report template without duplicates or overwrites', async () => {
    const context = requireDatabase(disposable);
    const first = await seedDatabase(context.connection);
    const second = await seedDatabase(context.connection);
    const verification = await verifySeedData(context.connection);

    expect(first.insertedCategories).toBe(6);
    expect(first.insertedReportTemplates).toBe(1);
    expect(second.insertedCategories).toBe(0);
    expect(second.insertedReportTemplates).toBe(0);
    expect(verification).toMatchObject({
      categoryCount: 6,
      reportTemplateCount: 1,
      issues: [],
      ok: true,
    });
  });

  it('performs scoped CRUD across all seven repositories with safe outputs', async () => {
    const context = requireDatabase(disposable);
    const repositories = createRepositories(context.connection);

    const user = await repositories.users.create({
      email: 'student@example.edu',
      passwordHash: 'password-hash-not-for-responses',
      firstName: 'Grad',
      lastName: 'Port',
      program: 'BS Information Technology',
      yearLevel: '4',
      school: 'Example College',
      status: 'active',
    });
    const otherUser = await repositories.users.create({
      email: 'other@example.edu',
      passwordHash: 'other-password-hash',
      firstName: 'Other',
      lastName: 'Student',
      program: '',
      yearLevel: '',
      school: '',
      status: 'active',
    });
    expectNoSensitiveHash(user);
    expectNoSensitiveHash(await repositories.users.findById(user._id));
    expectNoSensitiveHash(await repositories.users.findByEmail('STUDENT@EXAMPLE.EDU'));
    for (const listed of await repositories.users.list()) {
      expectNoSensitiveHash(listed);
    }
    const updatedUser = await repositories.users.updateById(user._id, {
      passwordHash: 'updated-password-hash',
      yearLevel: 'Graduate',
    });
    expect(updatedUser?.yearLevel).toBe('Graduate');
    expectNoSensitiveHash(updatedUser);
    await expect(
      repositories.users.create({
        email: 'student@example.edu',
        passwordHash: 'duplicate',
        firstName: 'Duplicate',
        lastName: 'Student',
        program: '',
        yearLevel: '',
        school: '',
        status: 'active',
      }),
    ).rejects.toMatchObject({ code: 11000 });

    const session = await repositories.sessions.create({
      userId: user._id,
      familyId: 'family-1',
      refreshTokenHash: 'refresh-token-hash',
      expiresAt: new Date(Date.now() + 3_600_000),
    });
    expectNoSensitiveHash(session);
    expect(
      await repositories.sessions.findByIdForUser(otherUser._id, session._id),
    ).toBeNull();
    expectNoSensitiveHash(
      await repositories.sessions.findByIdForUser(user._id, session._id),
    );
    for (const listed of await repositories.sessions.listForUser(user._id)) {
      expectNoSensitiveHash(listed);
    }
    expectNoSensitiveHash(
      await repositories.sessions.updateByIdForUser(user._id, session._id, {
        refreshTokenHash: 'updated-refresh-token-hash',
        lastUsedAt: new Date(),
      }),
    );

    const oneTimeCode = await repositories.oneTimeCodes.create({
      userId: user._id,
      type: 'passwordReset',
      targetEmail: user.email,
      codeHash: 'one-time-code-hash',
      attempts: 0,
      expiresAt: new Date(Date.now() + 900_000),
    });
    expectNoSensitiveHash(oneTimeCode);
    expect(
      await repositories.oneTimeCodes.findByIdForUser(otherUser._id, oneTimeCode._id),
    ).toBeNull();
    expectNoSensitiveHash(
      await repositories.oneTimeCodes.findByIdForUser(user._id, oneTimeCode._id),
    );
    for (const listed of await repositories.oneTimeCodes.listForUser(user._id)) {
      expectNoSensitiveHash(listed);
    }
    expectNoSensitiveHash(
      await repositories.oneTimeCodes.updateByIdForUser(user._id, oneTimeCode._id, {
        codeHash: 'updated-code-hash',
        attempts: 1,
      }),
    );

    const category = await repositories.documentCategories.create({
      key: 'integration-category',
      name: 'Integration Category',
      sortOrder: 999,
      active: true,
      folders: [{ key: 'records', name: 'Records', sortOrder: 10, active: true }],
    });
    expect((await repositories.documentCategories.findByKey(category.key))?._id).toEqual(
      category._id,
    );
    expect(
      (await repositories.documentCategories.updateById(category._id, { active: false }))?.active,
    ).toBe(false);

    const template = await repositories.reportTemplates.create({
      key: 'integration-report',
      version: 1,
      title: 'Integration Report',
      prompt: 'Choose an answer.',
      questions: [
        {
          key: 'integration-question',
          text: 'Integration question?',
          sortOrder: 10,
          options: ['very_often', 'often', 'sometimes', 'never'],
        },
      ],
      active: true,
    });
    expect(
      (await repositories.reportTemplates.findByKeyVersion(template.key, template.version))?._id,
    ).toEqual(template._id);
    expect(
      (await repositories.reportTemplates.updateById(template._id, { title: 'Updated Report' }))
        ?.title,
    ).toBe('Updated Report');

    const documentInput = {
      ownerId: user._id,
      categoryKey: 'certificates',
      folderKey: 'seminars',
      title: 'Integration Certificate',
      documentDate: new Date('2026-01-01T00:00:00.000Z'),
      description: 'Metadata only.',
      originalFileName: 'certificate.pdf',
      objectKey: `students/${user._id.toString()}/documents/certificate.pdf`,
      mimeType: 'application/pdf',
      fileKind: 'pdf' as const,
      extension: 'pdf',
      sizeBytes: 1024,
      sha256: 'a'.repeat(64),
    };
    for (const forbidden of [
      { fileBytes: Buffer.from('file') },
      { base64Data: 'ZmFrZS1maWxl' },
      { content: 'embedded file' },
      { gridFsId: new Types.ObjectId() },
      { description: 'data:application/pdf;base64,ZmFrZQ==' },
    ]) {
      await expect(
        repositories.documents.create({ ...documentInput, ...forbidden } as never),
      ).rejects.toBeInstanceOf(RepositoryInputError);
    }

    const document = await repositories.documents.create(documentInput);
    expect(
      await repositories.documents.findByIdForOwner(otherUser._id, document._id),
    ).toBeNull();
    expect(
      (await repositories.documents.updateByIdForOwner(user._id, document._id, {
        title: 'Updated Certificate',
      }))?.title,
    ).toBe('Updated Certificate');
    expect(await repositories.documents.listForOwner(user._id)).toHaveLength(1);

    const rawDocument = await registerModels(context.connection).Document.findById(document._id)
      .lean()
      .exec();
    expect(rawDocument).toMatchObject({ objectKey: documentInput.objectKey, sizeBytes: 1024 });
    expect(rawDocument).not.toHaveProperty('fileBytes');
    expect(rawDocument).not.toHaveProperty('base64Data');
    expect(rawDocument).not.toHaveProperty('content');
    expect(rawDocument).not.toHaveProperty('gridFsId');

    const collegeReport = await repositories.collegeReports.create({
      ownerId: user._id,
      templateId: template._id,
      academicYear: '2025-2026',
      answers: [{ questionKey: 'integration-question', value: 'often' }],
      status: 'draft',
    });
    expect(
      await repositories.collegeReports.findByIdForOwner(otherUser._id, collegeReport._id),
    ).toBeNull();
    expect(
      (await repositories.collegeReports.updateByIdForOwner(user._id, collegeReport._id, {
        status: 'submitted',
        submittedAt: new Date(),
      }))?.status,
    ).toBe('submitted');
    expect(await repositories.collegeReports.listForOwner(user._id)).toHaveLength(1);

    expect(await repositories.sessions.deleteByIdForUser(user._id, session._id)).toBe(true);
    expect(
      await repositories.oneTimeCodes.deleteByIdForUser(user._id, oneTimeCode._id),
    ).toBe(true);
    expect(await repositories.documents.deleteByIdForOwner(user._id, document._id)).toBe(true);
    expect(
      await repositories.collegeReports.deleteByIdForOwner(user._id, collegeReport._id),
    ).toBe(true);
    expect(await repositories.documentCategories.deleteById(category._id)).toBe(true);
    expect(await repositories.reportTemplates.deleteById(template._id)).toBe(true);
    expect(await repositories.users.deleteById(user._id)).toBe(true);
    expect(await repositories.users.deleteById(otherUser._id)).toBe(true);

    const collections = await context.connection.db!.listCollections().toArray();
    expect(collections.some(({ name }) => name.endsWith('.files') || name.endsWith('.chunks'))).toBe(
      false,
    );
  });

  it('disconnects through the Fastify close hook without leaking connection state', async () => {
    const context = requireDatabase(disposable);
    const secondary = new MongooseDatabaseConnection({
      uri: context.uri,
      databaseName: context.databaseName,
      serverSelectionTimeoutMs: 30_000,
      connectTimeoutMs: 30_000,
      maxPoolSize: 2,
    });
    await secondary.connect();
    await secondary.connect();

    const services: AppServices = {
      database: secondary,
      storage: {
        async put(key: string, _contents: Readable): Promise<StoredObject> {
          return { key, sizeBytes: 0 };
        },
        async get(): Promise<Readable> {
          return Readable.from([]);
        },
        async delete(): Promise<void> {},
        async exists(): Promise<boolean> {
          return false;
        },
        async healthCheck() {
          return { status: 'local' as const };
        },
      },
      email: {
        async send(_message: EmailMessage) {
          return { messageId: 'integration-message' };
        },
        async healthCheck() {
          return { status: 'console' as const };
        },
      },
    };
    const app = await buildApp({
      config: loadConfig({ NODE_ENV: 'test', LOG_LEVEL: 'silent' }),
      services,
      connectDatabase: false,
    });

    await app.close();
    expect(secondary.status).toBe('disconnected');
    await secondary.disconnect();
    expect(secondary.status).toBe('disconnected');
  });
});
