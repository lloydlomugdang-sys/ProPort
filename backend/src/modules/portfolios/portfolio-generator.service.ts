import { Buffer } from 'node:buffer';
import type { Types } from 'mongoose';
import { PDFDocument, PDFDict, PDFName, degrees, rgb, type PDFEmbeddedPage, type PDFImage } from 'pdf-lib';
import { AppError } from '../../common/errors/app-error.js';
import type { DocumentRecord } from '../../database/repositories/document.repository.js';
import { createRepositories } from '../../database/repositories/index.js';
import { CATEGORY_SEEDS } from '../../database/seeds/categories.seed.js';
import type { DatabaseConnection } from '../../infrastructure/database/database-connection.js';
import type { ObjectStorage } from '../../infrastructure/storage/object-storage.js';
import { CollegeReportService, type OfficialReportView } from '../college-report/college-report.service.js';
import { collegeReportPages, drawCollegeReportPage, type QuestionnairePage } from '../college-report/college-report.pdf.js';
import { generatePortfolioDocx } from './portfolio-docx.js';
import { exportDescription } from '../documents/description-source.js';
import { measureExport, type ExportObserver } from './export-metrics.js';
import { flattenExportForm } from './flatten-export-form.js';
import { drawStandardTitlePage, planStandardTitlePages, type StandardTitlePagePlan } from './portfolio-title-page.js';
import {
  CONTENT_WIDTH, PORTFOLIO_LAYOUT as L, TEXT_LINES_PER_PAGE, fitPortfolioArtifact,
  loadPortfolioFallbackFonts, wrapPortfolioText,
  type PortfolioFontLoader, type TextLine,
} from './portfolio-layout.js';

export const MAX_PORTFOLIO_TOTAL_SOURCE_BYTES = 50 * 1024 * 1024;
export const MAX_PORTFOLIO_TOTAL_PAGES = 150;
export const MAX_PORTFOLIO_DOCUMENTS = 500;
const MAX_ARTIFACT_FILE_BYTES = 15 * 1024 * 1024;
const PRIMARY = rgb(0.086, 0.376, 0.533);

export interface PortfolioExportInfo {
  readonly fullName: string;
  readonly yearAndSection: string;
  readonly schedule: string;
  readonly instructorName: string;
  readonly course?: string;
  readonly courseCode?: string;
  readonly semesterAndYear?: string;
}

type Attachment = Pick<DocumentRecord, 'objectKey' | 'fileKind' | 'sizeBytes'>;
interface Item { readonly document: DocumentRecord; readonly attachments: readonly Attachment[] }
interface Subsection { readonly key: string; readonly name: string; readonly items: Item[] }
interface Section { readonly key: string; readonly name: string; readonly subsections: Subsection[] }
type PlannedPage =
  | StandardTitlePagePlan
  | { readonly kind: 'questionnaire'; readonly plan: QuestionnairePage }
  | { readonly kind: 'text'; readonly lines: readonly TextLine[]; readonly centered?: boolean }
  | { readonly kind: 'image'; readonly image: PDFImage; readonly lines: readonly TextLine[] }
  | { readonly kind: 'pdf'; readonly page: PDFEmbeddedPage; readonly rotation: number };
interface TocEntry { readonly title: string; readonly pageIndex: number; readonly level: number }
interface TocLine extends TextLine { readonly target?: number }

function tooLarge(detail: string): AppError {
  return new AppError(413, 'PORTFOLIO_TOO_LARGE',
    `Your portfolio is too large to generate in one export. ${detail}`);
}

