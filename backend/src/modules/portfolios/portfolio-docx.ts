import sharp from 'sharp';
import { PDFDocument } from 'pdf-lib';
import { getDocument, VerbosityLevel } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { AppError } from '../../common/errors/app-error.js';
import type { DocumentRecord } from '../../database/repositories/document.repository.js';
import type { OfficialReportView } from '../college-report/college-report.service.js';
import { OFFICIAL_COLLEGE_REPORT } from '../college-report/college-report.template.js';
import { DocxPackage, paragraph as p, pageBreak, xml, questionnaireTable } from './docx-package.js';
import { exportDescription } from '../documents/description-source.js';
import { portfolioFontBytes } from './portfolio-font-assets.js';
import { loadPortfolioFallbackFonts, wrapPortfolioText } from './portfolio-layout.js';
import { measureExport, type ExportObserver } from './export-metrics.js';
import { flattenExportForm } from './flatten-export-form.js';
import { officialNeuSealPng, standardTitlePage } from './portfolio-title-page.js';
import {
  MAX_PORTFOLIO_DOCUMENTS, MAX_PORTFOLIO_TOTAL_PAGES, MAX_PORTFOLIO_TOTAL_SOURCE_BYTES,
  planPortfolioSections, type PortfolioExportInfo,
} from './portfolio-generator.service.js';

const tooLarge = () => new AppError(413, 'PORTFOLIO_TOO_LARGE',
  'This editable portfolio is too large. Reduce the number or size of the source files and retry.');
const corrupt = () => new AppError(422, 'PORTFOLIO_ARTIFACT_CORRUPT',
  'An uploaded file could not be included in DOCX. Review the original file and upload a readable image or PDF copy. No evidence was omitted.');

/** Uses the same owner-scoped snapshot and ordering as PDF. Word text remains
 * editable; original evidence is embedded as images, not misrepresented as
 * editable source text. Raster failure aborts rather than losing a source page. */
