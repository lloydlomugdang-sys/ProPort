export type SafeDatabaseErrorCode =
  | 'DATABASE_AUTHENTICATION_FAILED'
  | 'DATABASE_DNS_FAILED'
  | 'DATABASE_TLS_FAILED'
  | 'DATABASE_TIMEOUT'
  | 'DATABASE_UNAVAILABLE';

export class SafeDatabaseError extends Error {
  override readonly name = 'SafeDatabaseError';

  constructor(readonly code: SafeDatabaseErrorCode, message: string) {
    super(message);
  }
}

export function toSafeDatabaseError(error: unknown): SafeDatabaseError {
  const source = error instanceof Error ? `${error.name} ${error.message}`.toLowerCase() : '';

  if (source.includes('authentication') || source.includes('bad auth') || source.includes('code 18')) {
    return new SafeDatabaseError(
      'DATABASE_AUTHENTICATION_FAILED',
      'MongoDB authentication failed.',
    );
  }
  if (source.includes('enotfound') || source.includes('querysrv') || source.includes('dns')) {
    return new SafeDatabaseError('DATABASE_DNS_FAILED', 'MongoDB DNS resolution failed.');
  }
  if (source.includes('tls') || source.includes('ssl') || source.includes('certificate')) {
    return new SafeDatabaseError('DATABASE_TLS_FAILED', 'MongoDB TLS negotiation failed.');
  }
  if (source.includes('timeout') || source.includes('timed out') || source.includes('server selection')) {
    return new SafeDatabaseError('DATABASE_TIMEOUT', 'MongoDB connection timed out.');
  }

  return new SafeDatabaseError('DATABASE_UNAVAILABLE', 'MongoDB is unavailable.');
}
