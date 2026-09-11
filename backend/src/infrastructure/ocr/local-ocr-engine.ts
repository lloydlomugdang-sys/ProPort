import { createRequire } from 'node:module';
import { dirname, join, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  getDocument,
  PasswordResponses,
  VerbosityLevel,
} from 'pdfjs-dist/legacy/build/pdf.mjs';
import Tesseract from 'tesseract.js';
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

export const OCR_PROCESSING_TIMEOUT_MS = 45_000;
export const OCR_MAX_IMAGE_PIXELS = 25_000_000;
export const OCR_MAX_PDF_PAGES = 100;
export const OCR_MAX_TEXT_LENGTH = 200_000;

interface ImageDimensions {
  readonly width: number;
  readonly height: number;
}

export class LocalOcrEngine implements OcrEngine {
  private activeJobs = 0;

  constructor(
    private readonly timeoutMs = OCR_PROCESSING_TIMEOUT_MS,
    private readonly maxConcurrentJobs = 2,
  ) {}

  async extract(input: OcrInput): Promise<OcrExtraction> {
    if (this.activeJobs >= this.maxConcurrentJobs) {
      throw new OcrEngineError('unavailable');
    }
    this.activeJobs += 1;
    try {
      if (input.fileKind === 'image') return await this.extractImage(input.contents);
      return await this.extractPdf(input.contents);
    } finally {
      this.activeJobs -= 1;
    }
  }

  private async extractImage(contents: Buffer): Promise<OcrExtraction> {
    const dimensions = imageDimensions(contents);
    if (dimensions === null) throw new OcrEngineError('invalid-image');
    if (dimensions.width * dimensions.height > OCR_MAX_IMAGE_PIXELS) {
      throw new OcrEngineError('image-too-large');
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
      const result = await worker.recognize(contents as unknown as Tesseract.ImageLike);
      return checkedText(result.data.text, 'tesseract.js');
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
      if (timer !== undefined) clearTimeout(timer);
      await terminate();
    }
  }

  private async extractPdf(contents: Buffer): Promise<OcrExtraction> {
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

function checkedText(rawText: string, engine: OcrExtraction['engine']): OcrExtraction {
  const normalized = normalizeText(rawText);
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