export async function generatePortfolioDocx(
  documents: readonly DocumentRecord[], info: PortfolioExportInfo,
  report: OfficialReportView | null, program: string,
  fetchBytes: (key: string) => Promise<Buffer>,
  observe?: ExportObserver,
): Promise<Buffer> {
  if (documents.length > MAX_PORTFOLIO_DOCUMENTS) throw tooLarge();
  const sections = planPortfolioSections(documents);
  if (report && !sections.some((s) => s.key === 'college-report')) {
    sections.push({ key: 'college-report', name: 'College Report', subsections: [] });
  }
  const declaredSize = sections.flatMap((s) => s.subsections.flatMap((sub) => sub.items.flatMap((item) => item.attachments)))
    .reduce((sum, a) => sum + a.sizeBytes, 0);
  if (declaredSize > MAX_PORTFOLIO_TOTAL_SOURCE_BYTES) throw tooLarge();
  const pkg = new DocxPackage();
  for (const bold of [false, true]) {
    await measureExport('fonts', observe, async () => pkg.font(await portfolioFontBytes(bold), bold));
  }
  const body: string[] = [];
  const sealId = pkg.image(await officialNeuSealPng());
  // Named title-header exception: three fixed cells mirror PDF's symmetric
  // 60pt seals inside 108pt margins; no guessed college or program description.
  const cell = (width: number, content: string) => `<w:tc><w:tcPr><w:tcW w:w="${width}" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>${content}</w:tc>`;
  const center = '<w:jc w:val="center"/>';
  const seal = () => `<w:p><w:pPr><w:spacing w:after="0"/>${center}</w:pPr>${pkg.drawing(sealId, 60, 60, 'Official New Era University seal')}</w:p>`;
  body.push(`<w:tbl><w:tblPr><w:tblW w:w="7920" w:type="dxa"/><w:tblInd w:w="0" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="0" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w="1200"/><w:gridCol w:w="5520"/><w:gridCol w:w="1200"/></w:tblGrid><w:tr><w:trPr><w:cantSplit/></w:trPr>${cell(1200, seal())}${cell(5520, p('NEW ERA UNIVERSITY', 'Question', center) + (program.trim() ? p(program.trim(), 'Normal', center) : ''))}${cell(1200, seal())}</w:tr></w:tbl>`);
  body.push(p('', 'Normal', '<w:pBdr><w:bottom w:val="single" w:sz="16" w:space="8" w:color="000000"/></w:pBdr><w:ind w:right="720"/>'));
  const titleLines = standardTitlePage(info).filter((_, i) => i !== 2 && i !== 5);
  const fonts = await loadPortfolioFallbackFonts(await PDFDocument.create());
  const headerHeight = Math.max(60, (wrapPortfolioText('NEW ERA UNIVERSITY', fonts.bold, 276).length + wrapPortfolioText(program, fonts.regular, 276).length) * 18 + 20);
  const titleHeight = headerHeight + 64 + titleLines.slice(2).reduce((height, line) => height + wrapPortfolioText(line, fonts.regular, 396).length * 18, 0) + 7 * 5;
  if (titleHeight > 620) throw new AppError(422, 'PORTFOLIO_TITLE_TOO_LONG', 'Shorten the title-page fields or profile program so the complete title page fits on one Letter page.');
  body.push(p(titleLines[0]!, 'Title', '<w:ind w:right="720"/>' + center));
  body.push(p(titleLines[1]!, 'TitleField', '<w:ind w:right="720"/>'));
  for (let i = 2; i < titleLines.length; i += 2) body.push(p(`${titleLines[i]}\n${titleLines[i + 1] ?? ''}`, 'TitleField', '<w:ind w:right="720"/>'));

  let sourceBytes = 0, mediaBytes = 0, evidencePages = 0;
  const addMedia = (data: Buffer, width: number, height: number, description: string) => {
    if (++evidencePages > MAX_PORTFOLIO_TOTAL_PAGES) throw tooLarge();
    mediaBytes += data.length;
    if (mediaBytes > MAX_PORTFOLIO_TOTAL_SOURCE_BYTES) throw tooLarge();
    const scale = Math.min(432 / width, 528 / height, 1);
    const id = pkg.image(data);
    body.push(`<w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/>${center}</w:pPr>${pkg.drawing(id, width * scale, height * scale, description)}</w:p>`);
  };
  const addImage = async (bytes: Buffer, description: string) => {
    const { data, info: size } = await sharp(bytes, { limitInputPixels: 25_000_000 })
      .rotate().resize({ width: 1440, height: 1800, fit: 'inside', withoutEnlargement: true }).png().toBuffer({ resolveWithObject: true });
    addMedia(data, size.width, size.height, description);
  };
  const pdfPages = async (bytes: Buffer, name: string, creative: boolean) => {
    // Flatten entered form values before rasterizing. Unsupported dynamic forms
    // fail actionably using the same guard as PDF export.
    const source = await PDFDocument.load(bytes);
    const flattened = flattenExportForm(source);
    if (creative && source.getPageCount() !== 1) throw new AppError(422, 'PORTFOLIO_CREATIVE_TITLE_AMBIGUOUS', 'A Creative Title must be one page. No uploaded pages were omitted.');
    if (!source.getPageCount() || evidencePages + source.getPageCount() > MAX_PORTFOLIO_TOTAL_PAGES) throw tooLarge();
    const task = getDocument({ data: flattened ? await source.save() : new Uint8Array(bytes), useSystemFonts: true, verbosity: VerbosityLevel.ERRORS,
      stopAtErrors: true });
    const timer = setTimeout(() => { void task.destroy().catch(() => undefined); }, 45_000);
    try {
      const pdf = await task.promise;
      const factory = pdf.canvasFactory as {
        create(w: number, h: number): { canvas: HTMLCanvasElement & { toBuffer(type: string): Buffer }; context: CanvasRenderingContext2D };
        destroy(target: { canvas: HTMLCanvasElement; context: CanvasRenderingContext2D }): void;
      };
      for (let n = 1; n <= pdf.numPages; n++) {
        const page = await pdf.getPage(n);
        const natural = page.getViewport({ scale: 1 });
        const viewport = page.getViewport({ scale: Math.min(2, 1440 / Math.max(natural.width, natural.height)) });
        const target = factory.create(Math.ceil(viewport.width), Math.ceil(viewport.height));
        try {
          await page.render({ canvas: target.canvas, canvasContext: target.context, viewport }).promise;
          if (n > 1) body.push(pageBreak);
          // Canvas output is already oriented and bounded. Do not decode and
          // PNG-encode every PDF page again through sharp (same pixels/quality).
          addMedia(target.canvas.toBuffer('image/png'), Math.ceil(viewport.width), Math.ceil(viewport.height), `${name}, PDF page ${n} of ${pdf.numPages}`);
        } finally { factory.destroy(target); page.cleanup(); }
      }
    } finally { clearTimeout(timer); await task.destroy(); }
  };
  const sectionContent = async (section: (typeof sections)[number], index: number) => {
    let first = true;
    const nextPage = () => {
      body.push(pageBreak);
      if (first) { body.push(`<w:bookmarkStart w:id="${index}" w:name="section${index}"/>`); first = false; }
    };
    for (const sub of section.subsections) {
      for (const item of sub.items) {
        const doc = item.document;
        for (const [index, a] of item.attachments.entries()) {
          nextPage();
          const bytes = await measureExport('storage', observe, () => fetchBytes(a.objectKey));
          sourceBytes += bytes.length;
          if (sourceBytes > MAX_PORTFOLIO_TOTAL_SOURCE_BYTES) throw tooLarge();
          try {
            if (a.fileKind === 'pdf') await measureExport('pdf-raster', observe, () => pdfPages(bytes, doc.title, sub.key === 'creative-title'));
            else if (a.fileKind === 'image') {
              await measureExport('image-evidence', observe, () => addImage(bytes, `${doc.title}, image ${index + 1}`));
            } else {
              throw new AppError(422, 'PORTFOLIO_ARTIFACT_UNSUPPORTED',
                'DOCX evidence must be an image or PDF. Convert the unsupported source file and upload it again. No evidence was omitted.');
            }
          } catch (error) { if (error instanceof AppError) throw error; throw corrupt(); }
        }
        const description = exportDescription(doc);
        if (description || doc.reflection?.trim()) body.push(pageBreak);
        if (description) body.push(p('Description', 'Heading2'), p(description));
        if (doc.reflection?.trim()) body.push(p('Student Reflection', 'Heading2'), p(doc.reflection));
      }
    }
    if (section.key === 'college-report' && report) { nextPage(); body.push(await measureExport('questionnaire', observe, () => collegeReportDocx(report))); }
    body.push(`<w:bookmarkEnd w:id="${index}"/>`);
  };
  body.push(pageBreak, p('TABLE OF CONTENTS', 'Heading1'),
    p('Select a section below. Headings and text can be edited in Word. Uploaded evidence is embedded as images; use PDF export for original PDF-page fidelity.'));
  sections.forEach((s, i) => body.push(`<w:p><w:hyperlink w:anchor="section${i}"><w:r><w:t>${xml(s.name)}</w:t></w:r></w:hyperlink></w:p>`));
  for (const [index, section] of sections.entries()) {
    await sectionContent(section, index);
  }
  return measureExport('docx-package', observe, () => pkg.finish(body.join('')));
}

