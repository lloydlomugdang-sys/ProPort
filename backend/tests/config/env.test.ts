import { describe, expect, it } from 'vitest';
import {
  ConfigurationError,
  loadConfig,
  loadDatabaseConfig,
} from '../../src/config/env.js';

const ATLAS_TEST_URI = [
  'mongodb+srv://',
  'gradport-user',
  ':',
  'test-placeholder',
  '@gradport-dev.example.mongodb.net/',
].join('');
const DEVELOPMENT_AUTH = {
  AUTH_JWT_SECRET: 'test-development-jwt-secret-32-bytes-minimum',
  AUTH_CODE_PEPPER: 'test-development-code-pepper-32-bytes-minimum',
} as const;
const SMTP_TEST_CONFIG = {
  EMAIL_DRIVER: 'smtp',
  SMTP_HOST: 'smtp.example.test',
  SMTP_PORT: '587',
  SMTP_SECURE: 'false',
  SMTP_USER: 'smtp-user@example.test',
  SMTP_PASS: ' test-only-smtp-password ',
  EMAIL_FROM: 'GradPort <no-reply@example.test>',
} as const;

describe('loadConfig', () => {
  it('requires authentication secrets when starting the development API', () => {
    let thrown: unknown;
    try {
      loadConfig({ NODE_ENV: 'development' });
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeInstanceOf(ConfigurationError);
    expect(String(thrown)).toContain('AUTH_JWT_SECRET is required when starting the API');
    expect(String(thrown)).toContain('AUTH_CODE_PEPPER is required when starting the API');
  });

  it('uses safe local defaults', () => {
    const config = loadConfig({ NODE_ENV: 'test' });

    expect(config).toMatchObject({
      nodeEnv: 'test',
      host: '127.0.0.1',
      port: 3000,
      databaseDriver: 'mock',
      databaseEnvironment: 'test',
      databaseAccessMode: 'runtime',
      mongodbDbName: 'gradport_test_local',
      mongodbServerSelectionTimeoutMs: 10000,
      mongodbConnectTimeoutMs: 10000,
      mongodbMaxPoolSize: 10,
      storageDriver: 'local',
      localStoragePath: '.local-data/storage',
      emailDriver: 'console',
      readyCheckTimeoutMs: 2000,
    });
    expect(config.mongodbUri).toBeUndefined();
  });

  it('requires a MongoDB URI for the mongodb driver', () => {
    expect(() =>
      loadConfig({
        NODE_ENV: 'test',
        DATABASE_DRIVER: 'mongodb',
      }),
    ).toThrowError(/MONGODB_URI is required/);
  });

  it('accepts complete SMTP configuration without normalizing the password', () => {
    const config = loadConfig({ NODE_ENV: 'test', ...SMTP_TEST_CONFIG });

    expect(config).toMatchObject({
      emailDriver: 'smtp',
      smtp: {
        host: 'smtp.example.test',
        port: 587,
        secure: false,
        user: 'smtp-user@example.test',
        pass: ' test-only-smtp-password ',
        from: 'GradPort <no-reply@example.test>',
      },
    });
  });

  it.each(['SMTP_HOST', 'SMTP_PORT', 'SMTP_SECURE', 'SMTP_USER', 'SMTP_PASS', 'EMAIL_FROM'])(
    'requires %s when SMTP delivery is enabled',
    (name) => {
      expect(() =>
        loadConfig({
          NODE_ENV: 'test',
          ...SMTP_TEST_CONFIG,
          [name]: undefined,
        }),
      ).toThrowError(new RegExp(`${name} is required when EMAIL_DRIVER=smtp`));
    },
  );

  it.each([
    ['SMTP_PORT', '0'],
    ['SMTP_PORT', 'not-a-port'],
    ['SMTP_SECURE', 'yes'],
    ['SMTP_PASS', '   '],
  ])('rejects malformed SMTP setting %s=%s without exposing credentials', (name, value) => {
    let thrown: unknown;
    try {
      loadConfig({ NODE_ENV: 'test', ...SMTP_TEST_CONFIG, [name]: value });
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeInstanceOf(ConfigurationError);
    expect(String(thrown)).not.toContain(SMTP_TEST_CONFIG.SMTP_PASS);
    expect(String(thrown)).not.toContain(SMTP_TEST_CONFIG.SMTP_USER);
  });

  it('accepts an explicit Atlas development target', () => {
    const config = loadConfig({
      NODE_ENV: 'development',
      ...DEVELOPMENT_AUTH,
      DATABASE_DRIVER: 'mongodb',
      DATABASE_ENVIRONMENT: 'development',
      DATABASE_ACCESS_MODE: 'runtime',
      MONGODB_URI: ATLAS_TEST_URI,
      MONGODB_DB_NAME: 'gradport_dev',
    });

    expect(config).toMatchObject({
      databaseDriver: 'mongodb',
      databaseEnvironment: 'development',
      databaseAccessMode: 'runtime',
      mongodbDbName: 'gradport_dev',
    });
  });

  it('rejects a non-Atlas development target without exposing credentials', () => {
    let thrown: unknown;
    try {
      loadConfig({
        NODE_ENV: 'development',
        ...DEVELOPMENT_AUTH,
        DATABASE_DRIVER: 'mongodb',
        DATABASE_ENVIRONMENT: 'development',
        MONGODB_URI: ['mongodb://', 'gradport-user', ':', 'do-not-log', '@127.0.0.1:27017'].join(
          '',
        ),
        MONGODB_DB_NAME: 'gradport_dev',
      });
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeInstanceOf(ConfigurationError);
    expect(String(thrown)).not.toContain('do-not-log');
  });

  it.each([
    ['PORT', '0'],
    ['PORT', 'not-a-number'],
    ['READY_CHECK_TIMEOUT_MS', '99'],
    ['READY_CHECK_TIMEOUT_MS', '30001'],
    ['MONGODB_SERVER_SELECTION_TIMEOUT_MS', '99'],
    ['MONGODB_CONNECT_TIMEOUT_MS', '30001'],
    ['MONGODB_MAX_POOL_SIZE', '0'],
  ])('rejects malformed numeric value %s=%s', (name, value) => {
    expect(() => loadConfig({ NODE_ENV: 'test', [name]: value })).toThrow(ConfigurationError);
  });

  it.each([
    ['DATABASE_DRIVER', 'postgres'],
    ['DATABASE_ENVIRONMENT', 'production'],
    ['DATABASE_ACCESS_MODE', 'admin'],
    ['STORAGE_DRIVER', 's3'],
    ['EMAIL_DRIVER', 'resend'],
    ['LOG_LEVEL', 'verbose'],
  ])('rejects unsupported driver or enum %s=%s', (name, value) => {
    expect(() => loadConfig({ NODE_ENV: 'test', [name]: value })).toThrow(ConfigurationError);
  });
});

describe('loadDatabaseConfig', () => {
  it('accepts maintenance configuration without API auth or SMTP settings', () => {
    const config = loadDatabaseConfig({
      NODE_ENV: 'development',
      DATABASE_DRIVER: 'mongodb',
      DATABASE_ENVIRONMENT: 'development',
      DATABASE_ACCESS_MODE: 'maintenance',
      MONGODB_URI: ATLAS_TEST_URI,
      MONGODB_DB_NAME: 'gradport_dev',
      EMAIL_DRIVER: 'smtp',
    });

    expect(config).toMatchObject({
      nodeEnv: 'development',
      databaseDriver: 'mongodb',
      databaseEnvironment: 'development',
      databaseAccessMode: 'maintenance',
      mongodbDbName: 'gradport_dev',
    });
    expect(config).not.toHaveProperty('authJwtSecret');
    expect(config).not.toHaveProperty('authCodePepper');
    expect(config).not.toHaveProperty('smtp');
  });

  it('still requires MongoDB settings needed by database commands', () => {
    expect(() =>
      loadDatabaseConfig({
        NODE_ENV: 'development',
        DATABASE_DRIVER: 'mongodb',
        DATABASE_ENVIRONMENT: 'development',
        DATABASE_ACCESS_MODE: 'maintenance',
        MONGODB_DB_NAME: 'gradport_dev',
      }),
    ).toThrowError(/MONGODB_URI is required when DATABASE_DRIVER=mongodb/);
  });
});
