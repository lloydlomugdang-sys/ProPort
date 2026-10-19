import { getDocument, OPS } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { describe, expect, it } from 'vitest';
import { PortfolioGeneratorService } from '../../src/modules/portfolios/portfolio-generator.service.js';
import { OFFICIAL_COLLEGE_REPORT, OFFICIAL_QUESTIONS } from '../../src/modules/college-report/college-report.template.js';
import type { OfficialReportView } from '../../src/modules/college-report/college-report.service.js';
import { portfolioMemoryStorage, PORTFOLIO_TEST_INFO } from '../helpers/portfolio-fixtures.js';

describe('saved College Report PDF rendering', () => {
  it('includes all questions, exact selected labels, unanswered items, essay and accurate final TOC under Phase B geometry', async () => {
    const answers = OFFICIAL_QUESTIONS.map((q) => ({ questionKey: q.key, value: null as string | number | null }));
    answers.find((a) => a.questionKey === 's01-q01')!.value = 'often';
    answers.find((a) => a.questionKey === 's02-q01')!.value = 'once';
    answers.find((a) => a.questionKey === 's04-q01')!.value = 6;
    answers.find((a) => a.questionKey === 's07-q01')!.value = 'quite_a_bit';
    answers.find((a) => a.questionKey === 's09-q01')!.value = Array.from({ length: 70 }, (_, i) => `My response paragraph ${i}.`).join('\n');
    const report: OfficialReportView = { questionnaireVersion: 2, answers, essay: 'My student-written objectives and reflection.', updatedAt: new Date().toISOString() };
    const bytes = await new PortfolioGeneratorService(undefined, portfolioMemoryStorage()).generateFromDocuments([], PORTFOLIO_TEST_INFO, report);
    const task = getDocument({ data: new Uint8Array(bytes), useSystemFonts: true });
    try {
      const pdf = await task.promise;
      const pages = [];
      let shadedPages = 0;
      for (let number = 1; number <= pdf.numPages; number++) {
        const page = await pdf.getPage(number);
        const ops = await page.getOperatorList();
        if (ops.fnArray.some((op, i) => op === OPS.constructPath && [OPS.fill, OPS.fillStroke].includes(ops.argsArray[i][0]))) shadedPages++;
        expect(page.view).toEqual([0, 0, 612, 792]);
        const items = (await page.getTextContent()).items.filter((i) => 'str' in i);
        for (const item of items.filter((i) => i.str.trim())) {
          expect(item.transform[4]).toBeGreaterThanOrEqual(108);
          expect(item.transform[4] + item.width, item.str).toBeLessThanOrEqual(540.01);
          expect(item.transform[5]).toBeGreaterThanOrEqual(72);
          expect(item.transform[5] + item.height).toBeLessThanOrEqual(720.01);
          expect(item.height).toBeCloseTo(12);
        }
        pages.push({ text: items.map((i) => i.str).join(' ').replace(/\s+/g, ' '), items });
      }
      const text = pages.map((p) => p.text).join(' ');
      expect(OFFICIAL_COLLEGE_REPORT.sections).toHaveLength(10);
      expect(OFFICIAL_QUESTIONS).toHaveLength(62);
      expect(shadedPages).toBeGreaterThanOrEqual(8);
      expect(text).toContain(OFFICIAL_COLLEGE_REPORT.instructions);
      expect(pages.flatMap(p => p.items).filter(i => i.str === 'X')).toHaveLength(4);
      expect(text).toContain('Never');
      let previous = -1;
      for (const section of OFFICIAL_COLLEGE_REPORT.sections) {
        const at = text.indexOf(`${section.label} ${section.prompt}`);
        expect(at).toBeGreaterThan(previous); previous = at;
        for (const option of section.options) expect(text.replace(/\s/g, '')).toContain(option.label.replace(/\s/g, ''));
      }
      for (const question of OFFICIAL_QUESTIONS) expect(text.replace(/\s/g, '')).toContain(question.text.replace(/\s/g, ''));
      expect(text.match(/Unanswered/g)).toHaveLength(1); // blank choice boxes, optional written response only
      expect(text).not.toContain('quite_a_bit');
      for (let i = 0; i < 70; i++) expect(text).toContain(`My response paragraph ${i}.`);
      expect(text).toContain('My student-written objectives and reflection.');
      expect(text).toContain('9. Response (continued)');
      for (const page of pages.filter(p => p.text.includes('9. Response (continued)'))) {
        expect(page.text).toContain('My response paragraph');
      }
      const toc = pages.find((p) => p.text.includes('TABLE OF CONTENTS'))!;
      expect(toc.items.filter((i) => i.str === 'College Report')).toHaveLength(1);
      const label = toc.items.find((i) => i.str === 'College Report')!;
      const target = toc.items.find((i) => /^\d+$/.test(i.str) && i.transform[4] > 500 && i.transform[5] === label.transform[5])!;
      expect(pages[Number(target.str) - 1]!.text).toContain('College Report');
      expect(pages.at(-1)!.text).toContain('Reference:');
    } finally { await task.destroy(); }
  });

  it('does not fabricate an unsaved questionnaire or essay', async () => {
    const generator = new PortfolioGeneratorService(undefined, portfolioMemoryStorage());
    const bytes = await generator.generateFromDocuments([], PORTFOLIO_TEST_INFO);
    const task = getDocument({ data: new Uint8Array(bytes), useSystemFonts: true });
    try {
      const pdf = await task.promise;
      const texts = await Promise.all(Array.from({ length: pdf.numPages }, async (_, i) => {
        const page = await pdf.getPage(i + 1);
        return (await page.getTextContent()).items.filter((i) => 'str' in i).map((i) => i.str).join(' ');
      }));
      expect(texts.join(' ')).not.toMatch(/College Report|Selected response|Student-written essay/);
    } finally { await task.destroy(); }
  });
});