function collegeReportDocx(report: OfficialReportView): string {
  const body = [p(OFFICIAL_COLLEGE_REPORT.title, 'Heading2'), p(OFFICIAL_COLLEGE_REPORT.instructions)];
  const answers = new Map(report.answers.map((a) => [a.questionKey, a.value]));
  for (const s of OFFICIAL_COLLEGE_REPORT.sections) {
    body.push(p(`${s.label} ${s.prompt}`, 'Heading2'));
    if (s.note && s.responseType !== 'text') body.push(p(s.note));
    if (s.options.length) {
      const width = s.options.length <= 4 ? 1440
        : s.options.length === 5 ? 1040
        : s.options.length === 7 ? 520
        : 640;
      const widths = [480, 8640 - 480 - width * s.options.length, ...s.options.map(() => width)];
      body.push(questionnaireTable([['', '', ...s.options.map(o => o.label)], ...s.questions.map(q =>
        [q.label, q.label ? q.text : '', ...s.options.map(o => answers.get(q.key) === o.value ? 'X' : '')])], widths));
      continue;
    }
    for (const q of s.questions) {
      if (q.label || q.text !== s.prompt) body.push(p(`${q.label} ${q.text}`.trim(), 'Question'));
      const value = answers.get(q.key) ?? null;
      body.push(p(value === null ? 'Response: Unanswered' : s.responseType === 'text' ? `Response: ${value}` :
        `Selected response: ${s.options.find((o) => o.value === value)!.label}`, 'Response'));
    }
  }
  if (report.essay.trim()) body.push(p('Student-written essay / objectives', 'Heading2'), p(report.essay, 'Response'));
  body.push(p(`Reference: ${OFFICIAL_COLLEGE_REPORT.reference}`));
  return body.join('');
}
