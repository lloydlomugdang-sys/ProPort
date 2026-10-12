import { describe, expect, it } from 'vitest';
import { LocalOcrEngine, OCR_MAX_PDF_FALLBACK_PAGES } from '../../src/infrastructure/ocr/local-ocr-engine.js';
import { OcrEngineError, type OcrExtraction, type OcrInput } from '../../src/infrastructure/ocr/ocr-engine.js';
import { certificateText, cvText, cvContinuationText, mixedPdf } from '../helpers/mixed-pdf-fixtures.js';

class CountingEngine extends LocalOcrEngine {
  calls = 0;
  active = 0;
  peak = 0;
  failCall = 0;
  fast = false;
  protected override async extractImage(bytes: Buffer, timeout?: number, onPass?: (ms: number) => void, profile?: OcrInput['profile']): Promise<OcrExtraction> {
    this.calls++;
    this.active++;
    this.peak = Math.max(this.peak, this.active);
    try {
      if (this.calls === this.failCall) throw new OcrEngineError('unavailable');
      return this.fast ? { rawText: cvText, engine: 'tesseract.js' } : await super.extractImage(bytes, timeout, onPass, profile);
    } finally { this.active--; }
  }
}

describe('bounded mixed-PDF extraction', () => {
  it('keeps compiled fallback pages sequential and preserves scanned CV/certificate quality', async () => {
    const engine = new CountingEngine();
    const result = await engine.extract({ contents: await mixedPdf([
      { text: cvText, scanned: true }, { text: cvContinuationText }, { text: certificateText, scanned: true },
    ]), fileKind: 'pdf', mimeType: 'application/pdf', profile: 'compiled-analysis' });
    expect(engine.calls).toBe(2);
    expect(engine.peak).toBe(1);
    expect(result.pages?.map((page) => page.source)).toEqual(['ocr', 'digital', 'ocr']);
    expect(result.pages?.[0]?.text).toMatch(/CURRICULUM VITAE/i);
    expect(result.pages?.[2]?.text).toMatch(/CERTIFICATE OF PARTICIPATION/i);
  });
  it.each([[false, false], [true, true], [false, true], [true, false]])(
    'preserves digital text and OCRs only scanned pages (%s / %s)', async (certificateScanned, cvScanned) => {
      const engine = new CountingEngine();
      const input = await mixedPdf([{ text: certificateText, scanned: certificateScanned }, { text: cvText, scanned: cvScanned }]);
      const before = Buffer.from(input);
      const result = await engine.extract({ contents: input, fileKind: 'pdf', mimeType: 'application/pdf' });
      expect(result.pages?.map((page) => page.source)).toEqual([certificateScanned ? 'ocr' : 'digital', cvScanned ? 'ocr' : 'digital']);
      expect(result.pages?.map((page) => page.pageNumber)).toEqual([1, 2]);
      expect(result.pages?.every((page) => page.status === 'ready')).toBe(true);
      expect(result.rawText).toMatch(/CERTIFICATE OF PARTICIPATION/i);
      expect(result.rawText).toMatch(/CURRICULUM VITAE/i);
      expect(engine.calls).toBe(Number(certificateScanned) + Number(cvScanned));
      expect(engine.peak).toBeLessThanOrEqual(1);
      expect(input.equals(before)).toBe(true);
    },
  );

  it('OCRs a sparse digital layer on a scanned CV continuation', async () => {
    const engine = new CountingEngine();
    const result = await engine.extract({ contents: await mixedPdf([
      { text: cvText }, { text: cvContinuationText, scanned: true, digitalFragment: 'CV 2' },
    ]), fileKind: 'pdf', mimeType: 'application/pdf' });
    expect(engine.calls).toBe(1);
    expect(result.pages?.[1]).toMatchObject({ pageNumber: 2, source: 'ocr', status: 'ready' });
    expect(result.pages?.[1]?.text).toMatch(/Professional experience/i);
  });

  it('retains failed page identity and continues other pages without invented text', async () => {
    const engine = new CountingEngine(); engine.failCall = 1;
    const result = await engine.extract({ contents: await mixedPdf([
      { text: certificateText }, { text: cvText, scanned: true }, { text: certificateText },
    ]), fileKind: 'pdf', mimeType: 'application/pdf' });
    expect(result.pages).toHaveLength(3);
    expect(result.pages?.[1]).toEqual({ pageNumber: 2, text: '', source: 'failed', status: 'unresolved' });
    expect(result.pages?.[2]?.source).toBe('digital');
  });

  it('fails explicitly when the fallback-page budget is exceeded', async () => {
    const engine = new CountingEngine(); engine.fast = true;
    const input = await mixedPdf(Array.from({ length: OCR_MAX_PDF_FALLBACK_PAGES + 1 }, () => ({ text: cvText, scanned: true })));
    await expect(engine.extract({ contents: input, fileKind: 'pdf', mimeType: 'application/pdf' }))
      .rejects.toMatchObject({ reason: 'pdf-too-many-ocr-pages' });
    expect(engine.calls).toBe(OCR_MAX_PDF_FALLBACK_PAGES);
  });
});
