import { createRequire } from 'node:module';
import { dirname, join, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  getDocument,
  PasswordResponses,
  VerbosityLevel,
} from 'pdfjs-dist/legacy/build/pdf.mjs';
import Tesseract from 'tesseract.js';
import sharp from 'sharp';
import {
  OcrEngineError,
  type OcrEngine,
  type OcrExtraction,
  type OcrInput,
} from './ocr-engine.js';

const require = createRequire(import.meta.url);
const englishData = require('@tesseract.js-data/eng') as {
  readonly langPath: string;
  readonly gzip: boolean;
};
const pdfPackageRoot = dirname(require.resolve('pdfjs-dist/package.json'));
const pdfCharacterMapsUrl = pathToFileURL(`${join(pdfPackageRoot, 'cmaps')}${sep}`).href;
const pdfStandardFontsUrl = pathToFileURL(
  `${join(pdfPackageRoot, 'standard_fonts')}${sep}`,
).href;

// Bound libvips memory and descriptor caching on memory-constrained instances
sharp.cache({ memory: 16, files: 0, items: 10 });

export const OCR_PROCESSING_TIMEOUT_MS = 45_000;
export const OCR_MAX_IMAGE_PIXELS = 25_000_000;
export const OCR_MAX_PDF_PAGES = 100;
export const OCR_MAX_TEXT_LENGTH = 200_000;
export const OCR_MAX_WORKING_DIMENSION = 2000;
export const OCR_MIN_UPSCALE_DIMENSION = 1000;

export interface ImageDimensions {
  readonly width: number;
  readonly height: number;
}

export interface OcrBBox {
  readonly x0: number;
  readonly y0: number;
  readonly x1: number;
  readonly y1: number;
}

export interface OcrWordInfo {
  readonly text: string;
  readonly confidence: number;
  readonly bbox?: OcrBBox | undefined;
}

export interface OcrLineInfo {
  readonly text: string;
  readonly confidence: number;
  readonly bbox?: OcrBBox | undefined;
  readonly words?: readonly OcrWordInfo[] | undefined;
}

export interface OcrCandidate {
  readonly text: string;
  readonly confidence: number;
  readonly pass: 'auto' | 'color-aware' | 'sparse' | 'thresholded';
  readonly lines?: readonly OcrLineInfo[] | undefined;
}

interface WorkerWithOutput {
  recognize(
    image: Tesseract.ImageLike,
    options?: Record<string, unknown>,
    output?: Record<string, boolean>,
  ): Promise<{ data: { text: string; confidence: number; blocks?: unknown[] } }>;
}

function parseBBox(obj: unknown): OcrBBox | undefined {
  if (typeof obj !== 'object' || obj === null) return undefined;
  const b = obj as Record<string, unknown>;
  if (
    typeof b.x0 === 'number' &&
    typeof b.y0 === 'number' &&
    typeof b.x1 === 'number' &&
    typeof b.y1 === 'number'
  ) {
    return { x0: b.x0, y0: b.y0, x1: b.x1, y1: b.y1 };
  }
  return undefined;
}

function parseWords(words?: unknown[]): OcrWordInfo[] | undefined {
  if (!Array.isArray(words)) return undefined;
  const result: OcrWordInfo[] = [];
  for (const w of words) {
    if (typeof w !== 'object' || w === null) continue;
    const wObj = w as Record<string, unknown>;
    if (typeof wObj.text === 'string') {
      result.push({
        text: wObj.text,
        confidence: typeof wObj.confidence === 'number' ? wObj.confidence : 0,
        bbox: parseBBox(wObj.bbox),
      });
    }
  }
  return result.length > 0 ? result : undefined;
}

export function extractLinesInfo(blocks?: unknown[]): OcrLineInfo[] {
  if (!blocks || !Array.isArray(blocks)) return [];
  const lines: OcrLineInfo[] = [];
  for (const block of blocks) {
    if (typeof block !== 'object' || block === null) continue;
    const paragraphs = (block as { paragraphs?: unknown[] }).paragraphs;
    if (!Array.isArray(paragraphs)) continue;
    for (const paragraph of paragraphs) {
      if (typeof paragraph !== 'object' || paragraph === null) continue;
      const pLines = (paragraph as { lines?: unknown[] }).lines;
      if (!Array.isArray(pLines)) continue;
      for (const line of pLines) {
        if (typeof line !== 'object' || line === null) continue;
        const lineObj = line as Record<string, unknown>;
        if (typeof lineObj.text === 'string') {
          lines.push({
            text: lineObj.text,
            confidence: typeof lineObj.confidence === 'number' ? lineObj.confidence : 0,
            bbox: parseBBox(lineObj.bbox),
            words: parseWords(lineObj.words as unknown[]),
          });
        }
      }
    }
  }
  return lines;
}

