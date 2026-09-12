import type {
  AppConfig,
  BrevoConfig,
  DatabaseAccessMode,
  DatabaseConfig,
  DatabaseDriver,
  DatabaseEnvironment,
  EmailDriver,
  LogLevel,
  NodeEnvironment,
  R2Config,
  SmtpConfig,
  StorageDriver,
} from './env.types.js';
import { isIP } from 'node:net';

type Environment = Readonly<Record<string, string | undefined>>;

const NODE_ENVIRONMENTS = ['development', 'test', 'production'] as const;
const LOG_LEVELS = ['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'] as const;
const DATABASE_DRIVERS = ['mock', 'mongodb'] as const;
const DATABASE_ENVIRONMENTS = ['development', 'test'] as const;
const DATABASE_ACCESS_MODES = ['runtime', 'maintenance'] as const;
const STORAGE_DRIVERS = ['local', 'r2'] as const;
const EMAIL_DRIVERS = ['console', 'smtp', 'brevo'] as const;
const TEST_JWT_SECRET = 'gradport-test-jwt-secret-not-for-production';
const TEST_CODE_PEPPER = 'gradport-test-code-pepper-not-for-production';

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

function parseBoolean(value: string, name: string, issues: string[]): boolean {
  if (value === 'true') {
    return true;
  }
  if (value === 'false') {
    return false;
  }
  issues.push(`${name} must be true or false`);
  return false;
}

function requiredSmtpValue(
  value: string | undefined,
  name: string,
  issues: string[],
  options: { readonly preserveWhitespace?: boolean } = {},
): string {
  const trimmed = value?.trim();
  if (trimmed === undefined || trimmed.length === 0) {
    issues.push(`${name} is required when EMAIL_DRIVER=smtp`);
    return '';
  }
  return options.preserveWhitespace ? value! : trimmed;
}

function parseSmtpConfig(environment: Environment, issues: string[]): SmtpConfig {
  const host = requiredSmtpValue(environment.SMTP_HOST, 'SMTP_HOST', issues);
  const portText = requiredSmtpValue(environment.SMTP_PORT, 'SMTP_PORT', issues);
  const secureText = requiredSmtpValue(environment.SMTP_SECURE, 'SMTP_SECURE', issues);
  const user = requiredSmtpValue(environment.SMTP_USER, 'SMTP_USER', issues);
  const pass = requiredSmtpValue(environment.SMTP_PASS, 'SMTP_PASS', issues, {
    preserveWhitespace: true,
  });
  const from = requiredSmtpValue(environment.EMAIL_FROM, 'EMAIL_FROM', issues);

  return Object.freeze({
    host,
    port: portText.length === 0 ? 1 : parseInteger(portText, 'SMTP_PORT', 1, 65_535, issues),
    secure:
      secureText.length === 0 ? false : parseBoolean(secureText, 'SMTP_SECURE', issues),
    user,
    pass,
    from,
  });
}

function requiredDriverValue(
  value: string | undefined,
  name: string,
  driverName: string,
  issues: string[],
  options: { readonly preserveWhitespace?: boolean } = {},
): string {
  const trimmed = value?.trim();
  if (trimmed === undefined || trimmed.length === 0) {
    issues.push(`${name} is required when ${driverName}`);
    return '';
  }
  return options.preserveWhitespace ? value! : trimmed;
}

function parseR2Config(environment: Environment, issues: string[]): R2Config {
  const endpoint = requiredDriverValue(
    environment.R2_ENDPOINT,
    'R2_ENDPOINT',
    'STORAGE_DRIVER=r2',
    issues,
  );
  const accessKeyId = requiredDriverValue(
    environment.R2_ACCESS_KEY_ID,
    'R2_ACCESS_KEY_ID',
    'STORAGE_DRIVER=r2',
    issues,
  );
  const secretAccessKey = requiredDriverValue(
    environment.R2_SECRET_ACCESS_KEY,
    'R2_SECRET_ACCESS_KEY',
    'STORAGE_DRIVER=r2',
    issues,
    { preserveWhitespace: true },
  );
  const bucket = requiredDriverValue(
    environment.R2_BUCKET,
    'R2_BUCKET',
    'STORAGE_DRIVER=r2',
    issues,
  );
  const region = environment.R2_REGION?.trim() || 'auto';

  if (endpoint.length > 0) {
    const uri = URL.parse(endpoint);
    if (uri === null || uri.protocol !== 'https:' || uri.username || uri.password) {
      issues.push('R2_ENDPOINT must be an HTTPS URL without embedded credentials');
    }
  }

  return Object.freeze({ endpoint, accessKeyId, secretAccessKey, bucket, region });
}

