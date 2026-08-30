import type { Db } from 'mongodb';
import type { Connection } from 'mongoose';
import { loadConfig, ConfigurationError } from '../../config/env.js';
import type { AppConfig, DatabaseAccessMode } from '../../config/env.types.js';
import { MongooseDatabaseConnection } from '../../infrastructure/database/mongoose-database.js';
import {
  SafeDatabaseError,
  toSafeDatabaseError,
} from '../../infrastructure/database/database-error.js';
import {
  assertDevelopmentDatabaseTarget,
  DatabaseTargetError,
} from '../safety/database-target-guard.js';

export interface DatabaseCommandContext {
  readonly config: AppConfig;
  readonly connection: Connection;
  readonly db: Db;
}

export interface DatabaseCommandOptions {
  readonly requiredAccessMode: DatabaseAccessMode;
}

export async function executeDatabaseCommand(
  options: DatabaseCommandOptions,
  command: (context: DatabaseCommandContext) => Promise<void>,
): Promise<void> {
  let database: MongooseDatabaseConnection | undefined;

  try {
    const config = loadConfig();
    assertDevelopmentDatabaseTarget(config, {
      requiredAccessMode: options.requiredAccessMode,
    });
    if (config.mongodbUri === undefined) {
      throw new DatabaseTargetError('MongoDB URI is unavailable after configuration validation.');
    }

    database = new MongooseDatabaseConnection({
      uri: config.mongodbUri,
      databaseName: config.mongodbDbName,
      serverSelectionTimeoutMs: config.mongodbServerSelectionTimeoutMs,
      connectTimeoutMs: config.mongodbConnectTimeoutMs,
      maxPoolSize: config.mongodbMaxPoolSize,
    });
    await database.connect();

    const connection = database.mongooseConnection;
    const db = connection?.db;
    if (connection === undefined || db === undefined) {
      throw new SafeDatabaseError('DATABASE_UNAVAILABLE', 'MongoDB connection is unavailable.');
    }
    await command({ config, connection, db });
  } catch (error) {
    if (error instanceof ConfigurationError || error instanceof DatabaseTargetError) {
      process.stderr.write(`${error.message}\n`);
    } else {
      const safeError = error instanceof SafeDatabaseError ? error : toSafeDatabaseError(error);
      process.stderr.write(`${safeError.code}: ${safeError.message}\n`);
    }
    process.exitCode = 1;
  } finally {
    if (database !== undefined) {
      try {
        await database.disconnect();
      } catch {
        process.stderr.write('DATABASE_UNAVAILABLE: MongoDB disconnect failed.\n');
        process.exitCode = 1;
      }
    }
  }
}
