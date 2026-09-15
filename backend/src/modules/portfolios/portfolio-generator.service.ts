import { Buffer } from 'node:buffer';
import type { Readable } from 'node:stream';
import type { Types } from 'mongoose';
import { PDFDocument, StandardFonts, rgb, type PDFPage, type PDFFont, type PDFImage } from 'pdf-lib';
import { AppError } from '../../common/errors/app-error.js';
import type { DocumentRecord } from '../../database/repositories/document.repository.js';
import { createRepositories } from '../../database/repositories/index.js';
import type { DatabaseConnection } from '../../infrastructure/database/database-connection.js';
import type { ObjectStorage } from '../../infrastructure/storage/object-storage.js';

export const MAX_PORTFOLIO_TOTAL_SOURCE_BYTES = 50 * 1024 * 1024; // 50 MB
export const MAX_PORTFOLIO_TOTAL_PAGES = 150;
const MAX_ARTIFACT_FILE_BYTES = 15 * 1024 * 1024; // 15 MB

const PAGE_WIDTH = 595.28; // Standard A4 width in points
const PAGE_HEIGHT = 841.89; // Standard A4 height in points

const COLOR_PRIMARY = rgb(0.086, 0.376, 0.533); // #166088
const COLOR_SECONDARY = rgb(0.047, 0.208, 0.306); // #0C354E
const COLOR_TEXT_PRIMARY = rgb(0.12, 0.14, 0.17); // #1F242B
const COLOR_TEXT_MUTED = rgb(0.40, 0.45, 0.50); // #667380
const COLOR_DIVIDER = rgb(0.85, 0.88, 0.90);
const COLOR_SURFACE = rgb(0.96, 0.97, 0.98);

export interface PortfolioExportInfo {
  readonly fullName: string;
  readonly yearAndSection: string;
  readonly schedule: string;
  readonly instructorName: string;
  readonly course?: string;
  readonly courseCode?: string;
  readonly semesterAndYear?: string;
}

interface PortfolioItemAttachment {
  readonly id: string;
  readonly originalFileName: string;
  readonly objectKey: string;
  readonly mimeType: string;
  readonly fileKind: 'image' | 'pdf';
  readonly extension: string;
  readonly sizeBytes: number;
  readonly order: number;
}

interface PortfolioPlannedItem {
  readonly document: DocumentRecord;
  readonly attachments: readonly PortfolioItemAttachment[];
}

interface PortfolioPlannedSubsection {
  readonly folderKey: string;
  readonly folderName: string;
  readonly items: readonly PortfolioPlannedItem[];
}

interface PortfolioPlannedSection {
  readonly sectionKey: string;
  readonly sectionName: string;
  readonly sortOrder: number;
  readonly subsections: readonly PortfolioPlannedSubsection[];
}

interface TocEntry {
  readonly title: string;
  readonly pageNumber: number;
  readonly isSection: boolean;
  readonly isSubsection: boolean;
}

// Canonical section metadata matching CATEGORY_SEEDS
const SECTION_DEFINITIONS: readonly {
  readonly key: string;
  readonly name: string;
  readonly sortOrder: number;
}[] = [
  { key: 'creative-title', name: 'Creative Title', sortOrder: 5 },
  { key: 'curriculum-vitae', name: 'Curriculum Vitae', sortOrder: 10 },
  { key: 'scholastic-record', name: 'Scholastic Record', sortOrder: 20 },
  { key: 'certificates', name: 'Certificates', sortOrder: 30 },
  { key: 'accomplishments', name: 'Accomplishments', sortOrder: 40 },
  { key: 'other-achievements', name: 'Other Achievements', sortOrder: 50 },
  { key: 'college-report', name: 'College Report', sortOrder: 60 },
] as const;

export class PortfolioGeneratorService {
  constructor(
    private readonly database: DatabaseConnection | undefined,
    private readonly storage: ObjectStorage,
  ) {}

  async generate(
    ownerId: Types.ObjectId,
    info: PortfolioExportInfo,
  ): Promise<Buffer> {
    const repositories = this.repositories();
    const documents = await repositories.documents.listForOwner(ownerId, 500);
    return this.generateFromDocuments(documents, info);
  }

