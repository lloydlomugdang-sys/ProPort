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
  const lines = (text: string, bold = false, questionnaire?: TextLine['questionnaire']): TextLine[] =>
    wrapPortfolioText(text, bold ? measured.bold : measured.regular, questionnaire ? 408 : undefined)
      .map((text) => ({ text, bold, indent: questionnaire ? 12 : 0,
        ...(questionnaire ? { questionnaire } : {}) }));
  const block = (content: TextLine[], continuation: string) => {
    if (current.length && current.length + content.length > TEXT_LINES_PER_PAGE) flush();
    let remaining = content;
    while (remaining.length) {
      const capacity = TEXT_LINES_PER_PAGE - current.length;
      current.push(...remaining.slice(0, capacity));
      remaining = remaining.slice(capacity);
      if (remaining.length) {
        flush();
        current.push(...lines(`${continuation} (continued)`, true, 'section'));
      }
    }
  };
  const answers = new Map(report.answers.map((answer) => [answer.questionKey, answer.value]));
  for (const section of OFFICIAL_COLLEGE_REPORT.sections) {
    // Flow short sections together. The first question's block keeps each
    // source heading/options together instead of forcing almost-empty pages.
    const heading = `${section.label} ${section.prompt}`;
    let first = true;
    for (const question of section.questions) {
      const value = answers.get(question.key) ?? null;
      const questionHeading = `${question.label} ${question.text}`.trim();
      const prefix = first ? [
        ...(section.id === 's01' ? [...lines(OFFICIAL_COLLEGE_REPORT.title, true),
          ...lines(OFFICIAL_COLLEGE_REPORT.instructions)] : []),
        ...lines(heading, true, 'section'), ...(section.note ? lines(section.note) : []), ...lines(''),
      ] : [];
      const selection = section.options.find((option) => option.value === value);
      block([
        ...prefix,
        ...(question.label ? lines(questionHeading, true) : []),
        ...(section.options.length ? lines(section.options.map((option) =>
          `${option.value === value ? '[x]' : '[ ]'} ${option.label}`).join('   ')) : []),
        ...lines(value === null ? 'Response: Unanswered' :
          section.responseType === 'text' ? `Response: ${value}` : `Selected response: ${selection!.label}`,
        value !== null && section.responseType !== 'text', 'response'),
        ...lines(''),
      ], `${section.label}${question.label ? ` ${question.label}` : ''} Response`);
      first = false;
    }
  }
  if (report.essay.trim()) {
    block([...lines(''), ...lines('Student-written essay / objectives', true), ...lines(report.essay)], 'Student-written essay / objectives');
  }
  block([...lines(''), ...lines(`Reference: ${OFFICIAL_COLLEGE_REPORT.reference}`)], 'Reference');
  flush();
  return pages;
}
