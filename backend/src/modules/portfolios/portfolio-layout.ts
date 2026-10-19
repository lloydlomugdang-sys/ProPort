import { type PDFDocument, type PDFFont } from 'pdf-lib';
import fontkit from '@pdf-lib/fontkit';
import { readFile } from 'node:fs/promises';
import { AppError } from '../../common/errors/app-error.js';

export const PORTFOLIO_LAYOUT = {
  width: 612, height: 792,
  left: 108, top: 72, right: 72, bottom: 72,
  bodySize: 12, lineHeight: 24,
} as const;

export interface PortfolioFonts {
  readonly regular: PDFFont;
  readonly bold: PDFFont;
}

/** Central injection point for a licensed font loader (including registerFontkit).
 * No approved Arial asset is currently supplied. This fallback is NOT Arial.
 */
export type PortfolioFontLoader = (pdf: PDFDocument) => Promise<PortfolioFonts>;
export const loadPortfolioFallbackFonts: PortfolioFontLoader = async (pdf) => {
  pdf.registerFontkit(fontkit);
  const asset = async (name: string) => {
    try { return await readFile(new URL(`../../../../assets/fonts/${name}`, import.meta.url)); }
    catch { return readFile(new URL(`../../../../../assets/fonts/${name}`, import.meta.url)); }
  };
  return {
    regular: await pdf.embedFont(await asset('NotoSans-Regular.ttf'), { subset: true }),
    bold: await pdf.embedFont(await asset('NotoSans-Bold.ttf'), { subset: true }),
  };
};

export interface TextLine {
  readonly text: string;
  readonly bold: boolean;
  readonly indent: number;
  readonly questionnaire?: 'section' | 'response';
}

export const CONTENT_WIDTH = PORTFOLIO_LAYOUT.width - PORTFOLIO_LAYOUT.left - PORTFOLIO_LAYOUT.right;
// Reserve one double-spaced line for a footer, inside (not below) the margins.
export const TEXT_LINES_PER_PAGE = Math.floor(
  (PORTFOLIO_LAYOUT.height - PORTFOLIO_LAYOUT.top - PORTFOLIO_LAYOUT.bottom) /
  PORTFOLIO_LAYOUT.lineHeight,
) - 1;

/** Wrap paragraphs and even unbroken words by measured font width; never ellipsize. */
export function wrapPortfolioText(text: string, font: PDFFont, width = CONTENT_WIDTH): string[] {
  const lines: string[] = [];
  // Standard-font metrics include kerning; drawText emits individual glyph
  // advances. Reserve the larger width so actual output stays within margins.
  const glyphWidths = new Map<string, number>();
  const measuredWidth = (value: string) => Math.max(
    font.widthOfTextAtSize(value, PORTFOLIO_LAYOUT.bodySize),
    [...value].reduce((total, character) => {
      let advance = glyphWidths.get(character);
      if (advance === undefined) {
        advance = font.widthOfTextAtSize(character, PORTFOLIO_LAYOUT.bodySize);
        glyphWidths.set(character, advance);
      }
      return total + advance;
    }, 0),
  );
  try {
    const supported = new Set(font.getCharacterSet());
    if ([...text].some((character) => !/\s/.test(character) && !supported.has(character.codePointAt(0)!))) {
      throw new Error('Unsupported glyph');
    }
    for (const paragraph of text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
      let line = '';
      for (const word of paragraph.split(/\s+/).filter(Boolean)) {
        const candidate = line ? `${line} ${word}` : word;
        if (measuredWidth(candidate) <= width) {
          line = candidate;
          continue;
        }
        if (line) lines.push(line);
        line = '';
        for (const character of word) {
          if (line && measuredWidth(line + character) > width) {
            lines.push(line);
            line = '';
          }
          line += character;
        }
      }
      lines.push(line);
    }
  } catch {
    throw new AppError(422, 'PORTFOLIO_FONT_UNSUPPORTED',
      'The configured portfolio font cannot render some text. An approved font with matching character support is required.');
  }
  return lines;
}

/** Center within the printable rectangle, preserving the original aspect ratio. */
export function fitPortfolioArtifact(
  sourceWidth: number,
  sourceHeight: number,
  pageWidth: number,
  pageHeight: number,
  headerHeight = 0,
  footerHeight = 0,
) {
  const width = pageWidth - PORTFOLIO_LAYOUT.left - PORTFOLIO_LAYOUT.right;
  const height = pageHeight - PORTFOLIO_LAYOUT.top - PORTFOLIO_LAYOUT.bottom - headerHeight - footerHeight;
  const scale = Math.min(width / sourceWidth, height / sourceHeight, 1);
  return {
    x: PORTFOLIO_LAYOUT.left + (width - sourceWidth * scale) / 2,
    y: PORTFOLIO_LAYOUT.bottom + footerHeight + (height - sourceHeight * scale) / 2,
    width: sourceWidth * scale,
    height: sourceHeight * scale,
    scale,
  };
}