export function cleanAnchorLine(lineText: string): string {
  const trimmed = lineText.trim();
  const anchorMatch = trimmed.match(
    /\b((?:Certificate\s+No\.?|Cert\.?\s+No\.?|ID|Ref(?:\.?|\s+No\.?)|Serial\s+No\.?)[:\s]+[A-Z0-9-]+)\b/i,
  );
  if (anchorMatch && anchorMatch[1]) {
    const anchor = anchorMatch[1].trim();
    if (trimmed !== anchor && trimmed.length > anchor.length) {
      return anchor;
    }
  }
  return trimmed;
}

export function isExemptLine(lineText: string): boolean {
  const trimmed = lineText.trim();
  if (trimmed.length === 0) return true;

  // 1. Dates (4-digit year, month names, numeric dates)
  if (/\b(19|20)\d{2}\b/.test(trimmed)) return true;
  if (
    /\b(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\b/i.test(
      trimmed,
    )
  ) {
    return true;
  }
  if (/\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b/.test(trimmed)) return true;

  // 2. IDs, serials, and reference numbers
  if (/\b(id|no|number|ref|reference|serial|code|cert|certificate no)\b/i.test(trimmed)) {
    return true;
  }
  if (/\b[A-Z0-9]{2,}-[A-Z0-9-]+\b/.test(trimmed)) return true;

  // 3. Legitimate Certificate / Academic / Professional Roles and Terms
  if (
    /\b(dean|president|director|registrar|chancellor|provost|chairman|chairperson|secretary|head|principal|instructor|professor|prof|dr|engr|atty|mr|ms|mrs|lead|manager|coordinator|supervisor|officer)\b/i.test(
      trimmed,
    )
  ) {
    return true;
  }
  if (
    /\b(certificate|diploma|completion|achievement|recognition|participation|attendance|award|conferred|honors|degree|bachelor|master|doctor|seminar|training|workshop|course|university|college|school|institute|presented|awarded|conducted|organized|sponsored|issued|certified)\b/i.test(
      trimmed,
    )
  ) {
    return true;
  }

  // 4. Strong Plausible Real Names:
  // Rule A: Honorific + Name
  if (/\b(Dr|Engr|Atty|Prof|Hon|Mr|Mrs|Ms)\.?\s+[A-Z][a-z]+(\s+[A-Z][a-z]+)*/i.test(trimmed)) {
    return true;
  }
  // Rule B: Structured 2-to-4 word TitleCase name
  const words = trimmed.split(/\s+/);
  if (words.length >= 2 && words.length <= 4) {
    const isStrictTitleCase = words.every(
      (w) => /^[A-Z][a-z]{1,20}$/.test(w) || /^[A-Z]\.?$/.test(w),
    );
    if (isStrictTitleCase) return true;

    // Rule C: Structured 2-to-4 word All-Caps name (e.g. JUAN DELA CRUZ)
    const isStrictAllCaps = words.every(
      (w) => /^[A-Z]{2,20}$/.test(w) || /^[A-Z]\.?$/.test(w),
    );
    if (isStrictAllCaps) return true;
  }

  return false;
}

export function isDecorativeNoise(
  lineOrText: string | OcrLineInfo,
  confidenceParam?: number,
  dimensions?: ImageDimensions,
): boolean {
  const lineText = typeof lineOrText === 'string' ? lineOrText : lineOrText.text;
  const confidence =
    typeof lineOrText === 'string'
      ? (confidenceParam ?? 0)
      : lineOrText.confidence;
  const lineObj = typeof lineOrText === 'object' ? lineOrText : undefined;

  const cleaned = cleanAnchorLine(lineText);
  if (isExemptLine(cleaned)) return false;

  const trimmed = cleaned.trim();
  if (trimmed.length === 0) return false;

  // Short single/two-character lines that are not 2-4 digit numbers
  if (trimmed.length <= 2 && !/^\d{2,4}$/.test(trimmed)) {
    return true;
  }

  // Math or symbol artifacts commonly produced by decorative lines or cursive signatures
  const hasSymbolArtifact = /[=~_+*#<>|\\]/.test(trimmed);
  if (hasSymbolArtifact && !/\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b/.test(trimmed)) {
    return true;
  }

  // Alphanumeric ratio (< 50% alphanumeric when whitespace collapsed)
  const collapsed = trimmed.replace(/\s+/g, ' ');
  const alphanumericCount = (collapsed.match(/[a-zA-Z0-9]/g) || []).length;
  if (alphanumericCount === 0 || alphanumericCount / collapsed.length < 0.5) {
    return true;
  }

  // Outer margin check (outer 4% of image boundary)
  let isOuterMargin = false;
  if (lineObj?.bbox && dimensions && dimensions.width > 0 && dimensions.height > 0) {
    const bbox = lineObj.bbox;
    isOuterMargin =
      bbox.y1 < dimensions.height * 0.04 ||
      bbox.y0 > dimensions.height * 0.96 ||
      bbox.x1 < dimensions.width * 0.04 ||
      bbox.x0 > dimensions.width * 0.96;
    if (isOuterMargin && (trimmed.length < 15 || confidence < 75)) {
      return true;
    }
  }

  // Signature region check (lower 35% of page: y > 0.65 * H)
  if (lineObj?.bbox && dimensions && dimensions.height > 0) {
    const isLowerRegion = lineObj.bbox.y0 > dimensions.height * 0.65;
    if (isLowerRegion) {
      if (lineObj.words && lineObj.words.length > 0) {
        const avgWordConf =
          lineObj.words.reduce((sum, w) => sum + w.confidence, 0) / lineObj.words.length;
        if (avgWordConf < 70 && trimmed.length < 35) {
          return true;
        }
      } else if (confidence < 60 && trimmed.length < 35) {
        return true;
      }
    }
  }

  // Preserved if confidence is >= 50 unless symbol noise or margin geometry
  if (confidence >= 50) {
    if (isOuterMargin && trimmed.length < 15) {
      return true;
    }
    return false;
  }

  // Low confidence (< 50) and short line (< 35 chars)
  if (confidence < 45 && trimmed.length < 35) {
    return true;
  }

  return false;
}

export function cleanOcrText(
  rawText: string,
  linesInfo?: readonly OcrLineInfo[],
  dimensions?: ImageDimensions,
): string {
  // Normalize unprintable control characters
  const sanitized = rawText
    // eslint-disable-next-line no-control-regex
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '')
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

  let rawLines = sanitized.split('\n');

  // Filter decorative noise lines when line confidence information is available
  if (linesInfo && linesInfo.length > 0) {
    const filteredLines: string[] = [];
    for (const line of linesInfo) {
      if (!isDecorativeNoise(line, line.confidence, dimensions)) {
        filteredLines.push(cleanAnchorLine(line.text));
      }
    }
    if (filteredLines.length > 0) {
      rawLines = filteredLines.join('\n').split('\n');
    }
  }

  const cleanedLines: string[] = [];
  let i = 0;
  while (i < rawLines.length) {
    const current = rawLines[i]!;
    const anchorCleaned = cleanAnchorLine(current);
    const trimmed = anchorCleaned.trim();
    if (trimmed.length === 0) {
      cleanedLines.push('');
      i += 1;
      continue;
    }

    // Drop lines that contain only non-alphanumeric noise symbols
    const collapsedCurrent = trimmed.replace(/[\t ]+/g, ' ');
    const hasAlphaNumeric = /[a-zA-Z0-9]/.test(collapsedCurrent);
    if (!hasAlphaNumeric && collapsedCurrent.length < 10) {
      i += 1;
      continue;
    }

    // Multi-column signatory pairing
    // e.g. "Maria Santos       John Lloyd Lomugdang" followed by "Program Director       Project Lead"
    const currentParts = current.split(/\s{3,}|\t+/).map((s) => s.trim()).filter(Boolean);
    const nextLine = i + 1 < rawLines.length ? rawLines[i + 1] : undefined;
    const nextParts = nextLine ? nextLine.split(/\s{3,}|\t+/).map((s) => s.trim()).filter(Boolean) : [];

    if (currentParts.length >= 2 && currentParts.length === nextParts.length) {
      for (let col = 0; col < currentParts.length; col += 1) {
        cleanedLines.push(currentParts[col]!);
        cleanedLines.push(nextParts[col]!);
      }
      i += 2;
      continue;
    }

    if (currentParts.length >= 2) {
      for (const part of currentParts) {
        cleanedLines.push(part);
      }
      i += 1;
      continue;
    }

    cleanedLines.push(collapsedCurrent);
    i += 1;
  }

  return cleanedLines
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

export function usableCharCount(text: string): number {
  return text.replace(/\s+/g, '').length;
}

export function selectBestCandidate(candidates: readonly OcrCandidate[]): OcrCandidate {
  if (candidates.length === 0) {
    throw new Error('No OCR candidates to select from');
  }
  if (candidates.length === 1) {
    return candidates[0]!;
  }

  const standardCand = candidates.find((c) => c.pass === 'auto');
  const colorCand = candidates.find((c) => c.pass === 'color-aware');

  if (standardCand && colorCand) {
    const stdChars = usableCharCount(standardCand.text);
    const colorChars = usableCharCount(colorCand.text);

    // Guard: If color-aware candidate lost more than 25% of usable characters,
    // legitimate colored text may have been suppressed. Fall back to standard!
    if (stdChars > 0 && colorChars < stdChars * 0.75) {
      return standardCand;
    }
  }

  let best = candidates[0]!;
  for (let i = 1; i < candidates.length; i++) {
    const next = candidates[i]!;
    const bestChars = usableCharCount(best.text);
    const nextChars = usableCharCount(next.text);

    if (bestChars === 0 && nextChars > 0) {
      best = next;
      continue;
    }
    if (nextChars === 0 && bestChars > 0) {
      continue;
    }

    const confDiff = next.confidence - best.confidence;
    if (confDiff > 3) {
      best = next;
    } else if (confDiff < -3) {
      continue;
    } else {
      if (nextChars > bestChars * 1.15 && nextChars - bestChars >= 10) {
        best = next;
      } else if (bestChars > nextChars * 1.15 && bestChars - nextChars >= 10) {
        continue;
      } else if (confDiff > 0) {
        best = next;
      }
    }
  }
  return best;
}

export async function preprocessOcrImage(
  contents: Buffer,
  dimensions: ImageDimensions,
): Promise<Buffer> {
  let pipeline = sharp(contents).rotate();

  const longestEdge = Math.max(dimensions.width, dimensions.height);
  if (longestEdge > OCR_MAX_WORKING_DIMENSION) {
    pipeline = pipeline.resize({
      width: OCR_MAX_WORKING_DIMENSION,
      height: OCR_MAX_WORKING_DIMENSION,
      fit: 'inside',
      withoutEnlargement: true,
    });
  } else if (
    longestEdge < OCR_MIN_UPSCALE_DIMENSION &&
    dimensions.width * 2 * dimensions.height * 2 <= OCR_MAX_IMAGE_PIXELS
  ) {
    pipeline = pipeline.resize({
      width: dimensions.width * 2,
      height: dimensions.height * 2,
      fit: 'inside',
    });
  }

  pipeline = pipeline.grayscale().normalize().sharpen();

  return await pipeline.png().toBuffer();
}

export async function preprocessOcrColorAware(
  contents: Buffer,
  dimensions: ImageDimensions,
): Promise<Buffer> {
  let pipeline = sharp(contents).rotate();

  const longestEdge = Math.max(dimensions.width, dimensions.height);
  if (longestEdge > OCR_MAX_WORKING_DIMENSION) {
    pipeline = pipeline.resize({
      width: OCR_MAX_WORKING_DIMENSION,
      height: OCR_MAX_WORKING_DIMENSION,
      fit: 'inside',
      withoutEnlargement: true,
    });
  } else if (
    longestEdge < OCR_MIN_UPSCALE_DIMENSION &&
    dimensions.width * 2 * dimensions.height * 2 <= OCR_MAX_IMAGE_PIXELS
  ) {
    pipeline = pipeline.resize({
      width: dimensions.width * 2,
      height: dimensions.height * 2,
      fit: 'inside',
    });
  }

  const { data, info } = await pipeline.raw().toBuffer({ resolveWithObject: true });
  const channels = info.channels;
  const pixelCount = info.width * info.height;

  for (let i = 0; i < pixelCount; i += 1) {
    const idx = i * channels;
    const r = data[idx]!;
    const g = data[idx + 1]!;
    const b = data[idx + 2]!;

    const isDarkInk =
      (r <= 90 && g <= 90 && b <= 100) ||
      (b >= r && r <= 100) ||
      (g <= 90 && (r <= 140 || b <= 50));

    if (!isDarkInk) {
      const isWarmOrnament =
        r >= 130 &&
        g >= 100 &&
        r >= b + 35 &&
        g >= b + 15;

      if (isWarmOrnament) {
        data[idx] = 255;
        data[idx + 1] = 255;
        data[idx + 2] = 255;
      }
    }
  }

  return await sharp(data, {
    raw: {
      width: info.width,
      height: info.height,
      channels: info.channels,
    },
  })
    .grayscale()
    .normalize()
    .sharpen()
    .png()
    .toBuffer();
}

export async function binarizeOcrImage(preprocessedBuffer: Buffer): Promise<Buffer> {
  return await sharp(preprocessedBuffer).threshold(128).png().toBuffer();
}

export class LocalOcrEngine implements OcrEngine {
  private activeJobs = 0;
  private readonly activeDocumentIds = new Set<string>();
  public lastExecutedPassCount = 0;
  public lastExecutedCandidates: readonly OcrCandidate[] = [];

  constructor(
    private readonly timeoutMs = OCR_PROCESSING_TIMEOUT_MS,
    private readonly maxConcurrentJobs = 1,
  ) {}

  isBusy(): boolean {
    return this.activeJobs >= this.maxConcurrentJobs;
  }

  async extract(input: OcrInput): Promise<OcrExtraction> {
    if (input.documentId && this.activeDocumentIds.has(input.documentId)) {
      throw new OcrEngineError('unavailable');
    }
    if (this.activeJobs >= this.maxConcurrentJobs) {
      throw new OcrEngineError('busy');
    }
    this.activeJobs += 1;
    if (input.documentId) {
      this.activeDocumentIds.add(input.documentId);
    }
    try {
      if (input.fileKind === 'image') return await this.extractImage(input.contents);
      return await this.extractPdf(input.contents);
    } finally {
      this.activeJobs -= 1;
      if (input.documentId) {
        this.activeDocumentIds.delete(input.documentId);
      }
    }
  }

  private async extractImage(contents: Buffer): Promise<OcrExtraction> {
    const dimensions = imageDimensions(contents);
    if (dimensions === null) throw new OcrEngineError('invalid-image');
    if (dimensions.width * dimensions.height > OCR_MAX_IMAGE_PIXELS) {
      throw new OcrEngineError('image-too-large');
    }

    let preprocessedBuffer: Buffer | null = null;
    try {
      preprocessedBuffer = await preprocessOcrImage(contents, dimensions);
    } catch (error) {
      throw new OcrEngineError('invalid-image', { cause: error });
    }

    let worker: Awaited<ReturnType<typeof Tesseract.createWorker>> | undefined;
    let timedOut = false;
    let terminated = false;
    const terminate = async () => {
      if (worker === undefined || terminated) return;
      terminated = true;
      await worker.terminate().catch(() => undefined);
    };
    const operation = (async () => {
      worker = await Tesseract.createWorker('eng', Tesseract.OEM.LSTM_ONLY, {
        langPath: englishData.langPath,
        gzip: englishData.gzip,
        cacheMethod: 'none',
      });
      if (timedOut) {
        await terminate();
        throw new OcrEngineError('timeout');
      }

      await worker.setParameters({
        preserve_interword_spaces: '1',
        tessedit_pageseg_mode: Tesseract.PSM.AUTO,
      });
      if (timedOut) {
        await terminate();
        throw new OcrEngineError('timeout');
      }

      const candidates: OcrCandidate[] = [];

      // Pass 1: PSM.AUTO on preprocessed image
      const result1 = await (worker as unknown as WorkerWithOutput).recognize(
        preprocessedBuffer as unknown as Tesseract.ImageLike,
        {},
        { text: true, blocks: true },
      );
      if (timedOut) {
        await terminate();
        throw new OcrEngineError('timeout');
      }
      const cand1: OcrCandidate = {
        text: result1.data.text,
        confidence: result1.data.confidence,
        pass: 'auto',
        lines: extractLinesInfo(result1.data.blocks),
      };
      candidates.push(cand1);

      // Fast path: Pass 1 is sufficient if confident, sufficient length, and has no decorative noise lines
      const cand1Lines = cand1.lines ?? [];
      const hasNoiseLines = cand1Lines.some((l) =>
        isDecorativeNoise(l, l.confidence, dimensions),
      );
      const isPass1Sufficient =
        cand1.confidence >= 85 &&
        usableCharCount(cand1.text) >= 8 &&
        !hasNoiseLines;

      if (!isPass1Sufficient) {
        // Pass 2: Color-aware preprocessing with PSM.AUTO
        let colorAwareBuffer: Buffer;
        try {
          colorAwareBuffer = await preprocessOcrColorAware(contents, dimensions);
        } catch {
          colorAwareBuffer = preprocessedBuffer!;
        }
        if (colorAwareBuffer !== preprocessedBuffer) {
          preprocessedBuffer = null;
        }
        if (timedOut) {
          await terminate();
          throw new OcrEngineError('timeout');
        }
        const result2 = await (worker as unknown as WorkerWithOutput).recognize(
          colorAwareBuffer as unknown as Tesseract.ImageLike,
          {},
          { text: true, blocks: true },
        );
        if (timedOut) {
          await terminate();
          throw new OcrEngineError('timeout');
        }
        const cand2: OcrCandidate = {
          text: result2.data.text,
          confidence: result2.data.confidence,
          pass: 'color-aware',
          lines: extractLinesInfo(result2.data.blocks),
        };
        candidates.push(cand2);

        const bestSoFar = selectBestCandidate(candidates);
        // Pass 3: PSM.SPARSE_TEXT only if prior candidates remain poor
        const remainPoor = bestSoFar.confidence < 60 || usableCharCount(bestSoFar.text) < 8;

        if (remainPoor) {
          await worker.setParameters({
            tessedit_pageseg_mode: Tesseract.PSM.SPARSE_TEXT,
          });
          if (timedOut) {
            await terminate();
            throw new OcrEngineError('timeout');
          }
          const targetBuffer =
            bestSoFar.pass === 'color-aware' ? colorAwareBuffer : preprocessedBuffer;
          if (targetBuffer) {
            const result3 = await (worker as unknown as WorkerWithOutput).recognize(
              targetBuffer as unknown as Tesseract.ImageLike,
              {},
              { text: true, blocks: true },
            );
            if (timedOut) {
              await terminate();
              throw new OcrEngineError('timeout');
            }
            const cand3: OcrCandidate = {
              text: result3.data.text,
              confidence: result3.data.confidence,
              pass: 'sparse',
              lines: extractLinesInfo(result3.data.blocks),
            };
            candidates.push(cand3);
          }
        }
      }

      preprocessedBuffer = null;

      const winner = selectBestCandidate(candidates);
      this.lastExecutedPassCount = candidates.length;
      this.lastExecutedCandidates = candidates;
      return checkedText(winner.text, 'tesseract.js', winner.lines, dimensions);
    })();

    let timer: NodeJS.Timeout | undefined;
    try {
      return await Promise.race([
        operation,
        new Promise<never>((_resolve, reject) => {
          timer = setTimeout(() => {
            timedOut = true;
            void terminate();
            reject(new OcrEngineError('timeout'));
          }, this.timeoutMs);
        }),
      ]);
    } catch (error) {
      if (error instanceof OcrEngineError) throw error;
      throw new OcrEngineError('unavailable', { cause: error });
    } finally {
      preprocessedBuffer = null;
      if (timer !== undefined) clearTimeout(timer);
      await terminate();
    }
  }

  private async extractPdf(contents: Buffer): Promise<OcrExtraction> {
    this.lastExecutedPassCount = 1;
    this.lastExecutedCandidates = [];
    const loadingTask = getDocument({
      data: new Uint8Array(contents),
      cMapUrl: pdfCharacterMapsUrl,
      cMapPacked: true,
      standardFontDataUrl: pdfStandardFontsUrl,
      useSystemFonts: false,
      verbosity: VerbosityLevel.ERRORS,
    });
    let timer: NodeJS.Timeout | undefined;
    let timedOut = false;
    try {
      const pdf = await Promise.race([
        loadingTask.promise,
        new Promise<never>((_resolve, reject) => {
          timer = setTimeout(() => {
            timedOut = true;
            void loadingTask.destroy();
            reject(new OcrEngineError('timeout'));
          }, this.timeoutMs);
        }),
      ]);
      if (pdf.numPages > OCR_MAX_PDF_PAGES) {
        throw new OcrEngineError('pdf-too-many-pages');
      }

      const pages: string[] = [];
      let totalLength = 0;
      for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber += 1) {
        const page = await pdf.getPage(pageNumber);
        const content = await page.getTextContent();
        const pieces: string[] = [];
        for (const item of content.items) {
          if (!('str' in item) || typeof item.str !== 'string') continue;
          pieces.push(item.str);
          pieces.push(item.hasEOL ? '\n' : ' ');
        }
        const pageText = normalizeText(pieces.join(' '));
        if (pageText.length > 0) pages.push(pageText);
        totalLength += pageText.length;
        if (totalLength > OCR_MAX_TEXT_LENGTH) {
          throw new OcrEngineError('text-too-large');
        }
      }
      const rawText = normalizeText(pages.join('\n\n'));
      if (rawText.length === 0) {
        throw new OcrEngineError('scanned-pdf-not-supported');
      }
      return { rawText, engine: 'pdfjs' };
    } catch (error) {
      if (error instanceof OcrEngineError) throw error;
      if (timedOut) throw new OcrEngineError('timeout', { cause: error });
      if (isPasswordError(error)) {
        throw new OcrEngineError('protected-pdf', { cause: error });
      }
      throw new OcrEngineError('invalid-pdf', { cause: error });
    } finally {
      if (timer !== undefined) clearTimeout(timer);
      await loadingTask.destroy().catch(() => undefined);
    }
  }
}

function checkedText(
  rawText: string,
  engine: OcrExtraction['engine'],
  linesInfo?: readonly OcrLineInfo[],
  dimensions?: ImageDimensions,
): OcrExtraction {
  const cleaned = cleanOcrText(rawText, linesInfo, dimensions);
  const normalized = normalizeText(cleaned);
  if (normalized.length > OCR_MAX_TEXT_LENGTH) {
    throw new OcrEngineError('text-too-large');
  }
  return { rawText: normalized, engine };
}

function normalizeText(value: string): string {
  return value
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .split('\n')
    .map((line) => line.replace(/[\t ]+/g, ' ').trimEnd())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function isPasswordError(error: unknown): boolean {
  if (typeof error !== 'object' || error === null || !('code' in error)) return false;
  const code = (error as { readonly code?: unknown }).code;
  return code === PasswordResponses.NEED_PASSWORD || code === PasswordResponses.INCORRECT_PASSWORD;
}

function imageDimensions(contents: Buffer): ImageDimensions | null {
  if (
    contents.length >= 24 &&
    contents.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
  ) {
    return validDimensions(contents.readUInt32BE(16), contents.readUInt32BE(20));
  }
  if (contents.length < 4 || contents[0] !== 0xff || contents[1] !== 0xd8) return null;

  let offset = 2;
  while (offset + 3 < contents.length) {
    if (contents[offset] !== 0xff) {
      offset += 1;
      continue;
    }
    const marker = contents[offset + 1];
    if (marker === undefined) return null;
    offset += 2;
    if (marker === 0xd8 || marker === 0xd9 || (marker >= 0xd0 && marker <= 0xd7)) {
      continue;
    }
    if (offset + 1 >= contents.length) return null;
    const segmentLength = contents.readUInt16BE(offset);
    if (segmentLength < 2 || offset + segmentLength > contents.length) return null;
    if (isStartOfFrame(marker)) {
      if (segmentLength < 7) return null;
      return validDimensions(contents.readUInt16BE(offset + 5), contents.readUInt16BE(offset + 3));
    }
    offset += segmentLength;
  }
  return null;
}

function isStartOfFrame(marker: number): boolean {
  return (
    (marker >= 0xc0 && marker <= 0xc3) ||
    (marker >= 0xc5 && marker <= 0xc7) ||
    (marker >= 0xc9 && marker <= 0xcb) ||
    (marker >= 0xcd && marker <= 0xcf)
  );
}

function validDimensions(width: number, height: number): ImageDimensions | null {
  if (width <= 0 || height <= 0 || width > 65_535 || height > 65_535) return null;
  return { width, height };
}
