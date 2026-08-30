import type {
  AppConfig,
  DatabaseDriver,
  EmailDriver,
  LogLevel,
  NodeEnvironment,
  StorageDriver,
} from './env.types.js';

type Environment = Readonly<Record<string, string | undefined>>;

const NODE_ENVIRONMENTS = ['development', 'test'] as const;
const LOG_LEVELS = ['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'] as const;
const DATABASE_DRIVERS = ['mock', 'mongodb'] as const;
const STORAGE_DRIVERS = ['local'] as const;
const EMAIL_DRIVERS = ['console'] as const;

export class ConfigurationError extends Error {
  override readonly name = 'ConfigurationError';

  constructor(readonly issues: readonly string[]) {
    super(`Invalid environment configuration: ${issues.join('; ')}`);
  }
}

function parseEnum<T extends string>(
  value: string,
  name: string,
  allowed: readonly T[],
  issues: string[],
): T {
  if (allowed.includes(value as T)) {
    return value as T;
  }

  issues.push(`${name} must be one of: ${allowed.join(', ')}`);
  return allowed[0]!;
}

function parseInteger(
  value: string,
  name: string,
  minimum: number,
  maximum: number,
  issues: string[],
): number {
  if (!/^\d+$/.test(value)) {
    issues.push(`${name} must be an integer between ${minimum} and ${maximum}`);
    return minimum;
  }

  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < minimum || parsed > maximum) {
    issues.push(`${name} must be an integer between ${minimum} and ${maximum}`);
    return minimum;
  }

  return parsed;
}

function optionalNonEmpty(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

export function loadConfig(environment: Environment = process.env): AppConfig {
  const issues: string[] = [];

  const nodeEnv = parseEnum<NodeEnvironment>(
    environment.NODE_ENV ?? 'development',
    'NODE_ENV',
    NODE_ENVIRONMENTS,
    issues,
  );
  const logLevel = parseEnum<LogLevel>(
    environment.LOG_LEVEL ?? 'info',
    'LOG_LEVEL',
    LOG_LEVELS,
    issues,
  );
  const databaseDriver = parseEnum<DatabaseDriver>(
    environment.DATABASE_DRIVER ?? 'mock',
    'DATABASE_DRIVER',
    DATABASE_DRIVERS,
    issues,
  );
  const storageDriver = parseEnum<StorageDriver>(
    environment.STORAGE_DRIVER ?? 'local',
    'STORAGE_DRIVER',
    STORAGE_DRIVERS,
    issues,
  );
  const emailDriver = parseEnum<EmailDriver>(
    environment.EMAIL_DRIVER ?? 'console',
    'EMAIL_DRIVER',
    EMAIL_DRIVERS,
    issues,
  );
  const mongodbUri = optionalNonEmpty(environment.MONGODB_URI);

  if (databaseDriver === 'mongodb' && mongodbUri === undefined) {
    issues.push('MONGODB_URI is required when DATABASE_DRIVER=mongodb');
  }

  const host = environment.HOST?.trim() || '127.0.0.1';
  const mongodbDbName = environment.MONGODB_DB_NAME?.trim() || 'gradport';
  const localStoragePath = environment.LOCAL_STORAGE_PATH?.trim() || '.local-data/storage';
  const port = parseInteger(environment.PORT ?? '3000', 'PORT', 1, 65_535, issues);
  const readyCheckTimeoutMs = parseInteger(
    environment.READY_CHECK_TIMEOUT_MS ?? '2000',
    'READY_CHECK_TIMEOUT_MS',
    100,
    30_000,
    issues,
  );

  if (mongodbDbName.length > 64) {
    issues.push('MONGODB_DB_NAME must be 64 characters or fewer');
  }

  if (issues.length > 0) {
    throw new ConfigurationError(issues);
  }

  return Object.freeze({
    nodeEnv,
    host,
    port,
    logLevel,
    databaseDriver,
    ...(mongodbUri === undefined ? {} : { mongodbUri }),
    mongodbDbName,
    storageDriver,
    localStoragePath,
    emailDriver,
    readyCheckTimeoutMs,
  });
}
