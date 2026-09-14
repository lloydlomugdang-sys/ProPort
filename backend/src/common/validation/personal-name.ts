import { AppError } from '../errors/app-error.js';

export function normalizePersonalName(value: string, field: 'firstName' | 'lastName'): string {
  const name = value.trim().normalize('NFC');
  let message: string | undefined;
  if (/\p{N}/u.test(name)) message = 'Names cannot contain numbers.';
  else if (name.length < 2 || name.length > 100) message = 'must contain 2-100 characters';
  else if (!/^[\p{L}\p{M} '\u2019-]+$/u.test(name) || !/\p{L}/u.test(name)) {
    message = 'Use letters, spaces, hyphens, or apostrophes for names.';
  }
  if (message !== undefined) {
    throw new AppError(400, 'VALIDATION_ERROR', 'The request is invalid.', { [field]: [message] });
  }
  return name;
}
