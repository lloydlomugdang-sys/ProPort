import { describe, expect, it } from 'vitest';
import { normalizePortfolioInput, type PortfolioInput } from '../../src/modules/portfolios/portfolio.service.js';
import { PORTFOLIO_TEST_INFO } from '../helpers/portfolio-fixtures.js';

const valid = PORTFOLIO_TEST_INFO as PortfolioInput;
const limits = { fullName: 200, yearAndSection: 100, schedule: 200,
  instructorName: 200, course: 200, courseCode: 100, semesterAndYear: 100 };

describe('seven required portfolio title fields at the service boundary', () => {
  for (const [key, limit] of Object.entries(limits)) {
    for (const value of ['', ' \t\n ', 'x'.repeat(limit + 1)]) {
      it(`rejects ${key} with ${value.length} characters`, () => {
        expect(() => normalizePortfolioInput({ ...valid, [key]: value })).toThrow(
          expect.objectContaining({ statusCode: 400, code: 'VALIDATION_ERROR', fields: { [key]: expect.any(Array) } }),
        );
      });
    }
  }
  it('normalizes without inventing or replacing any student facts', () => {
    expect(normalizePortfolioInput({ ...valid, course: `  ${valid.course}  ` })).toEqual(valid);
  });
});
