import type { AppConfig, DatabaseAccessMode } from '../../config/env.types.js';

export class DatabaseTargetError extends Error {
  override readonly name = 'DatabaseTargetError';
}

export interface DatabaseTargetGuardOptions {
  readonly requiredAccessMode: DatabaseAccessMode;
  readonly argv?: readonly string[];
}

function confirmedDatabase(argv: readonly string[]): string | undefined {
  const prefix = '--confirm-database=';
  return argv.find((argument) => argument.startsWith(prefix))?.slice(prefix.length);
}

export function assertDevelopmentDatabaseTarget(
  config: AppConfig,
  options: DatabaseTargetGuardOptions,
): void {
  if (config.nodeEnv !== 'development' || config.databaseEnvironment !== 'development') {
    throw new DatabaseTargetError('Database command refused: development mode is required.');
  }
  if (config.databaseDriver !== 'mongodb' || config.mongodbUri === undefined) {
    throw new DatabaseTargetError('Database command refused: MongoDB must be configured explicitly.');
  }
  if (config.databaseAccessMode !== options.requiredAccessMode) {
    throw new DatabaseTargetError(
      `Database command refused: ${options.requiredAccessMode} credentials are required.`,
    );
  }
  if (config.mongodbDbName !== 'gradport_dev') {
    throw new DatabaseTargetError('Database command refused: target must be gradport_dev.');
  }

  const confirmation = confirmedDatabase(options.argv ?? process.argv.slice(2));
  if (confirmation !== config.mongodbDbName) {
    throw new DatabaseTargetError(
      'Database command refused: pass --confirm-database=gradport_dev explicitly.',
    );
  }
}

export function assertDisposableTestTarget(uri: string, databaseName: string): void {
  let parsed: URL;
  try {
    parsed = new URL(uri);
  } catch {
    throw new DatabaseTargetError('Disposable test database URI is invalid.');
  }

  if (
    parsed.protocol !== 'mongodb:' ||
    (parsed.hostname !== '127.0.0.1' && parsed.hostname !== 'localhost')
  ) {
    throw new DatabaseTargetError('Disposable tests require a loopback MongoDB server.');
  }
  if (!databaseName.startsWith('gradport_test_')) {
    throw new DatabaseTargetError('Disposable test database name is unsafe.');
  }
}
