import { describe, expect, it } from 'vitest';
import { normalizePersonalName } from '../../src/common/validation/personal-name.js';

describe('personal names', () => {
  it.each(['John Lloyd', 'Dela-Cruz', "O'Connor", 'José', '李明', 'O’Connor'])('accepts %s', (name) => {
    expect(normalizePersonalName(` ${name} `, 'firstName')).toBe(name);
  });
  it.each(['John123', 'Lomugdang9', 'John١', 'Name９'])('rejects numeric name %s', (name) => {
    expect(() => normalizePersonalName(name, 'lastName')).toThrow();
  });
});
