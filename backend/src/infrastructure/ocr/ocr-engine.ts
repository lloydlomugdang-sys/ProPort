export type OcrEngineName = 'tesseract.js' | 'pdfjs';

export interface OcrInput {
  readonly contents: Buffer;
  readonly mimeType: string;
  readonly fileKind: 'image' | 'pdf';
  readonly documentId?: string;
}

export interface OcrExtraction {
  readonly rawText: string;
  readonly engine: OcrEngineName;
}

export type OcrEngineFailureReason =
  | 'busy'
  | 'invalid-image'
  | 'image-too-large'
  | 'invalid-pdf'
  | 'pdf-too-many-pages'
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
