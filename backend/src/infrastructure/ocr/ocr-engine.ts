export type OcrEngineName = 'tesseract.js' | 'pdfjs';

export interface OcrInput {
  readonly contents: Buffer;
  readonly mimeType: string;
  readonly fileKind: 'image' | 'pdf';
  readonly documentId?: string;
  /** Internal caller-selected profile; never derived from untrusted upload fields. */
  readonly profile?: 'compiled-analysis';
}

export interface OcrPageText {
  readonly pageNumber: number;
  readonly text: string;
  readonly source?: 'digital' | 'ocr' | 'blank' | 'failed';
  readonly status?: 'ready' | 'unresolved';
}

export interface OcrExtraction {
  readonly rawText: string;
  readonly engine: OcrEngineName;
  readonly pages?: readonly OcrPageText[];
  readonly totalPages?: number;
}

export type OcrEngineFailureReason =
  | 'busy'
  | 'invalid-image'
  | 'image-too-large'
  | 'invalid-pdf'
  | 'pdf-too-many-pages'
  | 'pdf-too-many-ocr-pages'
  | 'protected-pdf'
  | 'scanned-pdf-not-supported'
  | 'text-too-large'
  | 'timeout'
  | 'unavailable';

export class OcrEngineError extends Error {
  constructor(
    readonly reason: OcrEngineFailureReason,
    options?: ErrorOptions,
  ) {
    super('Local OCR extraction failed.', options);
    this.name = 'OcrEngineError';
  }
}

export interface OcrEngine {
  extract(input: OcrInput): Promise<OcrExtraction>;
}

/** Content-free timings: never include file names, text, identities, or credentials. */
export type OcrTiming = {
  readonly pageNumber: number;
  readonly source: 'digital' | 'ocr';
  readonly rasterizationMs: number;
  readonly ocrPassMs: readonly number[];
  readonly pageMs: number;
} | { readonly analysisMs: number };

/** Content-free memory telemetry: never include text, file names, or document contents. */
export interface OcrMemorySample {
  readonly phase:
    | 'analysis-start'
    | 'after-pdf-load'
    | 'before-fallback-page'
    | 'after-rasterization'
    | 'before-ocr-pass'
    | 'after-ocr-pass'
    | 'after-page-cleanup'
    | 'after-worker-cleanup'
    | 'after-pdf-cleanup'
    | 'analysis-end';
  readonly rss: number;
  readonly heapUsed: number;
  readonly external: number;
  readonly arrayBuffers: number;
  readonly pageNumber?: number | undefined;
  readonly passNumber?: number | undefined;
  readonly elapsedMs: number;
}