/** Uses the existing taxonomy; legacy folders stay under their known category. */
export function planPortfolioSections(documents: readonly DocumentRecord[]): Section[] {
  const sections: Section[] = [
    ...[...CATEGORY_SEEDS].sort((a, b) => a.sortOrder - b.sortOrder).map((category) => ({
      key: category.key,
      name: category.key === 'scholastic-record'
        ? "Unofficial TOR - Bachelor's Degree with Reflection" : category.name,
      subsections: [] as Subsection[],
    })),
  ];
  for (const document of documents) {
    const categoryKey = document.categoryKey === 'cv' ? 'curriculum-vitae' : document.categoryKey;
    const category = CATEGORY_SEEDS.find((value) => value.key === categoryKey);
    if (!category) {
      // Originals remain untouched. Refuse an incomplete/misclassified export.
      throw new AppError(422, 'PORTFOLIO_CATEGORY_UNSUPPORTED',
        'A document has an unsupported category. Review its category before exporting; no source files have been changed.');
    }
    const sectionKey = categoryKey;
    const section = sections.find((value) => value.key === sectionKey)!;
    let subsection = section.subsections.find((value) => value.key === document.folderKey);
    if (!subsection) {
      const folder = category.folders.find((value) => value.key === document.folderKey);
      subsection = {
        key: document.folderKey,
        name: document.folderKey === 'seminars' ? 'Seminars (Onsite)' :
          folder?.name ?? document.folderKey.split('-').map((part) =>
            part.charAt(0).toUpperCase() + part.slice(1)).join(' '),
        items: [],
      };
      section.subsections.push(subsection);
    }
    subsection.items.push({
      document,
      attachments: document.attachments?.length
        ? [...document.attachments].sort((a, b) => a.order - b.order)
        : [document],
    });
  }
  for (const section of sections) {
    const creative = section.subsections.find(s => s.key === 'creative-title');
    if (creative && (creative.items.length !== 1 || creative.items[0]!.attachments.length !== 1)) {
      throw new AppError(422, 'PORTFOLIO_CREATIVE_TITLE_AMBIGUOUS',
        `Keep one single-page Creative Title for ${section.name} before exporting. No uploaded evidence has been omitted or changed.`);
    }
    const folders = CATEGORY_SEEDS.find((value) => value.key === section.key)?.folders ?? [];
    const rank = (key: string) => folders.find((value) => value.key === key)?.sortOrder ?? Number.MAX_SAFE_INTEGER;
    section.subsections.sort((a, b) => rank(a.key) - rank(b.key) || a.key.localeCompare(b.key));
    for (const subsection of section.subsections) {
      subsection.items.sort((a, b) =>
        new Date(a.document.documentDate).getTime() - new Date(b.document.documentDate).getTime() ||
        new Date(a.document.createdAt).getTime() - new Date(b.document.createdAt).getTime() ||
        a.document._id.toString().localeCompare(b.document._id.toString()));
    }
  }
  return sections.filter((section) => section.subsections.length > 0);
}

export class PortfolioGeneratorService {
  constructor(
    private readonly database: DatabaseConnection | undefined,
    private readonly storage: ObjectStorage,
    private readonly loadFonts: PortfolioFontLoader = loadPortfolioFallbackFonts,
    private readonly observe?: ExportObserver,
  ) {}

  async generate(ownerId: Types.ObjectId, info: PortfolioExportInfo, format: 'pdf' | 'docx' = 'pdf'): Promise<Buffer> {
    const recordStart = performance.now();
    const repositories = this.repositories();
    const repository = repositories.documents;
    // Header facts come from the authenticated owner, never request fields or
    // another user's portfolio. Existing seven-field API/persistence is unchanged.
    const user = await repositories.users.findById(ownerId);
    const documents: DocumentRecord[] = [];
    let afterId: Types.ObjectId | undefined;
    for (;;) {
      const batch = await repository.listPortfolioBatchForOwner(ownerId, afterId);
      documents.push(...batch);
      if (documents.length > MAX_PORTFOLIO_DOCUMENTS) {
        throw tooLarge(`At most ${MAX_PORTFOLIO_DOCUMENTS} documents can be exported at once.`);
      }
      if (batch.length < 100) break;
      afterId = batch[batch.length - 1]!._id;
    }
    const { report } = await new CollegeReportService(this.database!).current(ownerId);
    this.observe?.('records', performance.now() - recordStart);
    if (format === 'docx') return generatePortfolioDocx(documents, info, report, user?.program ?? '',
      (key) => this.fetchArtifactBytes(key), this.observe);
    return this.generateFromDocuments(documents, info, report, user?.program ?? '');
  }