  async generateFromDocuments(
    documents: readonly DocumentRecord[],
    info: PortfolioExportInfo,
  ): Promise<Buffer> {
    // Build the planned sections hierarchy
    const sections = this.buildPlannedSections(documents);

    // Check total source bytes before heavy processing
    let estimatedTotalBytes = 0;
    for (const sec of sections) {
      for (const sub of sec.subsections) {
        for (const item of sub.items) {
          for (const att of item.attachments) {
            estimatedTotalBytes += att.sizeBytes;
          }
        }
      }
    }
    if (estimatedTotalBytes > MAX_PORTFOLIO_TOTAL_SOURCE_BYTES) {
      throw new AppError(
        413,
        'PORTFOLIO_TOO_LARGE',
        'Your portfolio is too large to generate in one export.',
      );
    }

    // Pass 1: Measure and compute accurate page numbers
    const { tocEntries } = await this.calculatePageMap(sections);

    // Pass 2: Build the canonical PDF
    const pdfDoc = await PDFDocument.create();
    pdfDoc.setTitle('GradPort Academic Portfolio');
    pdfDoc.setAuthor(info.fullName || 'GradPort Student');
    pdfDoc.setCreator('GradPort Portfolio Builder');

    const fontRegular = await pdfDoc.embedFont(StandardFonts.Helvetica);
    const fontBold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);
    const fontOblique = await pdfDoc.embedFont(StandardFonts.HelveticaOblique);

    const fonts = { regular: fontRegular, bold: fontBold, oblique: fontOblique };

    // 1. Title Page
    this.renderTitlePage(pdfDoc, info, fonts);

    // 2. Table of Contents (two-pass verified accurate page numbers)
    this.renderTableOfContents(pdfDoc, tocEntries, fonts);

    // 3. Sections, Dividers, and Actual Artifacts
    let runningPageNumber = 1 + this.calculateTocPageCount(tocEntries.length);

    for (const section of sections) {
      if (section.subsections.every((sub) => sub.items.length === 0)) {
        continue;
      }

      // Section Divider Page
      runningPageNumber++;
      this.renderSectionDivider(pdfDoc, section.sectionName, fonts, runningPageNumber);

      for (const subsection of section.subsections) {
        for (const item of subsection.items) {
          for (let attIndex = 0; attIndex < item.attachments.length; attIndex++) {
            const attachment = item.attachments[attIndex];
            if (!attachment) continue;
            const isFirstAttachment = attIndex === 0;

            const artifactBytes = await this.fetchArtifactBytes(attachment.objectKey);

            if (attachment.fileKind === 'pdf') {
              // Uploaded PDF: Copy actual vector pages from uploaded PDF
              let sourcePdf: PDFDocument;
              try {
                sourcePdf = await PDFDocument.load(artifactBytes, { ignoreEncryption: true });
              } catch {
                throw new AppError(
                  422,
                  'PORTFOLIO_ARTIFACT_CORRUPT',
                  'This portfolio file could not be processed.',
                );
              }

              // Metadata cover sheet if description or reflection exists
              const hasMetadata =
                (item.document.description && item.document.description.trim().length > 0) ||
                (item.document.reflection && item.document.reflection.trim().length > 0);

              if (hasMetadata && isFirstAttachment) {
                runningPageNumber++;
                this.renderDocumentMetadataSheet(
                  pdfDoc,
                  item.document,
                  subsection.folderName,
                  fonts,
                  runningPageNumber,
                );
              }

              const pageIndices = sourcePdf.getPageIndices();
              const copiedPages = await pdfDoc.copyPages(sourcePdf, pageIndices);
              for (const copiedPage of copiedPages) {
                runningPageNumber++;
                pdfDoc.addPage(copiedPage);
              }
            } else {
              // Image artifact (JPG / PNG): Embed actual image with aspect ratio preserved
              runningPageNumber++;
              await this.renderImageArtifactPage(
                pdfDoc,
                item.document,
                attachment,
                artifactBytes,
                attIndex,
                item.attachments.length,
                subsection.folderName,
                fonts,
                runningPageNumber,
              );
            }

            if (runningPageNumber > MAX_PORTFOLIO_TOTAL_PAGES) {
              throw new AppError(
                413,
                'PORTFOLIO_TOO_LARGE',
                'Your portfolio is too large to generate in one export.',
              );
            }
          }
        }
      }
    }

