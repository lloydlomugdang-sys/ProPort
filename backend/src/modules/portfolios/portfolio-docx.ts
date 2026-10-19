import sharp from 'sharp';
import { readFile } from 'node:fs/promises';
import { PDFDocument } from 'pdf-lib';
import { getDocument, VerbosityLevel } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { AppError } from '../../common/errors/app-error.js';
import type { DocumentRecord } from '../../database/repositories/document.repository.js';
import type { OfficialReportView } from '../college-report/college-report.service.js';
import { OFFICIAL_COLLEGE_REPORT } from '../college-report/college-report.template.js';
import { DocxPackage, paragraph as p, pageBreak, xml } from './docx-package.js';
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
    const name = `NotoSans-${bold ? 'Bold' : 'Regular'}.ttf`;
    const bytes = await readFile(new URL(`../../../../assets/fonts/${name}`, import.meta.url))
      .catch(() => readFile(new URL(`../../../../../assets/fonts/${name}`, import.meta.url)));
    pkg.font(bytes, bold);
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
  for (const [i, line] of standardTitlePage(info).entries()) {
    body.push(p(line, i === 0 ? 'Title' : 'Normal', `<w:ind w:right="720"/>${center}`));
  }

  let sourceBytes = 0, mediaBytes = 0, evidencePages = 0;
  const addImage = async (bytes: Buffer, description: string) => {
    if (++evidencePages > MAX_PORTFOLIO_TOTAL_PAGES) throw tooLarge();
    const { data, info: size } = await sharp(bytes, { limitInputPixels: 25_000_000 })
      .rotate().resize({ width: 1440, height: 1800, fit: 'inside', withoutEnlargement: true }).png().toBuffer({ resolveWithObject: true });
    mediaBytes += data.length;
    if (mediaBytes > MAX_PORTFOLIO_TOTAL_SOURCE_BYTES) throw tooLarge();
    const scale = Math.min(432 / size.width, 528 / size.height, 1);
    const id = pkg.image(data);
    body.push(`<w:p><w:pPr>${center}</w:pPr>${pkg.drawing(id, size.width * scale, size.height * scale, description)}</w:p>`);
  };
  const pdfPages = async (bytes: Buffer, name: string) => {
    // Flatten entered form values before rasterizing. Unsupported dynamic forms
    // fail actionably using the same guard as PDF export.
    const source = await PDFDocument.load(bytes);
    flattenExportForm(source);
    if (!source.getPageCount() || evidencePages + source.getPageCount() > MAX_PORTFOLIO_TOTAL_PAGES) throw tooLarge();
    const task = getDocument({ data: await source.save(), useSystemFonts: true, verbosity: VerbosityLevel.ERRORS,
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
          body.push(pageBreak, p(`${name} — PDF page ${n} of ${pdf.numPages}`, 'Heading2'));
          await addImage(target.canvas.toBuffer('image/png'), `${name}, PDF page ${n} of ${pdf.numPages}`);
        } finally { factory.destroy(target); page.cleanup(); }
      }
    } finally { clearTimeout(timer); await task.destroy(); }
  };
  const sectionContent = async (section: (typeof sections)[number], index: number) => {
    body.push(pageBreak, `<w:bookmarkStart w:id="${index}" w:name="section${index}"/>`,
      p(section.name, 'Heading1'), `<w:bookmarkEnd w:id="${index}"/>`);
    for (const sub of section.subsections) {
      if (section.key !== 'creative-title' && sub.name !== section.name) body.push(p(sub.name, 'Heading2'));
      for (const [itemIndex, item] of sub.items.entries()) {
        const doc = item.document;
        if (section.key === 'creative-title' && itemIndex > 0) body.push(pageBreak);
        body.push(p(doc.title, 'Heading2'), p(`Source: ${doc.originalFileName}`));
        if (doc.description?.trim()) body.push(p('Description', 'Heading2'), p(doc.description));
        if (doc.reflection?.trim()) body.push(p('Student Reflection', 'Heading2'), p(doc.reflection));
        for (const [index, a] of item.attachments.entries()) {
          const bytes = await fetchBytes(a.objectKey);
          sourceBytes += bytes.length;
          if (sourceBytes > MAX_PORTFOLIO_TOTAL_SOURCE_BYTES) throw tooLarge();
          try {
            if (a.fileKind === 'pdf') await pdfPages(bytes, doc.title);
            else if (a.fileKind === 'image') {
              body.push(p(`${doc.title} — image ${index + 1}`, 'Question'));
              await addImage(bytes, `${doc.title}, image ${index + 1}`);
            } else {
              throw new AppError(422, 'PORTFOLIO_ARTIFACT_UNSUPPORTED',
                'DOCX evidence must be an image or PDF. Convert the unsupported source file and upload it again. No evidence was omitted.');
            }
          } catch (error) { if (error instanceof AppError) throw error; throw corrupt(); }
        }
      }
    }
    if (section.key === 'college-report' && report) body.push(collegeReportDocx(report));
  };
  const creativeIndex = sections.findIndex((s) => s.key === 'creative-title');
  if (creativeIndex !== -1) await sectionContent(sections[creativeIndex]!, creativeIndex);
  body.push(pageBreak, p('TABLE OF CONTENTS', 'Heading1'),
    p('Select a section below. Headings and text can be edited in Word. Uploaded evidence is embedded as images; use PDF export for original PDF-page fidelity.'));
  sections.forEach((s, i) => body.push(`<w:p><w:hyperlink w:anchor="section${i}"><w:r><w:t>${xml(s.name)}</w:t></w:r></w:hyperlink></w:p>`));
  for (const [index, section] of sections.entries()) {
    if (index !== creativeIndex) await sectionContent(section, index);
  }
  return pkg.finish(body.join(''));
}

function collegeReportDocx(report: OfficialReportView): string {
  const body = [p(OFFICIAL_COLLEGE_REPORT.title, 'Heading2'), p(OFFICIAL_COLLEGE_REPORT.instructions)];
  const answers = new Map(report.answers.map((a) => [a.questionKey, a.value]));
  for (const s of OFFICIAL_COLLEGE_REPORT.sections) {
    body.push(p(`${s.label} ${s.prompt}`, 'Heading2'));
    if (s.note) body.push(p(s.note));
    for (const q of s.questions) {
      if (q.label || q.text !== s.prompt) body.push(p(`${q.label} ${q.text}`.trim(), 'Question'));
      const value = answers.get(q.key) ?? null;
      if (s.options.length) body.push(p(s.options.map((o) => `${o.value === value ? '[x]' : '[ ]'} ${o.label}`).join('   ')));
      body.push(p(value === null ? 'Response: Unanswered' : s.responseType === 'text' ? `Response: ${value}` :
        `Selected response: ${s.options.find((o) => o.value === value)!.label}`, 'Response'));
    }
  }
  if (report.essay.trim()) body.push(p('Student-written essay / objectives', 'Heading2'), p(report.essay, 'Response'));
  body.push(p(`Reference: ${OFFICIAL_COLLEGE_REPORT.reference}`));
  return body.join('');
}
