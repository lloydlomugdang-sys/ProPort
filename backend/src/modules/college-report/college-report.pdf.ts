import type { OfficialReportView } from './college-report.service.js';
import type { PDFFont } from 'pdf-lib';
import { OFFICIAL_COLLEGE_REPORT } from './college-report.template.js';
import { TEXT_LINES_PER_PAGE, wrapPortfolioText, type PortfolioFonts, type TextLine } from '../portfolios/portfolio-layout.js';

/** Structured question/options/selection blocks, using Phase B's font metrics.
 * Keeps ordinary questions with their answers. Long written responses continue
 * on explicitly labelled pages, never truncated or replaced with generated text.
 */
export function collegeReportPages(report: OfficialReportView, fonts: PortfolioFonts): readonly TextLine[][] {
  const pages: TextLine[][] = [];
  let current: TextLine[] = [];
  const flush = () => { if (current.length) pages.push(current); current = []; };
  // Standard-font widthOfTextAtSize includes kerning, but PDF drawText emits
  // unkerned glyph advances. Measure conservatively without changing Phase B.
  const measuringFont = (font: PDFFont) => new Proxy(font, {
    get(target, property, receiver) {
      if (property === 'widthOfTextAtSize') return (text: string, size: number) => Math.max(
        font.widthOfTextAtSize(text, size),
        [...text].reduce((width, character) => width + font.widthOfTextAtSize(character, size), 0),
      );
      return Reflect.get(target, property, receiver);
    },
  });
  const measured = { regular: measuringFont(fonts.regular), bold: measuringFont(fonts.bold) };
  const lines = (text: string, bold = false): TextLine[] => wrapPortfolioText(text, bold ? measured.bold : measured.regular)
    .map((text) => ({ text, bold, indent: 0 }));
  const block = (content: TextLine[], continuation: string) => {
    if (current.length && current.length + content.length > TEXT_LINES_PER_PAGE) flush();
    let remaining = content;
    while (remaining.length) {
      const capacity = TEXT_LINES_PER_PAGE - current.length;
      current.push(...remaining.slice(0, capacity));
      remaining = remaining.slice(capacity);
      if (remaining.length) {
        flush();
        current.push(...lines(`${continuation} (continued)`, true));
      }
    }
  };
  const answers = new Map(report.answers.map((answer) => [answer.questionKey, answer.value]));
  for (const section of OFFICIAL_COLLEGE_REPORT.sections) {
    flush(); // deterministic section starts, with no empty pages
    const heading = `${section.label} ${section.prompt}`;
    let first = true;
    for (const question of section.questions) {
      const value = answers.get(question.key) ?? null;
      const questionHeading = `${question.label} ${question.text}`.trim();
      const prefix = first ? [
        ...lines(heading, true), ...(section.note ? lines(section.note) : []), ...lines(''),
      ] : [];
      const selection = section.options.find((option) => option.value === value);
      block([
        ...prefix,
        ...(question.label ? lines(questionHeading, true) : []),
        ...(section.options.length ? lines(`Options: ${section.options.map((option) => option.label).join(' | ')}`) : []),
        ...lines(value === null ? 'Response: Unanswered' :
          section.responseType === 'text' ? `Response: ${value}` : `Selected response: ${selection!.label}`),
        ...lines(''),
      ], `${section.label}${question.label ? ` ${question.label}` : ''} Response`);
      first = false;
    }
  }
  flush();
  if (report.essay.trim()) {
    block([...lines('Student-written essay / objectives', true), ...lines(report.essay)], 'Student-written essay / objectives');
    flush();
  }
  block(lines(`Reference: ${OFFICIAL_COLLEGE_REPORT.reference}`), 'Reference');
  flush();
  return pages;
}
