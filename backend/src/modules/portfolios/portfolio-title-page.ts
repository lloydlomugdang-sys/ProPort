import { readFile } from 'node:fs/promises';
import { type PDFDocument, type PDFImage, type PDFPage, rgb } from 'pdf-lib';
import sharp from 'sharp';
import { AppError } from '../../common/errors/app-error.js';
import type { PortfolioExportInfo } from './portfolio-generator.service.js';
import { PORTFOLIO_LAYOUT as L, wrapPortfolioText, type PortfolioFonts, type TextLine } from './portfolio-layout.js';

// Symmetric about the physical page center, within both existing print margins.
const SIDE = Math.max(L.left, L.right);
const WIDTH = L.width - 2 * SIDE;
const CENTER = L.width / 2;
const SEAL_SIZE = 60;
const GAP = 12;

export interface StandardTitlePagePlan {
  readonly kind: 'title';
  readonly lines: readonly TextLine[];
  readonly top: number;
  readonly header?: {
    readonly seal: PDFImage;
    readonly lines: readonly TextLine[];
    readonly height: number;
    readonly dividerY: number;
  };
}

/** Branding is isolated here. No inferred college, description, or thesis facts. */
export function standardTitlePage(info: PortfolioExportInfo): readonly string[] {
  return [
    'ACADEMIC PORTFOLIO', 'Standard Title Page', '',
    'Full Name', info.fullName, '',
    'Year & Section', info.yearAndSection,
    'Schedule', info.schedule,
    "Instructor's Name", info.instructorName,
    'Course', info.course ?? '',
    'Course Code', info.courseCode ?? '',
    'Semester & Academic Year', info.semesterAndYear ?? '',
  ];
}

export async function officialNeuSealPng(): Promise<Buffer> {
  const asset = await readFile(new URL('../../../../assets/images/neu_seal.webp', import.meta.url))
    .catch(() => readFile(new URL('../../../../../assets/images/neu_seal.webp', import.meta.url)));
  return sharp(asset).png().toBuffer();
}

export async function planStandardTitlePages(
  pdf: PDFDocument, info: PortfolioExportInfo, fonts: PortfolioFonts, program: string,
): Promise<StandardTitlePagePlan[]> {
  const lines = (text: string, bold = false, width = WIDTH): TextLine[] =>
    wrapPortfolioText(text, bold ? fonts.bold : fonts.regular, width).map((text) => ({ text, bold, indent: 0 }));
  // Exact official-site asset, no recoloring/cropping/redrawing. pdf-lib needs
  // PNG rather than WebP; lossless conversion happens only in memory.
  const seal = await pdf.embedPng(await officialNeuSealPng());
  const headerLines = [
    ...lines('NEW ERA UNIVERSITY', true, WIDTH - 2 * (SEAL_SIZE + GAP)),
    ...(program.trim() ? lines(program.trim(), false, WIDTH - 2 * (SEAL_SIZE + GAP)) : []),
  ];
  const height = Math.max(SEAL_SIZE, headerLines.length * L.lineHeight);
  const dividerY = L.height - L.top - height - 18;
  const content = standardTitlePage(info).flatMap((value, index) => lines(value, index === 0));
  const pages: StandardTitlePagePlan[] = [];
  for (let start = 0; start < content.length;) {
    const first = pages.length === 0;
    const top = first ? dividerY - 24 : L.height - L.top;
    const capacity = Math.floor((top - L.bottom) / L.lineHeight) - 1;
    if (capacity < 1) throw new AppError(413, 'PORTFOLIO_TOO_LARGE',
      'The title-page header is too long. Shorten the program in your profile and retry.');
    const end = Math.min(start + capacity, content.length);
    pages.push({ kind: 'title', lines: content.slice(start, end), top,
      ...(first ? { header: { seal, lines: headerLines, height, dividerY } } : {}),
    });
    start = end;
  }
  return pages;
}

export function drawStandardTitlePage(page: PDFPage, plan: StandardTitlePagePlan, fonts: PortfolioFonts): void {
  const centered = (lines: readonly TextLine[], top: number, body = false) => lines.forEach((line, index) => {
    const font = line.bold ? fonts.bold : fonts.regular;
    page.drawText(line.text, { x: CENTER - font.widthOfTextAtSize(line.text, L.bodySize) / 2,
      y: top - L.bodySize - index * L.lineHeight, size: L.bodySize, font,
      color: body && line.bold ? rgb(0.086, 0.376, 0.533) : rgb(0, 0, 0) });
  });
  const header = plan.header;
  if (header) {
    const size = header.seal.scaleToFit(SEAL_SIZE, SEAL_SIZE);
    const y = L.height - L.top - (header.height + size.height) / 2;
    const inset = (SEAL_SIZE - size.width) / 2;
    for (const x of [SIDE + inset, L.width - SIDE - SEAL_SIZE + inset]) {
      page.drawImage(header.seal, { x, y, ...size });
    }
    centered(header.lines, L.height - L.top - (header.height - header.lines.length * L.lineHeight) / 2);
    page.drawLine({ start: { x: SIDE, y: header.dividerY }, end: { x: L.width - SIDE, y: header.dividerY },
      thickness: 2, color: rgb(0, 0, 0) });
  }
  centered(plan.lines, plan.top, true);
}
