import { randomUUID } from 'node:crypto';
import { MongoMemoryReplSet } from 'mongodb-memory-server';
import type { Connection } from 'mongoose';
import { assertDisposableTestTarget } from '../../src/database/safety/database-target-guard.js';
import { MongooseDatabaseConnection } from '../../src/infrastructure/database/mongoose-database.js';

export interface DisposableMongoDatabase {
  readonly databaseName: string;
  readonly uri: string;
  readonly database: MongooseDatabaseConnection;
  readonly connection: Connection;
  stop(): Promise<void>;
}

export async function createDisposableMongoDatabase(): Promise<DisposableMongoDatabase> {
  if (process.env.MONGODB_URI?.trim()) {
    throw new Error('Integration tests refuse to run while an external MONGODB_URI is set.');
  }

  const databaseName = `gradport_test_${randomUUID().replaceAll('-', '')}`;
  const replicaSet = await MongoMemoryReplSet.create({
    binary: { version: '8.0.29' },
    instanceOpts: [{ launchTimeout: 30_000 }],
    replSet: { count: 1, storageEngine: 'wiredTiger' },
  });
  const uri = replicaSet.getUri(databaseName);
  assertDisposableTestTarget(uri, databaseName);

  const database = new MongooseDatabaseConnection({
    uri,
    databaseName,
    serverSelectionTimeoutMs: 30_000,
    connectTimeoutMs: 30_000,
    maxPoolSize: 5,
  });
  await database.connect();
  const connection = database.mongooseConnection;
  if (connection === undefined) {
    await replicaSet.stop();
    throw new Error('Disposable MongoDB connection was not created.');
  }

  return {
    databaseName,
    uri,
    database,
    connection,
    async stop(): Promise<void> {
      assertDisposableTestTarget(uri, databaseName);
      if (connection.db !== undefined) {
        await connection.db.dropDatabase();
      }
      await database.disconnect();
      await replicaSet.stop();
    },
  };
}
