import { describe, expect, it } from 'vitest';
import { ConfigurationError, loadConfig } from '../../src/config/env.js';

const ATLAS_TEST_URI = [
  'mongodb+srv://',
  'gradport-user',
  ':',
  'test-placeholder',
  '@gradport-dev.example.mongodb.net/',
].join('');

describe('loadConfig', () => {
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

  it('accepts an explicit Atlas development target', () => {
    const config = loadConfig({
      NODE_ENV: 'development',
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
