import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { OFFICIAL_COLLEGE_REPORT as template, OFFICIAL_QUESTIONS } from '../../src/modules/college-report/college-report.template.js';
import { validateOfficialAnswers, type SaveCollegeReport } from '../../src/modules/college-report/college-report.service.js';

describe('official College Report source transcription and validation', () => {
  it('matches the full versioned Flutter contract fixture without wording drift', () => {
    expect(template).toEqual(JSON.parse(readFileSync(new URL('../../../test/fixtures/college_report_template.json', import.meta.url), 'utf8')));
  });
  it('preserves ten sections, all 62 stable positional IDs and distinct source scales', () => {
    expect(template.version).toBe(2);
    expect(template.sections.map((s) => s.questions.length)).toEqual([19, 5, 5, 1, 7, 4, 14, 5, 1, 1]);
    expect(OFFICIAL_QUESTIONS).toHaveLength(62);
    expect(new Set(OFFICIAL_QUESTIONS.map((q) => q.key)).size).toBe(62);
    expect(template.sections.map((s) => s.responseType)).toEqual(['choice', 'choice', 'range', 'rating', 'choice', 'range', 'choice', 'choice', 'text', 'text']);
    expect(template.sections.map((s) => s.options.map((o) => o.label))).toEqual([
      ['Very Often', 'Often', 'Sometimes', 'Never'],
      ['Very Often', 'Often', 'Sometimes', 'Once'],
      ['None', '1 – 4', '5 – 10', '11–20', '> 20'],
      ['7', '6', '5', '4', '3', '2', '1'],
      ['Yes', 'No', 'Undecided'],
      ['0', '1 – 5', '6 – 10', '11 – 15', '16 – 20', '21 – 25', '26 – 30', '>30'],
      ['Very much', 'Quite a bit', 'Some', 'Very little'],
      ['Very much', 'Quite a bit', 'Some', 'Very little'], [], [],
    ]);
    for (const [i, section] of template.sections.entries()) {
      expect(section.label).toBe(`${i + 1}.`);
      for (const [j, question] of section.questions.entries()) {
        expect(question.key).toBe(`s${String(i + 1).padStart(2, '0')}-q${String(j + 1).padStart(2, '0')}`);
      }
    }
  });

  it('retains irregular labels, the combined source row, truncation and blank responses', () => {
    expect(template.sections[0]!.questions[12]!.label).toBe('m');
    expect(template.sections[0]!.questions[15]!.text).toContain('standards or expectations Worked with faculty');
    expect(template.sections[0]!.questions[16]!.text).toMatch(/coworkers, etc\.$/);
    expect(template.sections[6]!.questions.map((q) => q.label)).toEqual(['a.', 'b.', 'c.', 'd.', 'e.', 'f.', 'g.', 'h.', 'i.', 'j.', 'k.', 'm', 'n.', 'o.']);
    expect(template.sections[7]!.questions[1]!.text).toBe('Providing the support you need to help you succeed academicall');
    expect(template.sections[8]!.prompt).toBe('How would you evaluate your entire educational experience at this institution?');
    expect(template.sections[9]!.prompt).toBe('If you could start over again, would you go to the same institution you are now attending?');
  });

  it('accepts all exact option types, all-null answers, and only student-written text', () => {
    const answers = OFFICIAL_QUESTIONS.map((q) => ({ questionKey: q.key, value: q.section.options[0]?.value ?? 'My own response' }));
    expect(validateOfficialAnswers({ questionnaireVersion: 2, answers, essay: 'My essay' })).toEqual(answers);
    expect(validateOfficialAnswers({ questionnaireVersion: 2, answers: answers.map((a) => ({ ...a, value: null })) }).every((a) => a.value === null)).toBe(true);
    expect(validateOfficialAnswers({ questionnaireVersion: 2, answers: [{ questionKey: 's09-q01', value: '  ' }] })[0]!.value).toBeNull();
    expect(validateOfficialAnswers({ questionnaireVersion: 2, answers: [] })).toEqual([]);
  });

  it.each([
    ['s01-q01', 'yes'], ['s02-q01', 'never'], ['s03-q01', 4], ['s04-q01', '7'],
    ['s04-q01', 0], ['s04-q01', 8], ['s04-q01', 1.5], ['s05-q01', true],
    ['s06-q01', 0], ['s07-q01', 'often'], ['s08-q01', {}], ['s09-q01', 2],
    ['s10-q01', 'x'.repeat(5001)], ['invented', null],
  ])('rejects invalid response for %s (including non-coercion)', (questionKey, value) => {
    expect(() => validateOfficialAnswers({ questionnaireVersion: 2, answers: [{ questionKey, value }] } as SaveCollegeReport)).toThrow();
  });

  it('rejects duplicate IDs, wrong versions and overlong essays', () => {
    const answer = { questionKey: 's01-q01', value: 'often' };
    expect(() => validateOfficialAnswers({ questionnaireVersion: 2, answers: [answer, answer] })).toThrow();
    expect(() => validateOfficialAnswers({ questionnaireVersion: 1, answers: [] })).toThrow();
    expect(() => validateOfficialAnswers({ questionnaireVersion: 2, answers: [], essay: 'x'.repeat(10001) })).toThrow();
  });
});