function parseBrevoConfig(environment: Environment, issues: string[]): BrevoConfig {
  const apiKey = requiredDriverValue(
    environment.BREVO_API_KEY,
    'BREVO_API_KEY',
    'EMAIL_DRIVER=brevo',
    issues,
    { preserveWhitespace: true },
  );
  const fromEmail = requiredDriverValue(
    environment.BREVO_FROM_EMAIL,
    'BREVO_FROM_EMAIL',
    'EMAIL_DRIVER=brevo',
    issues,
  );
  const fromName = requiredDriverValue(
    environment.BREVO_FROM_NAME,
    'BREVO_FROM_NAME',
    'EMAIL_DRIVER=brevo',
    issues,
  );
  if (
    fromEmail.length > 0 &&
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(fromEmail)
  ) {
    issues.push('BREVO_FROM_EMAIL must be a valid email address');
  }
  return Object.freeze({ apiKey, fromEmail, fromName });
}

function isIpOrCidr(value: string): boolean {
  const slash = value.lastIndexOf('/');
  if (slash === -1) {
    return isIP(value) !== 0;
  }

  const address = value.slice(0, slash);
  const prefixText = value.slice(slash + 1);
  const family = isIP(address);
  if (family === 0 || !/^\d+$/.test(prefixText)) {
    return false;
  }
  const prefix = Number(prefixText);
  return Number.isSafeInteger(prefix) && prefix >= 0 && prefix <= (family === 4 ? 32 : 128);
}

function parseTrustProxy(
  value: string | undefined,
  issues: string[],
): false | number | string[] {
  const normalized = value?.trim();
  if (!normalized || normalized === 'false') {
    return false;
  }
  if (normalized === 'true' || normalized === '*') {
    issues.push(
      'TRUST_PROXY must name exact trusted hops, IP addresses, or CIDRs; unconditional trust is forbidden',
    );
    return false;
  }
  if (/^\d+$/.test(normalized)) {
    return parseInteger(normalized, 'TRUST_PROXY', 1, 10, issues);
  }

  const entries = normalized.split(',').map((entry) => entry.trim());
  if (entries.length === 0 || entries.some((entry) => !isIpOrCidr(entry))) {
    issues.push('TRUST_PROXY must be a hop count or comma-separated IP addresses/CIDRs');
    return false;
  }
  return entries;
}

function validateSecret(
  value: string | undefined,
  name: string,
  nodeEnv: NodeEnvironment,
  issues: string[],
): string {
  if (value === undefined) {
    if (nodeEnv === 'test') {
      return name === 'AUTH_JWT_SECRET' ? TEST_JWT_SECRET : TEST_CODE_PEPPER;
    }
    issues.push(`${name} is required when starting the API`);
    return '';
  }
  if (Buffer.byteLength(value, 'utf8') < 32) {
    issues.push(`${name} must contain at least 32 bytes`);
  }
  return value;
}

function validateMongoTarget(
  uri: string,
  databaseEnvironment: DatabaseEnvironment,
  databaseName: string,
  issues: string[],
): void {
  let parsed: URL;
  try {
    parsed = new URL(uri);
  } catch {
    issues.push('MONGODB_URI is not a valid MongoDB connection URI');
    return;
  }

  if (databaseEnvironment === 'development') {
    if (databaseName !== 'gradport_dev') {
      issues.push('MONGODB_DB_NAME must be gradport_dev for the development database');
    }
    if (parsed.protocol !== 'mongodb+srv:' || !parsed.hostname.endsWith('.mongodb.net')) {
      issues.push('Development MongoDB must use an Atlas mongodb+srv URI');
    }
    if (parsed.username.length === 0 || parsed.password.length === 0) {
      issues.push('Development MONGODB_URI must contain database-user credentials');
    }
    return;
  }

  if (!databaseName.startsWith('gradport_test_')) {
    issues.push('Test MongoDB database names must start with gradport_test_');
  }
  if (
    parsed.protocol !== 'mongodb:' ||
    (parsed.hostname !== '127.0.0.1' && parsed.hostname !== 'localhost')
  ) {
    issues.push('Test MongoDB must use a loopback mongodb URI');
  }
}

