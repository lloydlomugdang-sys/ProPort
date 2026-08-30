import { describe, expect, it } from 'vitest';
import { ConfigurationError, loadConfig } from '../../src/config/env.js';

describe('loadConfig', () => {
  it('uses safe local defaults', () => {
    const config = loadConfig({ NODE_ENV: 'test' });

    expect(config).toMatchObject({
      nodeEnv: 'test',
      host: '127.0.0.1',
      port: 3000,
      databaseDriver: 'mock',
      mongodbDbName: 'gradport',
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

  it.each([
    ['PORT', '0'],
    ['PORT', 'not-a-number'],
    ['READY_CHECK_TIMEOUT_MS', '99'],
    ['READY_CHECK_TIMEOUT_MS', '30001'],
  ])('rejects malformed numeric value %s=%s', (name, value) => {
    expect(() => loadConfig({ NODE_ENV: 'test', [name]: value })).toThrow(ConfigurationError);
  });

  it.each([
    ['DATABASE_DRIVER', 'postgres'],
    ['STORAGE_DRIVER', 's3'],
    ['EMAIL_DRIVER', 'resend'],
    ['LOG_LEVEL', 'verbose'],
  ])('rejects unsupported driver or enum %s=%s', (name, value) => {
    expect(() => loadConfig({ NODE_ENV: 'test', [name]: value })).toThrow(ConfigurationError);
  });
});