    const savedBytes = await pdfDoc.save();
    return Buffer.from(savedBytes);
  }

  private buildPlannedSections(
    documents: readonly DocumentRecord[],
  ): readonly PortfolioPlannedSection[] {
    // 1. Separate documents into their canonical section categories
    const creativeTitleItems: PortfolioPlannedItem[] = [];
    const sectionGroups = new Map<string, Map<string, PortfolioPlannedItem[]>>();

    for (const def of SECTION_DEFINITIONS) {
      if (def.key !== 'creative-title') {
        sectionGroups.set(def.key, new Map());
      }
    }

    for (const doc of documents) {
      const attachments = this.resolveAttachments(doc);
      const plannedItem: PortfolioPlannedItem = { document: doc, attachments };

      if (doc.folderKey === 'creative-title') {
        creativeTitleItems.push(plannedItem);
      } else {
        const catKey = doc.categoryKey === 'cv' ? 'curriculum-vitae' : doc.categoryKey;
        const catMap = sectionGroups.get(catKey);
        if (catMap !== undefined) {
          const list = catMap.get(doc.folderKey) ?? [];
          list.push(plannedItem);
          catMap.set(doc.folderKey, list);
        }
      }
    }

    // Sort items within subsections deterministically:
    // documentDate ascending, then createdAt ascending, then _id
    const sortItems = (items: PortfolioPlannedItem[]) => {
      items.sort((left, right) => {
        const leftTime = left.document.documentDate instanceof Date
          ? left.document.documentDate.getTime()
          : new Date(left.document.documentDate).getTime();
        const rightTime = right.document.documentDate instanceof Date
          ? right.document.documentDate.getTime()
          : new Date(right.document.documentDate).getTime();
        const dateDiff = leftTime - rightTime;
        if (dateDiff !== 0) return dateDiff;
        const leftCreated = left.document.createdAt ? new Date(left.document.createdAt).getTime() : 0;
        const rightCreated = right.document.createdAt ? new Date(right.document.createdAt).getTime() : 0;
        const createdDiff = leftCreated - rightCreated;
        if (createdDiff !== 0) return createdDiff;
        return left.document._id.toString().localeCompare(right.document._id.toString());
      });
    };

    sortItems(creativeTitleItems);

    const plannedSections: PortfolioPlannedSection[] = [];

    // Creative Title Section
    if (creativeTitleItems.length > 0) {
      plannedSections.push({
        sectionKey: 'creative-title',
        sectionName: 'Creative Title',
        sortOrder: 5,
        subsections: [
          {
            folderKey: 'creative-title',
            folderName: 'Creative Title',
            items: creativeTitleItems,
          },
        ],
      });
    }

    // Other categories in canonical sort order
    for (const def of SECTION_DEFINITIONS) {
      if (def.key === 'creative-title') continue;
      const catMap = sectionGroups.get(def.key);
      if (catMap === undefined) continue;

      const subsections: PortfolioPlannedSubsection[] = [];
      for (const [folderKey, items] of catMap.entries()) {
        if (items.length === 0) continue;
        sortItems(items);
        subsections.push({
          folderKey,
          folderName: this.humanizeFolderName(folderKey),
          items,
        });
      }

      if (subsections.length > 0) {
        plannedSections.push({
          sectionKey: def.key,
          sectionName: def.name,
          sortOrder: def.sortOrder,
          subsections,
        });
      }
    }

    return plannedSections;
  }

  private resolveAttachments(doc: DocumentRecord): readonly PortfolioItemAttachment[] {
    if (doc.attachments && doc.attachments.length > 0) {
      const sorted = [...doc.attachments].sort((a, b) => a.order - b.order);
      return sorted.map((a) => ({
        id: a.id,
        originalFileName: a.originalFileName,
        objectKey: a.objectKey,
        mimeType: a.mimeType,
        fileKind: a.fileKind,
        extension: a.extension,
        sizeBytes: a.sizeBytes,
        order: a.order,
      }));
    }
    return [
      {
        id: '1',
        originalFileName: doc.originalFileName,
        objectKey: doc.objectKey,
        mimeType: doc.mimeType,
        fileKind: doc.fileKind as 'image' | 'pdf',
        extension: doc.extension,
        sizeBytes: doc.sizeBytes,
        order: 0,
      },
    ];
  }

  private humanizeFolderName(folderKey: string): string {
    const knownNames: Record<string, string> = {
      'curriculum-vitae': 'Curriculum Vitae',
      'unofficial-tor-with-reflections': 'Unofficial TOR with Reflections',
      'seminars': 'Seminars',
      'other-seminars': 'Other Seminars',
      'trainings': 'Trainings',
      'thesis-capstone': 'Thesis / Capstone',
      'case-studies': 'Case Studies',
      'projects': 'Projects',
      'assessments': 'Assessments',
      'college-report': 'College Report',
      'creative-title': 'Creative Title',
    };
    return knownNames[folderKey] ?? folderKey.split('-').map((s) => s.charAt(0).toUpperCase() + s.slice(1)).join(' ');
  }

  private calculateTocPageCount(entryCount: number): number {
    return Math.max(1, Math.ceil(entryCount / 22));
  }

  private async calculatePageMap(
    sections: readonly PortfolioPlannedSection[],
  ): Promise<{
    readonly tocEntries: readonly TocEntry[];
    readonly itemPageMap: ReadonlyMap<string, number>;
  }> {
    const preliminaryEntries: {
      readonly title: string;
      readonly isSection: boolean;
      readonly isSubsection: boolean;
      readonly key: string;
      pagesContributed: number;
    }[] = [];

    // Measure pages for each item
    for (const section of sections) {
      if (section.subsections.every((sub) => sub.items.length === 0)) continue;

      preliminaryEntries.push({
        title: section.sectionName,
        isSection: true,
        isSubsection: false,
        key: `sec:${section.sectionKey}`,
        pagesContributed: 1, // Section Divider
      });

      for (const subsection of section.subsections) {
        if (section.subsections.length > 1) {
          preliminaryEntries.push({
            title: subsection.folderName,
            isSection: false,
            isSubsection: true,
            key: `sub:${section.sectionKey}:${subsection.folderKey}`,
            pagesContributed: 0,
          });
        }

        for (const item of subsection.items) {
          let itemPages = 0;
          for (let attIndex = 0; attIndex < item.attachments.length; attIndex++) {
            const att = item.attachments[attIndex];
            if (!att) continue;
            if (att.fileKind === 'pdf') {
              const artifactBytes = await this.fetchArtifactBytes(att.objectKey);
              try {
                const sourcePdf = await PDFDocument.load(artifactBytes, { ignoreEncryption: true });
                const hasMetadata =
                  (item.document.description && item.document.description.trim().length > 0) ||
                  (item.document.reflection && item.document.reflection.trim().length > 0);
                if (hasMetadata && attIndex === 0) {
                  itemPages += 1;
                }
                itemPages += sourcePdf.getPageCount();
              } catch {
                throw new AppError(
                  422,
                  'PORTFOLIO_ARTIFACT_CORRUPT',
                  'This portfolio file could not be processed.',
                );
              }
            } else {
              itemPages += 1;
            }
          }

          preliminaryEntries.push({
            title: item.document.title,
            isSection: false,
            isSubsection: false,
            key: `doc:${item.document._id.toString()}`,
            pagesContributed: itemPages,
          });
        }
      }
    }

    const tocPageCount = this.calculateTocPageCount(preliminaryEntries.length);
    let currentPage = 1 + tocPageCount + 1; // Title page is 1, followed by TOC pages

    const tocEntries: TocEntry[] = [];
    const itemPageMap = new Map<string, number>();

    for (const entry of preliminaryEntries) {
      tocEntries.push({
        title: entry.title,
        pageNumber: currentPage,
        isSection: entry.isSection,
        isSubsection: entry.isSubsection,
      });
      itemPageMap.set(entry.key, currentPage);
      currentPage += entry.pagesContributed;
    }

    if (currentPage - 1 > MAX_PORTFOLIO_TOTAL_PAGES) {
      throw new AppError(
        413,
        'PORTFOLIO_TOO_LARGE',
        'Your portfolio is too large to generate in one export.',
      );
    }

    return { tocEntries, itemPageMap };
  }

  private async fetchArtifactBytes(objectKey: string): Promise<Buffer> {
    try {
      const stream = await this.storage.get(objectKey);
      return await readableToBoundedBuffer(stream, MAX_ARTIFACT_FILE_BYTES);
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError(
        422,
        'PORTFOLIO_ARTIFACT_MISSING',
        'One of your portfolio files could not be retrieved.',
      );
    }
  }

  private renderTitlePage(
    pdfDoc: PDFDocument,
    info: PortfolioExportInfo,
    fonts: { regular: PDFFont; bold: PDFFont; oblique: PDFFont },
  ): void {
    const page = pdfDoc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);

    // Top decorative bar
    page.drawRectangle({
      x: 0,
      y: PAGE_HEIGHT - 12,
      width: PAGE_WIDTH,
      height: 12,
      color: COLOR_PRIMARY,
    });

    // Institution Header
    const uniText = 'NEW ERA UNIVERSITY';
    const uniSize = 20;
    const uniWidth = fonts.bold.widthOfTextAtSize(uniText, uniSize);
    page.drawText(uniText, {
      x: (PAGE_WIDTH - uniWidth) / 2,
      y: PAGE_HEIGHT - 80,
      size: uniSize,
      font: fonts.bold,
      color: COLOR_PRIMARY,
    });

    const collegeText = 'College of Informatics and Computing Studies';
    const collegeSize = 12;
    const collegeWidth = fonts.regular.widthOfTextAtSize(collegeText, collegeSize);
    page.drawText(collegeText, {
      x: (PAGE_WIDTH - collegeWidth) / 2,
      y: PAGE_HEIGHT - 102,
      size: collegeSize,
      font: fonts.regular,
      color: COLOR_TEXT_MUTED,
    });

    // Subtle divider
    page.drawLine({
      start: { x: 80, y: PAGE_HEIGHT - 125 },
      end: { x: PAGE_WIDTH - 80, y: PAGE_HEIGHT - 125 },
      thickness: 1,
      color: COLOR_DIVIDER,
    });

    // Main Portfolio Title
    const titleText = 'ACADEMIC PORTFOLIO';
    const titleSize = 28;
    const titleWidth = fonts.bold.widthOfTextAtSize(titleText, titleSize);
    page.drawText(titleText, {
      x: (PAGE_WIDTH - titleWidth) / 2,
      y: PAGE_HEIGHT - 210,
      size: titleSize,
      font: fonts.bold,
      color: COLOR_SECONDARY,
    });

    const subTitle = 'Compiled Academic Requirements & Student Artifacts';
    const subSize = 11;
    const subWidth = fonts.oblique.widthOfTextAtSize(subTitle, subSize);
    page.drawText(subTitle, {
      x: (PAGE_WIDTH - subWidth) / 2,
      y: PAGE_HEIGHT - 232,
      size: subSize,
      font: fonts.oblique,
      color: COLOR_TEXT_MUTED,
    });

    // Student Info Card
    const cardX = 65;
    const cardY = PAGE_HEIGHT - 540;
    const cardWidth = PAGE_WIDTH - 130;
    const cardHeight = 270;

    page.drawRectangle({
      x: cardX,
      y: cardY,
      width: cardWidth,
      height: cardHeight,
      color: COLOR_SURFACE,
      borderColor: COLOR_DIVIDER,
      borderWidth: 1,
    });

    // Left accent bar on card
    page.drawRectangle({
      x: cardX,
      y: cardY,
      width: 4,
      height: cardHeight,
      color: COLOR_PRIMARY,
    });

    const fields: readonly [string, string][] = [
      ['Full Name', info.fullName || '—'],
      ['Year & Section', info.yearAndSection || '—'],
      ['Schedule', info.schedule || '—'],
      ["Instructor's Name", info.instructorName || '—'],
      ['Course', info.course || '—'],
      ['Course Code', info.courseCode || '—'],
      ['Semester & Academic Year', info.semesterAndYear || '—'],
    ];

    let fieldY = cardY + cardHeight - 34;
    for (const [label, val] of fields) {
      page.drawText(label, {
        x: cardX + 24,
        y: fieldY,
        size: 10,
        font: fonts.bold,
        color: COLOR_TEXT_MUTED,
      });

      page.drawText(val, {
        x: cardX + 180,
        y: fieldY,
        size: 11,
        font: fonts.regular,
        color: COLOR_TEXT_PRIMARY,
      });

      fieldY -= 32;
    }

    // Footer
    const footerText = 'Generated and verified via GradPort Academic Suite';
    const footSize = 9;
    const footWidth = fonts.oblique.widthOfTextAtSize(footerText, footSize);
    page.drawText(footerText, {
      x: (PAGE_WIDTH - footWidth) / 2,
      y: 45,
      size: footSize,
      font: fonts.oblique,
      color: COLOR_TEXT_MUTED,
    });
  }

  private renderTableOfContents(
    pdfDoc: PDFDocument,
    entries: readonly TocEntry[],
    fonts: { regular: PDFFont; bold: PDFFont; oblique: PDFFont },
  ): void {
    const entriesPerPage = 22;
    const totalTocPages = this.calculateTocPageCount(entries.length);

    for (let p = 0; p < totalTocPages; p++) {
      const page = pdfDoc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);
      const pageEntries = entries.slice(p * entriesPerPage, (p + 1) * entriesPerPage);

      // TOC Header
      page.drawText('TABLE OF CONTENTS', {
        x: 50,
        y: PAGE_HEIGHT - 65,
        size: 20,
        font: fonts.bold,
        color: COLOR_PRIMARY,
      });

      page.drawLine({
        start: { x: 50, y: PAGE_HEIGHT - 78 },
        end: { x: PAGE_WIDTH - 50, y: PAGE_HEIGHT - 78 },
        thickness: 1.5,
        color: COLOR_PRIMARY,
      });

      let entryY = PAGE_HEIGHT - 110;

      for (const item of pageEntries) {
        if (item.isSection) {
          entryY -= 6;
          page.drawText(item.title, {
            x: 50,
            y: entryY,
            size: 12,
            font: fonts.bold,
            color: COLOR_SECONDARY,
          });

          const pageNumStr = String(item.pageNumber);
          const numWidth = fonts.bold.widthOfTextAtSize(pageNumStr, 12);
          page.drawText(pageNumStr, {
            x: PAGE_WIDTH - 50 - numWidth,
            y: entryY,
            size: 12,
            font: fonts.bold,
            color: COLOR_SECONDARY,
          });
          entryY -= 20;
        } else if (item.isSubsection) {
          page.drawText(item.title, {
            x: 68,
            y: entryY,
            size: 10,
            font: fonts.bold,
            color: COLOR_TEXT_MUTED,
          });
          entryY -= 16;
        } else {
          // Document item with dotted leader line
          const displayTitle = item.title.length > 52 ? `${item.title.substring(0, 50)}...` : item.title;
          page.drawText(displayTitle, {
            x: 82,
            y: entryY,
            size: 10,
            font: fonts.regular,
            color: COLOR_TEXT_PRIMARY,
          });

          const pageNumStr = String(item.pageNumber);
          const numWidth = fonts.regular.widthOfTextAtSize(pageNumStr, 10);
          page.drawText(pageNumStr, {
            x: PAGE_WIDTH - 50 - numWidth,
            y: entryY,
            size: 10,
            font: fonts.regular,
            color: COLOR_TEXT_PRIMARY,
          });

          // Draw dotted leader
          const titleWidth = fonts.regular.widthOfTextAtSize(displayTitle, 10);
          const dotStartX = 82 + titleWidth + 8;
          const dotEndX = PAGE_WIDTH - 50 - numWidth - 8;
          if (dotEndX > dotStartX) {
            const dots = '. '.repeat(Math.floor((dotEndX - dotStartX) / 6));
            page.drawText(dots, {
              x: dotStartX,
              y: entryY,
              size: 8,
              font: fonts.regular,
              color: COLOR_DIVIDER,
            });
          }

          entryY -= 18;
        }
      }

      // Footer
      const footerPage = `Page ${1 + p + 1}`;
      page.drawText(footerPage, {
        x: PAGE_WIDTH - 80,
        y: 35,
        size: 9,
        font: fonts.regular,
        color: COLOR_TEXT_MUTED,
      });
    }
  }

  private renderSectionDivider(
    pdfDoc: PDFDocument,
    sectionName: string,
    fonts: { regular: PDFFont; bold: PDFFont; oblique: PDFFont },
    pageNumber: number,
  ): void {
    const page = pdfDoc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);

    // Top subtle brand header
    page.drawText('GRADPORT ACADEMIC PORTFOLIO', {
      x: 50,
      y: PAGE_HEIGHT - 50,
      size: 9,
      font: fonts.bold,
      color: COLOR_TEXT_MUTED,
    });

    page.drawLine({
      start: { x: 50, y: PAGE_HEIGHT - 58 },
      end: { x: PAGE_WIDTH - 50, y: PAGE_HEIGHT - 58 },
      thickness: 0.5,
      color: COLOR_DIVIDER,
    });

    // Center divider hero card
    const cardY = PAGE_HEIGHT / 2 - 80;
    page.drawRectangle({
      x: 50,
      y: cardY,
      width: PAGE_WIDTH - 100,
      height: 160,
      color: COLOR_SURFACE,
      borderColor: COLOR_DIVIDER,
      borderWidth: 1,
    });

    page.drawRectangle({
      x: 50,
      y: cardY + 154,
      width: PAGE_WIDTH - 100,
      height: 6,
      color: COLOR_PRIMARY,
    });

    const secSize = 24;
    const secWidth = fonts.bold.widthOfTextAtSize(sectionName, secSize);
    page.drawText(sectionName, {
      x: (PAGE_WIDTH - secWidth) / 2,
      y: cardY + 80,
      size: secSize,
      font: fonts.bold,
      color: COLOR_PRIMARY,
    });

    const secSub = 'Official Student Evidence & Portfolio Documentation';
    const subSize = 10;
    const subWidth = fonts.oblique.widthOfTextAtSize(secSub, subSize);
    page.drawText(secSub, {
      x: (PAGE_WIDTH - subWidth) / 2,
      y: cardY + 54,
      size: subSize,
      font: fonts.oblique,
      color: COLOR_TEXT_MUTED,
    });

    // Page number
    page.drawText(`Page ${pageNumber}`, {
      x: PAGE_WIDTH - 80,
      y: 35,
      size: 9,
      font: fonts.regular,
      color: COLOR_TEXT_MUTED,
    });
  }

  private renderDocumentMetadataSheet(
    pdfDoc: PDFDocument,
    doc: DocumentRecord,
    folderName: string,
    fonts: { regular: PDFFont; bold: PDFFont; oblique: PDFFont },
    pageNumber: number,
  ): void {
    const page = pdfDoc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);

    page.drawText('DOCUMENT OVERVIEW', {
      x: 50,
      y: PAGE_HEIGHT - 60,
      size: 16,
      font: fonts.bold,
      color: COLOR_PRIMARY,
    });

    page.drawLine({
      start: { x: 50, y: PAGE_HEIGHT - 70 },
      end: { x: PAGE_WIDTH - 50, y: PAGE_HEIGHT - 70 },
      thickness: 1,
      color: COLOR_DIVIDER,
    });

    let currentY = PAGE_HEIGHT - 105;

    // Document Title
    page.drawText('Title', { x: 50, y: currentY, size: 10, font: fonts.bold, color: COLOR_TEXT_MUTED });
    currentY -= 16;
    page.drawText(doc.title, { x: 50, y: currentY, size: 13, font: fonts.bold, color: COLOR_TEXT_PRIMARY });
    currentY -= 26;

    // Category / Date
    const formattedDate = doc.documentDate instanceof Date
      ? doc.documentDate.toISOString().slice(0, 10)
      : String(doc.documentDate).slice(0, 10);
    const metaLine = `${folderName}  •  ${formattedDate}  •  ${doc.originalFileName}`;
    page.drawText(metaLine, { x: 50, y: currentY, size: 9, font: fonts.regular, color: COLOR_TEXT_MUTED });
    currentY -= 26;

    // Description
    if (doc.description && doc.description.trim().length > 0) {
      page.drawText('Description', { x: 50, y: currentY, size: 10, font: fonts.bold, color: COLOR_TEXT_MUTED });
      currentY -= 16;
      currentY = this.drawWrappedText(page, doc.description.trim(), 50, currentY, PAGE_WIDTH - 100, fonts.regular, 10, 15);
      currentY -= 18;
    }

    // Reflection (User-written text strictly preserved; never AI generated)
    if (doc.reflection && doc.reflection.trim().length > 0) {
      page.drawText('Student Reflection', { x: 50, y: currentY, size: 10, font: fonts.bold, color: COLOR_PRIMARY });
      currentY -= 16;
      currentY = this.drawWrappedText(page, doc.reflection.trim(), 50, currentY, PAGE_WIDTH - 100, fonts.oblique, 10, 15);
      currentY -= 18;
    }

    // Attachment note
    page.drawText('Uploaded document pages follow immediately on next page.', {
      x: 50,
      y: currentY,
      size: 9,
      font: fonts.oblique,
      color: COLOR_TEXT_MUTED,
    });

    // Running footer
    page.drawText(`Page ${pageNumber}`, {
      x: PAGE_WIDTH - 80,
      y: 35,
      size: 9,
      font: fonts.regular,
      color: COLOR_TEXT_MUTED,
    });
  }

  private async renderImageArtifactPage(
    pdfDoc: PDFDocument,
    doc: DocumentRecord,
    attachment: PortfolioItemAttachment,
    imageBytes: Buffer,
    pageIndex: number,
    totalPages: number,
    folderName: string,
    fonts: { regular: PDFFont; bold: PDFFont; oblique: PDFFont },
    pageNumber: number,
  ): Promise<void> {
    const page = pdfDoc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);

    // Top mini-header with document title and page indicator
    const headerTitle = doc.title.length > 50 ? `${doc.title.substring(0, 48)}...` : doc.title;
    const pageIndicator = totalPages > 1 ? ` (Page ${pageIndex + 1} of ${totalPages})` : '';
    page.drawText(`${headerTitle}${pageIndicator}`, {
      x: 50,
      y: PAGE_HEIGHT - 45,
      size: 10,
      font: fonts.bold,
      color: COLOR_TEXT_PRIMARY,
    });

    const formattedDate = doc.documentDate instanceof Date
      ? doc.documentDate.toISOString().slice(0, 10)
      : String(doc.documentDate).slice(0, 10);
    const subText = `${folderName}  •  ${formattedDate}`;
    page.drawText(subText, {
      x: 50,
      y: PAGE_HEIGHT - 58,
      size: 8,
      font: fonts.regular,
      color: COLOR_TEXT_MUTED,
    });

    page.drawLine({
      start: { x: 50, y: PAGE_HEIGHT - 65 },
      end: { x: PAGE_WIDTH - 50, y: PAGE_HEIGHT - 65 },
      thickness: 0.5,
      color: COLOR_DIVIDER,
    });

    // Metadata card if page 0 and description/reflection present
    let availableTopY = PAGE_HEIGHT - 75;
    if (pageIndex === 0) {
      if (doc.description && doc.description.trim().length > 0) {
        availableTopY -= 5;
        page.drawText('Description: ', {
          x: 50,
          y: availableTopY,
          size: 8,
          font: fonts.bold,
          color: COLOR_TEXT_MUTED,
        });
        const descSample = doc.description.trim().length > 180 ? `${doc.description.trim().substring(0, 177)}...` : doc.description.trim();
        page.drawText(descSample, {
          x: 108,
          y: availableTopY,
          size: 8,
          font: fonts.regular,
          color: COLOR_TEXT_PRIMARY,
        });
        availableTopY -= 14;
      }

      if (doc.reflection && doc.reflection.trim().length > 0) {
        page.drawText('Reflection: ', {
          x: 50,
          y: availableTopY,
          size: 8,
          font: fonts.bold,
          color: COLOR_PRIMARY,
        });
        const refSample = doc.reflection.trim().length > 180 ? `${doc.reflection.trim().substring(0, 177)}...` : doc.reflection.trim();
        page.drawText(refSample, {
          x: 105,
          y: availableTopY,
          size: 8,
          font: fonts.oblique,
          color: COLOR_TEXT_PRIMARY,
        });
        availableTopY -= 16;
      }
    }

    // Normalize image bytes to an independent ArrayBuffer with byteOffset = 0
    // to shield against pdf-lib JpegEmbedder bug (DataView(imageData.buffer) ignoring byteOffset)
    const normalizedBytes = new Uint8Array(imageBytes);

    const isPng =
      normalizedBytes.length >= 8 &&
      normalizedBytes[0] === 0x89 &&
      normalizedBytes[1] === 0x50 &&
      normalizedBytes[2] === 0x4e &&
      normalizedBytes[3] === 0x47;

    let embeddedImg: PDFImage;
    try {
      if (isPng) {
        embeddedImg = await pdfDoc.embedPng(normalizedBytes);
      } else {
        embeddedImg = await pdfDoc.embedJpg(normalizedBytes);
      }
    } catch {
      throw new AppError(
        422,
        'PORTFOLIO_ARTIFACT_CORRUPT',
        'This portfolio file could not be processed.',
      );
    }

    // Calculate scale and position to preserve exact aspect ratio
    const marginSide = 40;
    const marginBottom = 50;
    const maxWidth = PAGE_WIDTH - marginSide * 2;
    const maxHeight = availableTopY - marginBottom - 15;

    const imgWidth = embeddedImg.width;
    const imgHeight = embeddedImg.height;

    const scale = Math.min(maxWidth / imgWidth, maxHeight / imgHeight, 1.0);
    const renderWidth = imgWidth * scale;
    const renderHeight = imgHeight * scale;

    const posX = (PAGE_WIDTH - renderWidth) / 2;
    const posY = marginBottom + (maxHeight - renderHeight) / 2;

    page.drawImage(embeddedImg, {
      x: posX,
      y: posY,
      width: renderWidth,
      height: renderHeight,
    });

    // Running footer
    page.drawText(`Page ${pageNumber}`, {
      x: PAGE_WIDTH - 80,
      y: 30,
      size: 9,
      font: fonts.regular,
      color: COLOR_TEXT_MUTED,
    });
  }

  private drawWrappedText(
    page: PDFPage,
    text: string,
    x: number,
    startY: number,
    maxWidth: number,
    font: PDFFont,
    fontSize: number,
    lineHeight: number,
  ): number {
    const words = text.split(/\s+/);
    let currentLine = '';
    let currentY = startY;

    for (const word of words) {
      const candidate = currentLine.length === 0 ? word : `${currentLine} ${word}`;
      const width = font.widthOfTextAtSize(candidate, fontSize);
      if (width > maxWidth && currentLine.length > 0) {
        page.drawText(currentLine, { x, y: currentY, size: fontSize, font, color: COLOR_TEXT_PRIMARY });
        currentLine = word;
        currentY -= lineHeight;
      } else {
        currentLine = candidate;
      }
    }

    if (currentLine.length > 0) {
      page.drawText(currentLine, { x, y: currentY, size: fontSize, font, color: COLOR_TEXT_PRIMARY });
      currentY -= lineHeight;
    }

    return currentY;
  }

  private repositories() {
    if (this.database === undefined) {
      throw new Error('Database connection is required to load documents by ownerId.');
    }
    const connection = this.database.mongooseConnection;
    if (this.database.status !== 'connected' || connection === undefined) {
      throw new AppError(503, 'DOCUMENT_UNAVAILABLE', 'Database is temporarily unavailable.');
    }
    return createRepositories(connection);
  }
}

async function readableToBoundedBuffer(stream: Readable, maxBytes: number): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let total = 0;
  for await (const chunk of stream) {
    const buffer = Buffer.isBuffer(chunk)
      ? chunk
      : typeof chunk === 'string' || chunk instanceof Uint8Array
        ? Buffer.from(chunk)
        : null;
    if (buffer === null) throw new Error('Unreadable stream chunk.');
    total += buffer.length;
    if (total > maxBytes) {
      throw new AppError(413, 'PORTFOLIO_TOO_LARGE', 'The portfolio artifact exceeds the supported size limit.');
    }
    chunks.push(buffer);
  }
  return Buffer.concat(chunks, total);
}