function parseDatabaseConfig(environment: Environment, issues: string[]): DatabaseConfig {
  const nodeEnv = parseEnum<NodeEnvironment>(
    environment.NODE_ENV ?? 'development',
    'NODE_ENV',
    NODE_ENVIRONMENTS,
    issues,
  );
  const databaseDriver = parseEnum<DatabaseDriver>(
    environment.DATABASE_DRIVER ?? 'mock',
    'DATABASE_DRIVER',
    DATABASE_DRIVERS,
    issues,
  );
  const databaseEnvironment = parseEnum<DatabaseEnvironment>(
    environment.DATABASE_ENVIRONMENT ?? (nodeEnv === 'test' ? 'test' : 'development'),
    'DATABASE_ENVIRONMENT',
    DATABASE_ENVIRONMENTS,
    issues,
  );
  const databaseAccessMode = parseEnum<DatabaseAccessMode>(
    environment.DATABASE_ACCESS_MODE ?? 'runtime',
    'DATABASE_ACCESS_MODE',
    DATABASE_ACCESS_MODES,
    issues,
  );
  const mongodbUri = optionalNonEmpty(environment.MONGODB_URI);
  if (databaseDriver === 'mongodb' && mongodbUri === undefined) {
    issues.push('MONGODB_URI is required when DATABASE_DRIVER=mongodb');
  }

  const mongodbDbName =
    environment.MONGODB_DB_NAME?.trim() ||
    (databaseEnvironment === 'test' ? 'gradport_test_local' : 'gradport_dev');
  const mongodbServerSelectionTimeoutMs = parseInteger(
    environment.MONGODB_SERVER_SELECTION_TIMEOUT_MS ?? '10000',
    'MONGODB_SERVER_SELECTION_TIMEOUT_MS',
    100,
    30_000,
    issues,
  );
  const mongodbConnectTimeoutMs = parseInteger(
    environment.MONGODB_CONNECT_TIMEOUT_MS ?? '10000',
    'MONGODB_CONNECT_TIMEOUT_MS',
    100,
    30_000,
    issues,
  );
  const mongodbMaxPoolSize = parseInteger(
    environment.MONGODB_MAX_POOL_SIZE ?? '10',
    'MONGODB_MAX_POOL_SIZE',
    1,
    100,
    issues,
  );

  if (mongodbDbName.length > 38) {
    issues.push('MONGODB_DB_NAME must be 38 characters or fewer');
  }
  if (databaseDriver === 'mongodb' && mongodbUri !== undefined) {
    validateMongoTarget(mongodbUri, databaseEnvironment, mongodbDbName, issues);
  }

  return {
    nodeEnv,
    databaseDriver,
    databaseEnvironment,
    databaseAccessMode,
    ...(mongodbUri === undefined ? {} : { mongodbUri }),
    mongodbDbName,
    mongodbServerSelectionTimeoutMs,
    mongodbConnectTimeoutMs,
    mongodbMaxPoolSize,
  };
}

function assertValidConfiguration(issues: string[]): void {
  if (issues.length > 0) {
    throw new ConfigurationError(issues);
  }
}

export function loadDatabaseConfig(environment: Environment = process.env): DatabaseConfig {
  const issues: string[] = [];
  const config = parseDatabaseConfig(environment, issues);
  assertValidConfiguration(issues);
  return Object.freeze(config);
}