  async generateFromDocuments(documents: readonly DocumentRecord[], info: PortfolioExportInfo, collegeReport: OfficialReportView | null = null, program = ''): Promise<Buffer> {
    if (documents.length > MAX_PORTFOLIO_DOCUMENTS) {
      throw tooLarge(`At most ${MAX_PORTFOLIO_DOCUMENTS} documents can be exported at once.`);
    }
    const sections = planPortfolioSections(documents);
    if (collegeReport && !sections.some((section) => section.key === 'college-report')) {
      sections.push({ key: 'college-report', name: 'College Report', subsections: [] });
    }
    const sourceBytes = sections.flatMap((s) => s.subsections.flatMap((sub) =>
      sub.items.flatMap((item) => item.attachments))).reduce((sum, att) => sum + att.sizeBytes, 0);
    if (sourceBytes > MAX_PORTFOLIO_TOTAL_SOURCE_BYTES) {
      throw tooLarge('Reduce source file sizes to a combined 50 MiB or less.');
    }
    const pdf = await PDFDocument.create();
    pdf.setTitle('GradPort Academic Portfolio');
    pdf.setAuthor(info.fullName);
    pdf.setCreator('GradPort Portfolio Builder');
    const fonts = await measureExport('fonts', this.observe, () => this.loadFonts(pdf));
    const pages: PlannedPage[] = [];
    const entries: TocEntry[] = [];
    let actualBytes = 0;

    const addPage = (page: PlannedPage) => {
      pages.push(page);
      if (pages.length > MAX_PORTFOLIO_TOTAL_PAGES) {
        throw tooLarge('The maximum is 150 pages including front matter. Reduce the document/page count.');
      }
    };
    const lines = (text: string, bold = false): TextLine[] =>
      wrapPortfolioText(text, bold ? fonts.bold : fonts.regular).map((text) => ({ text, bold, indent: 0 }));
    const addTextPages = (content: readonly TextLine[], centered = false) => {
      for (let start = 0; start < content.length;) {
        let end = Math.min(start + TEXT_LINES_PER_PAGE, content.length);
        if (end < content.length) {
          // Keep a wrapped heading with the first body line where possible.
          while (end > start && content[end - 1]!.bold) end--;
          if (end === start) end = start + TEXT_LINES_PER_PAGE;
        }
        addPage({ kind: 'text', lines: content.slice(start, end), centered });
        start = end;
      }
    };
    // Pass 1: measure all text and artifact pages using the same fonts as rendering.
    for (const page of await planStandardTitlePages(pdf, info, fonts, program)) addPage(page);

    const planSection = async (section: Section) => {
      entries.push({ title: section.name, pageIndex: pages.length, level: 0 });
      // Creative Title is the supplied document itself, not an invented cover.
      // The saved creative-title artifact (if present) is the section's cover.
      // No invented heading-only page and no generated metadata before evidence.
      for (const sub of section.subsections) {
        if (sub.key !== 'creative-title' &&
            (section.key === 'certificates' || section.key === 'accomplishments' || section.subsections.length > 1)) {
          entries.push({ title: sub.name, pageIndex: pages.length, level: 1 });
        }
        for (const item of sub.items) {
          const doc = item.document;
          if (doc.title !== section.name && doc.title !== sub.name) entries.push({ title: doc.title, pageIndex: pages.length, level: 2 });
          const description = exportDescription(doc);
          const metadata = [
            ...(description ? [...lines('Description', true), ...lines(description)] : []),
            ...(doc.reflection?.trim() ? [...lines('Student Reflection', true), ...lines(doc.reflection)] : []),
          ];
          for (const attachment of item.attachments) {
            const bytes = await measureExport('storage', this.observe, () => this.fetchArtifactBytes(attachment.objectKey));
            const artifactStart = performance.now();
            actualBytes += bytes.length;
            if (actualBytes > MAX_PORTFOLIO_TOTAL_SOURCE_BYTES) {
              throw tooLarge('Reduce source file sizes to a combined 50 MiB or less.');
            }
            if (attachment.fileKind === 'pdf') {
              try {
                const source = await PDFDocument.load(bytes);
                flattenExportForm(source);
                if (source.getPageCount() === 0) throw new Error('Empty PDF');
                if (sub.key === 'creative-title' && source.getPageCount() !== 1) throw new AppError(422,
                  'PORTFOLIO_CREATIVE_TITLE_AMBIGUOUS', 'A Creative Title must be one page. Review the uploaded title; no source pages were omitted.');
                if (pages.length + source.getPageCount() > MAX_PORTFOLIO_TOTAL_PAGES) {
                  throw tooLarge('The maximum is 150 pages including front matter. Reduce the document/page count.');
                }
                for (const page of source.getPages()) {
                  // Embedding page content does not paint annotation appearances.
                  // Do not silently lose entered form answers, stamps or ink.
                  const hasVisibleAnnotations = page.node.Annots()?.asArray().some((ref) => {
                    const annotation = source.context.lookup(ref);
                    // Flatteners can leave dangling references to removed widgets.
                    // Only surviving dictionaries can have visible appearances.
                    return annotation instanceof PDFDict &&
                      annotation.get(PDFName.of('Subtype'))?.toString() !== '/Link';
                  });
                  if (hasVisibleAnnotations) {
                    throw new AppError(422, 'PORTFOLIO_ARTIFACT_UNSUPPORTED',
                      'A PDF contains unsupported annotations. Open it in a PDF reader, print to PDF with visible annotations, and upload that copy. Your original file is unchanged.');
                  }
                  // Preserve the source's visible page boundary, including a
                  // pre-existing CropBox, rather than revealing hidden margins.
                  const media = page.getMediaBox();
                  const crop = page.getCropBox();
                  const left = Math.max(media.x, crop.x);
                  const bottom = Math.max(media.y, crop.y);
                  const right = Math.min(media.x + media.width, crop.x + crop.width);
                  const top = Math.min(media.y + media.height, crop.y + crop.height);
                  if (right <= left || top <= bottom) throw new Error('Invalid page boundary');
                  const embedded = await pdf.embedPage(page, {
                    left, bottom, right, top,
                  });
                  addPage({ kind: 'pdf', page: embedded, rotation: ((page.getRotation().angle % 360) + 360) % 360 });
                }
              } catch (error) {
                if (error instanceof AppError) throw error;
                throw new AppError(422, 'PORTFOLIO_ARTIFACT_CORRUPT', 'This portfolio file could not be processed.');
              }
            } else {
              try {
                const normalized = new Uint8Array(bytes);
                const image = bytes.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47]))
                  ? await pdf.embedPng(normalized) : await pdf.embedJpg(normalized);
                addPage({ kind: 'image', image, lines: [] });
              } catch (error) {
                if (error instanceof AppError) throw error;
                throw new AppError(422, 'PORTFOLIO_ARTIFACT_CORRUPT', 'This portfolio file could not be processed.');
              }
            }
            this.observe?.(attachment.fileKind === 'pdf' ? 'pdf-evidence' : 'image-evidence', performance.now() - artifactStart);
          }
          if (metadata.length) addTextPages(metadata);
        }
      }
    };
    const tocIndex = pages.length;
    for (const section of sections) {
      await planSection(section);
      if (section.key === 'college-report' && collegeReport) {
        for (const plan of await measureExport('questionnaire-plan', this.observe, () => collegeReportPages(collegeReport, fonts))) addPage({ kind: 'questionnaire', plan });
      }
    }

    // Wrapped TOC rows reserve a fixed page-number column. Page-number digits do
    // not affect wrapping, so the resulting page count is stable in two passes.
    const tocPages: TocLine[][] = [[]];
    for (const entry of entries) {
      const indent = entry.level * 12;
      const wrapped = wrapPortfolioText(entry.title, entry.level < 2 ? fonts.bold : fonts.regular,
        CONTENT_WIDTH - indent - 36);
      const currentToc = tocPages[tocPages.length - 1]!;
      const rowCapacity = TEXT_LINES_PER_PAGE - 2;
      const followingLine = entry.level < 2 ? 1 : 0;
      if (currentToc.length && wrapped.length + followingLine <= rowCapacity &&
          currentToc.length + wrapped.length + followingLine > rowCapacity) {
        tocPages.push([]); // Do not strand an ordinary wrapped TOC row across pages.
      }
      for (const [index, text] of wrapped.entries()) {
        let page = tocPages[tocPages.length - 1]!;
        if (page.length >= TEXT_LINES_PER_PAGE - 2) {
          page = [];
          tocPages.push(page);
        }
        page.push({ text, bold: entry.level < 2, indent,
          ...(index === 0 ? { target: entry.pageIndex } : {}) });
      }
    }
    if (pages.length + tocPages.length > MAX_PORTFOLIO_TOTAL_PAGES) {
      throw tooLarge('The maximum is 150 pages including front matter. Reduce the document/page count.');
    }

    // Pass 2: insert the measured TOC after Standard Title; each Creative Title
    // remains inside its category immediately before that category's evidence.
    const drawLines = (page: ReturnType<PDFDocument['addPage']>, content: readonly TextLine[], centered = false) => {
      content.forEach((line, index) => {
        if (line.questionnaire) page.drawRectangle({ x: L.left,
          y: page.getHeight() - L.top - (index + 1) * L.lineHeight + 4,
          width: CONTENT_WIDTH, height: L.lineHeight,
          color: line.questionnaire === 'section' ? rgb(0.9, 0.93, 0.95) : rgb(0.96, 0.96, 0.96) });
        page.drawText(line.text, {
        x: centered ? L.left + (CONTENT_WIDTH - (line.bold ? fonts.bold : fonts.regular).widthOfTextAtSize(line.text, L.bodySize)) / 2 : L.left + line.indent,
        y: page.getHeight() - L.top - L.bodySize - index * L.lineHeight,
        size: L.bodySize, font: line.bold ? fonts.bold : fonts.regular,
        ...(line.questionnaire ? { color: rgb(0, 0, 0) } : line.bold ? { color: PRIMARY } : {}),
      });
      });
    };
    const footer = (page: ReturnType<PDFDocument['addPage']>) => page.drawText(`Page ${pdf.getPageCount()}`, {
      x: L.left, y: L.bottom + L.bodySize, size: L.bodySize, font: fonts.regular,
    });
    for (let index = 0; index <= pages.length; index++) {
      if (index === tocIndex) {
        for (const tocLines of tocPages) {
          const page = pdf.addPage([L.width, L.height]);
          drawLines(page, [...lines('TABLE OF CONTENTS', true), ...lines(''), ...tocLines]);
          tocLines.forEach((line, row) => {
            if (line.target === undefined) return;
            const target = String(line.target + 1 + (line.target >= tocIndex ? tocPages.length : 0));
            page.drawText(target, {
              x: L.width - L.right - fonts.regular.widthOfTextAtSize(target, L.bodySize),
              y: L.height - L.top - L.bodySize - (row + 2) * L.lineHeight,
              size: L.bodySize, font: fonts.regular,
            });
          });
          footer(page);
        }
      }
      const planned = pages[index];
      if (!planned) break;
      if (planned.kind === 'pdf') {
        const rotated = planned.rotation === 90 || planned.rotation === 270;
        const width = rotated ? planned.page.height : planned.page.width;
        const height = rotated ? planned.page.width : planned.page.height;
        const landscape = width > height;
        const page = pdf.addPage(landscape ? [L.height, L.width] : [L.width, L.height]);
        const fit = fitPortfolioArtifact(width, height, page.getWidth(), page.getHeight());
        page.drawPage(planned.page, {
          x: fit.x + (planned.rotation === 180 || planned.rotation === 270 ? fit.width : 0),
          y: fit.y + (planned.rotation === 90 || planned.rotation === 180 ? fit.height : 0),
          width: planned.page.width * fit.scale, height: planned.page.height * fit.scale,
          rotate: degrees(-planned.rotation),
        });
      } else {
        const page = pdf.addPage([L.width, L.height]);
        if (planned.kind === 'title') drawStandardTitlePage(page, planned, fonts);
        else if (planned.kind === 'questionnaire') drawCollegeReportPage(page, planned.plan, fonts);
        else drawLines(page, planned.lines, planned.kind === 'text' && planned.centered);
        if (planned.kind === 'image') {
          const fit = fitPortfolioArtifact(planned.image.width, planned.image.height, L.width, L.height,
            planned.lines.length * L.lineHeight + L.bodySize, L.lineHeight + L.bodySize);
          // Leave the footer's line free as well as the measured caption.
          page.drawImage(planned.image, fit);
        }
        footer(page);
      }
    }
    return Buffer.from(await measureExport('pdf-save', this.observe, () => pdf.save()));
  }

  private async fetchArtifactBytes(objectKey: string): Promise<Buffer> {
    try {
      const stream = await this.storage.get(objectKey);
      const chunks: Buffer[] = [];
      let total = 0;
      for await (const chunk of stream) {
        const buffer = Buffer.isBuffer(chunk) ? chunk :
          typeof chunk === 'string' || chunk instanceof Uint8Array ? Buffer.from(chunk) : null;
        if (!buffer) throw new Error('Unreadable stream');
        total += buffer.length;
        if (total > MAX_ARTIFACT_FILE_BYTES) throw tooLarge('Each source file must be 15 MiB or less.');
        chunks.push(buffer);
      }
      return Buffer.concat(chunks, total);
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError(422, 'PORTFOLIO_ARTIFACT_MISSING', 'One of your portfolio files could not be retrieved.');
    }
  }

  private repositories() {
    const connection = this.database?.mongooseConnection;
    if (this.database?.status !== 'connected' || connection === undefined) {
      throw new AppError(503, 'DOCUMENT_UNAVAILABLE', 'Database is temporarily unavailable.');
    }
    return createRepositories(connection);
  }
}
