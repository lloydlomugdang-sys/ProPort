import { describe, expect, it } from 'vitest';
import { toSafeDatabaseError } from '../../src/infrastructure/database/database-error.js';

describe('database error sanitization', () => {
  const sensitiveTestUri = [
    'mongodb+srv://',
    'test-user',
    ':',
    'top-secret',
    '@cluster.mongodb.net',
  ].join('');

  it.each([
    [`authentication failed ${sensitiveTestUri}`, 'DATABASE_AUTHENTICATION_FAILED'],
    ['not authorized to read a database collection', 'DATABASE_AUTHORIZATION_FAILED'],
    ['user is not allowed to execute find', 'DATABASE_AUTHORIZATION_FAILED'],
    ['querySrv ENOTFOUND cluster.mongodb.net', 'DATABASE_DNS_FAILED'],
    ['TLS certificate rejected', 'DATABASE_TLS_FAILED'],
    ['server selection timed out', 'DATABASE_TIMEOUT'],
    [sensitiveTestUri, 'DATABASE_UNAVAILABLE'],
  ])('returns a safe category for %s', (source, expectedCode) => {
    const safe = toSafeDatabaseError(new Error(source));

    expect(safe.code).toBe(expectedCode);
    expect(`${safe.code} ${safe.message}`).not.toContain('top-secret');
    expect(safe).not.toHaveProperty('cause');
  });
});