export function loadConfig(environment: Environment = process.env): AppConfig {
  const issues: string[] = [];
  const databaseConfig = parseDatabaseConfig(environment, issues);
  const { nodeEnv } = databaseConfig;
  const logLevel = parseEnum<LogLevel>(
    environment.LOG_LEVEL ?? 'info',
    'LOG_LEVEL',
    LOG_LEVELS,
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
  const consoleEmailPreview = parseBoolean(
    environment.CONSOLE_EMAIL_PREVIEW ?? 'false',
    'CONSOLE_EMAIL_PREVIEW',
    issues,
  );
  const smtp = emailDriver === 'smtp' ? parseSmtpConfig(environment, issues) : undefined;
  const brevo =
    emailDriver === 'brevo' ? parseBrevoConfig(environment, issues) : undefined;
  const r2 = storageDriver === 'r2' ? parseR2Config(environment, issues) : undefined;
  const authJwtSecret = validateSecret(
    optionalNonEmpty(environment.AUTH_JWT_SECRET),
    'AUTH_JWT_SECRET',
    nodeEnv,
    issues,
  );
  const authCodePepper = validateSecret(
    optionalNonEmpty(environment.AUTH_CODE_PEPPER),
    'AUTH_CODE_PEPPER',
    nodeEnv,
    issues,
  );
  const host = environment.HOST?.trim() || (nodeEnv === 'production' ? '0.0.0.0' : '127.0.0.1');
  const localStoragePath = environment.LOCAL_STORAGE_PATH?.trim() || '.local-data/storage';
  const port = parseInteger(environment.PORT ?? '3000', 'PORT', 1, 65_535, issues);
  const readyCheckTimeoutMs = parseInteger(
    environment.READY_CHECK_TIMEOUT_MS ?? '2000',
    'READY_CHECK_TIMEOUT_MS',
    100,
    30_000,
    issues,
  );
  const authAccessTokenTtlSeconds = parseInteger(
    environment.AUTH_ACCESS_TOKEN_TTL_SECONDS ?? '900',
    'AUTH_ACCESS_TOKEN_TTL_SECONDS',
    60,
    86_400,
    issues,
  );
  const authRefreshTokenTtlSeconds = parseInteger(
    environment.AUTH_REFRESH_TOKEN_TTL_SECONDS ?? '2592000',
    'AUTH_REFRESH_TOKEN_TTL_SECONDS',
    3_600,
    31_536_000,
    issues,
  );
  const authCodeTtlSeconds = parseInteger(
    environment.AUTH_CODE_TTL_SECONDS ?? '600',
    'AUTH_CODE_TTL_SECONDS',
    60,
    3_600,
    issues,
  );
  const authResetGrantTtlSeconds = parseInteger(
    environment.AUTH_RESET_GRANT_TTL_SECONDS ?? '600',
    'AUTH_RESET_GRANT_TTL_SECONDS',
    60,
    3_600,
    issues,
  );
  const authCodeResendCooldownSeconds = parseInteger(
    environment.AUTH_CODE_RESEND_COOLDOWN_SECONDS ?? '60',
    'AUTH_CODE_RESEND_COOLDOWN_SECONDS',
    1,
    3_600,
    issues,
  );
  const authCodeMaxAttempts = parseInteger(
    environment.AUTH_CODE_MAX_ATTEMPTS ?? '5',
    'AUTH_CODE_MAX_ATTEMPTS',
    1,
    20,
    issues,
  );
  const ocrMaxConcurrentJobs = parseInteger(
    environment.OCR_MAX_CONCURRENT_JOBS ?? (nodeEnv === 'production' ? '1' : '2'),
    'OCR_MAX_CONCURRENT_JOBS',
    1,
    2,
    issues,
  );
  const documentUploadRateLimitMax = parseInteger(
    environment.DOCUMENT_UPLOAD_RATE_LIMIT_MAX ?? (nodeEnv === 'test' ? '10000' : '10'),
    'DOCUMENT_UPLOAD_RATE_LIMIT_MAX',
    1,
    10_000,
    issues,
  );
  const documentOcrRateLimitMax = parseInteger(
    environment.DOCUMENT_OCR_RATE_LIMIT_MAX ?? (nodeEnv === 'test' ? '10000' : '5'),
    'DOCUMENT_OCR_RATE_LIMIT_MAX',
    1,
    10_000,
    issues,
  );
  const trustProxy = parseTrustProxy(environment.TRUST_PROXY, issues);

  if (nodeEnv === 'production' && consoleEmailPreview) {
    issues.push('CONSOLE_EMAIL_PREVIEW must be false in production');
  }
  if (nodeEnv === 'production' && databaseConfig.databaseDriver !== 'mongodb') {
    issues.push('DATABASE_DRIVER must be mongodb in production');
  }
  if (nodeEnv === 'production' && storageDriver !== 'r2') {
    issues.push('STORAGE_DRIVER must be r2 in production');
  }
  if (nodeEnv === 'production' && emailDriver !== 'brevo') {
    issues.push('EMAIL_DRIVER must be brevo in production');
  }
  if (nodeEnv === 'production' && host !== '0.0.0.0') {
    issues.push('HOST must be 0.0.0.0 in production');
  }

  assertValidConfiguration(issues);

  return Object.freeze({
    ...databaseConfig,
    host,
    port,
    logLevel,
    storageDriver,
    localStoragePath,
    ...(r2 === undefined ? {} : { r2 }),
    emailDriver,
    consoleEmailPreview,
    ...(smtp === undefined ? {} : { smtp }),
    ...(brevo === undefined ? {} : { brevo }),
    authJwtSecret,
    authJwtIssuer: environment.AUTH_JWT_ISSUER?.trim() || 'gradport-api',
    authJwtAudience: environment.AUTH_JWT_AUDIENCE?.trim() || 'gradport-mobile',
    authCodePepper,
    authAccessTokenTtlSeconds,
    authRefreshTokenTtlSeconds,
    authCodeTtlSeconds,
    authResetGrantTtlSeconds,
    authCodeResendCooldownSeconds,
    authCodeMaxAttempts,
    ocrMaxConcurrentJobs,
    documentUploadRateLimitMax,
    documentOcrRateLimitMax,
    trustProxy,
    readyCheckTimeoutMs,
  });
}
