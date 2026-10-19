import { rgb, type PDFPage } from 'pdf-lib';
import type { OfficialReportView } from './college-report.service.js';
import { OFFICIAL_COLLEGE_REPORT } from './college-report.template.js';
import { CONTENT_WIDTH, PORTFOLIO_LAYOUT as L, wrapPortfolioText, type PortfolioFonts } from '../portfolios/portfolio-layout.js';

interface Cell { x: number; top: number; width: number; height: number; text: string[]; bold?: boolean; center?: boolean; fill?: boolean }
export interface QuestionnairePage { cells: Cell[] }
const LEADING = 16; // Local table rhythm only; existing global 12pt font/margins unchanged.

/** Source questionnaire's item/response-column tables. Empty choice cells mean
 * unanswered, as on the source. Continuation pages repeat the response scale. */
export function collegeReportPages(report: OfficialReportView, fonts: PortfolioFonts): QuestionnairePage[] {
  const pages: QuestionnairePage[] = [];
  let page: QuestionnairePage = { cells: [] }, y = L.height - L.top;
  const fresh = () => { page = { cells: [] }; pages.push(page); y = L.height - L.top; };
  fresh();
  const wrap = (text: string, width = CONTENT_WIDTH, bold = false) => wrapPortfolioText(text, bold ? fonts.bold : fonts.regular, width);
  const space = (height: number) => { if (y - height < L.bottom + 36) fresh(); };
  const prose = (text: string, bold = false) => {
    for (const line of wrap(text, CONTENT_WIDTH, bold)) {
      space(LEADING); page.cells.push({ x: L.left, top: y, width: 0, height: 0, text: [line], bold }); y -= LEADING;
    }
    y -= 8;
  };
  prose(OFFICIAL_COLLEGE_REPORT.title, true);
  prose(OFFICIAL_COLLEGE_REPORT.instructions);
  const answers = new Map(report.answers.map(a => [a.questionKey, a.value]));
  for (const section of OFFICIAL_COLLEGE_REPORT.sections) {
    const prompt = `${section.label} ${section.prompt}`;
    const promptHeight = wrap(prompt, CONTENT_WIDTH, true).length * LEADING + 8;
    const optionWidth = section.options.length <= 4 ? 72
      : section.options.length === 5 ? 52
      : section.options.length === 7 ? 26
      : 32;
    const labelWidth = 24;
    const questionWidth = CONTENT_WIDTH - labelWidth - optionWidth * section.options.length;
    const headers = section.options.map(o => wrap(o.label.replaceAll(' – ', '–'), optionWidth - 4, true));
    const headerHeight = Math.max(1, ...headers.map(h => h.length)) * LEADING + 12;
    const row = (texts: string[][], widths: number[], height: number, header = false) => {
      let x = L.left;
      texts.forEach((text, i) => {
        page.cells.push({ x, top: y, width: widths[i]!, height, text, bold: header, center: i !== 1, fill: header }); x += widths[i]!;
      });
      y -= height;
    };
    const tableHeader = () => row([[], [], ...headers], [labelWidth, questionWidth, ...headers.map(() => optionWidth)], headerHeight, true);
    const firstQuestion = section.questions[0]!;
    const firstRowHeight = Math.max(1, wrap(firstQuestion.text, questionWidth - 10).length) * LEADING + 12;
    const noteHeight = section.note && section.responseType !== 'text' ? wrap(section.note).length * LEADING + 8 : 0;
    space(promptHeight + noteHeight + (section.options.length ? headerHeight + firstRowHeight : 90));
    prose(prompt, true);
    if (section.responseType === 'text') {
      const response = answers.get(firstQuestion.key);
      const text = wrap(response === null || response === undefined ? 'Unanswered' : String(response), CONTENT_WIDTH - 16);
      let offset = 0;
      while (offset < text.length) {
        if (offset > 0) {
          fresh();
          prose(`${section.label} Response (continued)`, true);
        } else if (y - L.bottom - 36 < 64) {
          fresh();
        }
        const availableLines = Math.floor((y - L.bottom - 36 - 16) / LEADING);
        if (availableLines < 1) {
          fresh();
          if (offset > 0) prose(`${section.label} Response (continued)`, true);
          continue;
        }
        const count = Math.min(text.length - offset, availableLines);
        const height = Math.max(48, count * LEADING + 16);
        page.cells.push({ x: L.left, top: y, width: CONTENT_WIDTH, height, text: text.slice(offset, offset + count) });
        y -= height + 12;
        offset += count;
      }
      continue;
    }
    if (section.note) prose(section.note);
    tableHeader();
    for (const question of section.questions) {
      const words = question.label ? wrap(question.text, questionWidth - 10) : [];
      const height = Math.max(1, words.length) * LEADING + 12;
      if (y - height < L.bottom + 36) { fresh(); prose(`${section.label} (continued)`, true); tableHeader(); }
      const answer = answers.get(question.key);
      row([[question.label], words, ...section.options.map(o => [answer === o.value ? 'X' : ''])],
        [labelWidth, questionWidth, ...section.options.map(() => optionWidth)], height);
    }
    y -= 18;
  }
  if (report.essay.trim()) { space(LEADING * 3); prose('Student-written essay / objectives', true); prose(report.essay); }
  const reference = `Reference: ${OFFICIAL_COLLEGE_REPORT.reference}`;
  space(wrap(reference).length * LEADING + 8);
  prose(reference);
  return pages;
}

export function drawCollegeReportPage(page: PDFPage, plan: QuestionnairePage, fonts: PortfolioFonts): void {
  for (const cell of plan.cells) {
    if (cell.width) page.drawRectangle({ x: cell.x, y: cell.top - cell.height, width: cell.width, height: cell.height,
      borderWidth: .5, borderColor: rgb(.3, .3, .3), ...(cell.fill ? { color: rgb(.94, .94, .94) } : {}) });
    const font = cell.bold ? fonts.bold : fonts.regular;
    cell.text.forEach((text, i) => page.drawText(text, { x: cell.center ? cell.x + (cell.width - font.widthOfTextAtSize(text, L.bodySize)) / 2 : cell.x + (cell.width ? 5 : 0),
      y: cell.top - L.bodySize - (cell.width ? 6 : 0) - i * LEADING, font, size: L.bodySize, color: rgb(0, 0, 0) }));
  }
}
