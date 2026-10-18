import { describe, expect, it } from 'vitest';
import { requireTorReflection, validateScholasticDetails } from '../../src/modules/documents/scholastic-details.js';

describe('scholastic evidence metadata', () => {
  it.each([undefined, '', '  '])('requires text or explicit included reflection (%s)', (reflection) => {
    expect(() => requireTorReflection('scholastic-record', 'unofficial-tor-with-reflections', reflection)).toThrow('Enter a TOR reflection');
  });
  it('accepts student text without an included-reflection assertion', () => {
    expect(() => requireTorReflection('scholastic-record', 'unofficial-tor-with-reflections', 'My reflection')).not.toThrow();
  });
  it('accepts an explicit included reflection and preserves study period', () => {
    const input = { studyYear: 1, semester: '2nd Semester', reflectionIncluded: true };
    const details = validateScholasticDetails(input);
    expect(details).toEqual(input);
    expect(() => requireTorReflection('scholastic-record', 'unofficial-tor-with-reflections', undefined, details)).not.toThrow();
  });
  it('does not invent a period or reflection for other categories', () => {
    expect(validateScholasticDetails(undefined)).toBeUndefined();
    expect(() => requireTorReflection('certificates', 'trainings')).not.toThrow();
  });
  it.each([{ studyYear: 0 }, { studyYear: 1.5 }, { studyYear: 21 }, { semester: 'invented' }, { ownerId: 'another' }, { reflectionIncluded: 'true' }])('rejects invalid or unsupported coverage %j', (patch) => {
    expect(() => validateScholasticDetails({ reflectionIncluded: false, ...patch })).toThrow();
  });
});
