import { describe, expect, it } from 'vitest';
import { loadDatabaseConfig } from '../../src/config/env.js';
import {
  assertDevelopmentDatabaseTarget,
  assertDisposableTestTarget,
  DatabaseTargetError,
} from '../../src/database/safety/database-target-guard.js';

const ATLAS_TEST_URI = [
  'mongodb+srv://',
  'gradport-user',
  ':',
  'test-placeholder',
  '@gradport-dev.example.mongodb.net/',
].join('');
function developmentConfig(accessMode: 'runtime' | 'maintenance' = 'runtime') {
  return loadDatabaseConfig({
    NODE_ENV: 'development',
    DATABASE_DRIVER: 'mongodb',
    DATABASE_ENVIRONMENT: 'development',
    DATABASE_ACCESS_MODE: accessMode,
    MONGODB_URI: ATLAS_TEST_URI,
    MONGODB_DB_NAME: 'gradport_dev',
  });
}

describe('database target guards', () => {
  it('accepts the explicit development database confirmation', () => {
    expect(() =>
      assertDevelopmentDatabaseTarget(developmentConfig(), {
        allowedAccessModes: ['runtime'],
        argv: ['--confirm-database=gradport_dev'],
      }),
    ).not.toThrow();
  });

  it('rejects missing confirmation and the wrong access mode', () => {
    expect(() =>
      assertDevelopmentDatabaseTarget(developmentConfig(), {
        allowedAccessModes: ['runtime'],
        argv: [],
      }),
    ).toThrow(DatabaseTargetError);
    expect(() =>
      assertDevelopmentDatabaseTarget(developmentConfig('runtime'), {
        allowedAccessModes: ['maintenance'],
        argv: ['--confirm-database=gradport_dev'],
      }),
    ).toThrow(/maintenance credentials/);
  });

  it('allows an explicitly read-only command without the confirmation flag', () => {
    expect(() =>
      assertDevelopmentDatabaseTarget(developmentConfig('maintenance'), {
        allowedAccessModes: ['maintenance'],
        requireConfirmation: false,
        argv: [],
      }),
    ).not.toThrow();
  });

  it('still requires confirmation for mutating maintenance commands', () => {
    expect(() =>
      assertDevelopmentDatabaseTarget(developmentConfig('maintenance'), {
        allowedAccessModes: ['maintenance'],
        argv: [],
      }),
    ).toThrow(/confirm-database=gradport_dev/);
  });

  it('allows read-only diagnostics with runtime or maintenance access', () => {
    for (const accessMode of ['runtime', 'maintenance'] as const) {
      expect(() =>
        assertDevelopmentDatabaseTarget(developmentConfig(accessMode), {
          allowedAccessModes: ['runtime', 'maintenance'],
          requireConfirmation: false,
          argv: [],
        }),
      ).not.toThrow();
    }
  });

  it('only accepts disposable loopback test targets', () => {
    expect(() =>
      assertDisposableTestTarget('mongodb://127.0.0.1:27017/gradport_test_safe', 'gradport_test_safe'),
    ).not.toThrow();
    expect(() =>
      assertDisposableTestTarget(
        ['mongodb+srv://', 'test-user', ':', 'test-placeholder', '@prod.example.mongodb.net/'].join(
          '',
        ),
        'gradport_test_unsafe',
      ),
    ).toThrow(DatabaseTargetError);
    expect(() =>
      assertDisposableTestTarget('mongodb://127.0.0.1:27017/production', 'production'),
    ).toThrow(DatabaseTargetError);
  });
});
