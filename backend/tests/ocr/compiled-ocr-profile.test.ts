import sharp from 'sharp';
import Tesseract from 'tesseract.js';
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  COMPILED_ANALYSIS_TIMEOUT_MS,
  COMPILED_MAX_RASTER_DIMENSION,
  LocalOcrEngine,
  OCR_PROCESSING_TIMEOUT_MS,
} from '../../src/infrastructure/ocr/local-ocr-engine.js';
import type { OcrTiming } from '../../src/infrastructure/ocr/ocr-engine.js';
import { cvText, mixedPdf } from '../helpers/mixed-pdf-fixtures.js';

type Worker = Awaited<ReturnType<typeof Tesseract.createWorker>>;
const result = (text: string, confidence: number) => ({ data: { text, confidence } });

function mockWorker() {
  const worker = {
    recognize: vi.fn().mockResolvedValue(result(cvText, 75)),
    setParameters: vi.fn().mockResolvedValue(undefined),
    terminate: vi.fn().mockResolvedValue(undefined),
  };
  const create = vi.spyOn(Tesseract, 'createWorker').mockResolvedValue(worker as unknown as Worker);
  return { worker, create };
}

class ImageProbe extends LocalOcrEngine {
  compiledImage(bytes: Buffer, timeout: number) {
    return this.extractImage(bytes, timeout, undefined, 'compiled-analysis');
  }
}

const image = () => sharp({ create: { width: 200, height: 200, channels: 3, background: 'white' } }).png().toBuffer();

afterEach(() => { vi.restoreAllMocks(); });

describe('compiled-only OCR profile', () => {
  it('never rasterizes or starts OCR for sufficient digital text', async () => {
    const { create } = mockWorker();
    const timings: OcrTiming[] = [];
    const engine = new LocalOcrEngine(undefined, 1, (timing) => timings.push(timing));
    const extracted = await engine.extract({ contents: await mixedPdf([{ text: cvText }]),
      fileKind: 'pdf', mimeType: 'application/pdf', profile: 'compiled-analysis' });
    expect(extracted.pages?.[0]?.source).toBe('digital');
    expect(create).not.toHaveBeenCalled();
    expect(timings).toEqual([{ pageNumber: 1, source: 'digital', rasterizationMs: 0, ocrPassMs: [], pageMs: expect.any(Number) }]);
  });

  it('stops after one sufficient pass, bounds the raster and logs timings without contents', async () => {
    const { worker } = mockWorker();
    const timings: OcrTiming[] = [];
    const engine = new LocalOcrEngine(undefined, 1, (timing) => timings.push(timing));
    const extracted = await engine.extract({ contents: await mixedPdf([{ text: cvText, scanned: true }]),
      fileKind: 'pdf', mimeType: 'application/pdf', profile: 'compiled-analysis' });
    expect(extracted.pages?.[0]).toMatchObject({ source: 'ocr', text: cvText });
    expect(worker.recognize).toHaveBeenCalledTimes(1);
    expect(worker.terminate).toHaveBeenCalledTimes(1);
    const raster = worker.recognize.mock.calls[0]![0] as Buffer;
    const dimensions = await sharp(raster).metadata();
    expect(Math.max(dimensions.width!, dimensions.height!)).toBeLessThanOrEqual(COMPILED_MAX_RASTER_DIMENSION);
    expect(timings).toEqual([{ pageNumber: 1, source: 'ocr', rasterizationMs: expect.any(Number), ocrPassMs: [expect.any(Number)], pageMs: expect.any(Number) }]);
    expect(JSON.stringify(timings)).not.toContain(cvText);
  });

  it('runs only a targeted sparse fallback after a poor first pass and selects, never concatenates', async () => {
    const { worker } = mockWorker();
    worker.recognize.mockResolvedValueOnce(result('x', 20)).mockResolvedValueOnce(result(cvText, 80));
    const engine = new ImageProbe();
    const extracted = await engine.compiledImage(await image(), 1000);
    expect(extracted.rawText).toBe(cvText);
    expect(worker.recognize).toHaveBeenCalledTimes(2);
    expect(worker.setParameters.mock.calls.map(([parameters]) => parameters.tessedit_pageseg_mode))
      .toEqual([Tesseract.PSM.AUTO, Tesseract.PSM.SPARSE_TEXT]);
    expect(engine.lastExecutedCandidates.map((candidate) => candidate.pass)).toEqual(['auto', 'sparse']);
  });

  it('does not accept a high-confidence tiny fragment as sufficient segmentation text', async () => {
    const { worker } = mockWorker();
    worker.recognize.mockResolvedValueOnce(result('Output', 99));
    await new ImageProbe().compiledImage(await image(), 1000);
    expect(worker.recognize).toHaveBeenCalledTimes(2);
  });

  it('keeps unreadable pages unresolved after two empty passes; never adds a third pass', async () => {
    const { worker } = mockWorker();
    worker.recognize.mockResolvedValue(result('', 0));
    const extracted = await new LocalOcrEngine().extract({ contents: await mixedPdf([{ text: cvText, scanned: true }]),
      fileKind: 'pdf', mimeType: 'application/pdf', profile: 'compiled-analysis' });
    expect(worker.recognize).toHaveBeenCalledTimes(2);
    expect(extracted.pages?.[0]).toMatchObject({ pageNumber: 1, source: 'failed', status: 'unresolved', text: '' });
  });

  it('preserves ordinary upload multi-pass behavior and the 45-second default', async () => {
    const { worker } = mockWorker();
    const timer = vi.spyOn(globalThis, 'setTimeout');
    await new LocalOcrEngine().extract({ contents: await image(), fileKind: 'image', mimeType: 'image/png' });
    expect(worker.recognize).toHaveBeenCalledTimes(2);
    expect(worker.setParameters).toHaveBeenCalledTimes(1); // Both normal passes use AUTO.
    expect(timer.mock.calls.some(([, ms]) => ms! <= OCR_PROCESSING_TIMEOUT_MS && ms! > 44_000)).toBe(true);
  });

  it('uses the dedicated compiled deadline, not the ordinary constructor timeout', async () => {
    const timer = vi.spyOn(globalThis, 'setTimeout');
    const bytes = await mixedPdf([{ text: cvText }]);
    const engine = new LocalOcrEngine(0);
    await expect(engine.extract({ contents: bytes, fileKind: 'pdf', mimeType: 'application/pdf', profile: 'compiled-analysis' }))
      .resolves.toMatchObject({ totalPages: 1 });
    expect(timer.mock.calls.some(([, ms]) => ms === COMPILED_ANALYSIS_TIMEOUT_MS)).toBe(true);
    await expect(engine.extract({ contents: bytes, fileKind: 'pdf', mimeType: 'application/pdf' }))
      .rejects.toMatchObject({ reason: 'timeout' });
  });

  it('terminates a stuck OCR pass within its remaining page deadline', async () => {
    const { worker } = mockWorker();
    worker.recognize.mockImplementation(() => new Promise(() => undefined));
    await expect(new ImageProbe().compiledImage(await image(), 100)).rejects.toMatchObject({ reason: 'timeout' });
    expect(worker.recognize).toHaveBeenCalledTimes(1);
    expect(worker.terminate).toHaveBeenCalledTimes(1);
  });

  it('terminates a worker that finishes initialization after its deadline', async () => {
    const { worker, create } = mockWorker();
    let release!: (worker: Worker) => void;
    create.mockImplementation(() => new Promise<Worker>((resolve) => { release = resolve; }));
    await expect(new ImageProbe().compiledImage(await image(), 100)).rejects.toMatchObject({ reason: 'timeout' });
    release(worker as unknown as Worker);
    await vi.waitFor(() => expect(worker.terminate).toHaveBeenCalledTimes(1));
    expect(worker.recognize).not.toHaveBeenCalled();
  });

  it('reuses a single Tesseract worker sequentially across multiple PDF fallback pages and terminates once', async () => {
    const { worker, create } = mockWorker();
    let inFlight = 0;
    let maxInFlight = 0;
    const callOrder: number[] = [];
    worker.recognize.mockImplementation(async () => {
      inFlight += 1;
      maxInFlight = Math.max(maxInFlight, inFlight);
      callOrder.push(callOrder.length + 1);
      await new Promise((resolve) => setTimeout(resolve, 10));
      inFlight -= 1;
      return result(cvText, 85);
    });

    const engine = new LocalOcrEngine();
    const pdfBytes = await mixedPdf([
      { text: cvText },
      { text: cvText, scanned: true },
      { text: cvText, scanned: true },
    ]);
    const extracted = await engine.extract({
      contents: pdfBytes,
      fileKind: 'pdf',
      mimeType: 'application/pdf',
      profile: 'compiled-analysis',
    });

    expect(extracted.pages?.map((p) => p.source)).toEqual(['digital', 'ocr', 'ocr']);
    expect(create).toHaveBeenCalledTimes(1);
    expect(worker.recognize).toHaveBeenCalledTimes(2);
    expect(maxInFlight).toBe(1);
    expect(callOrder).toEqual([1, 2]);
    expect(worker.terminate).toHaveBeenCalledTimes(1);
    expect(engine.lastExecutedCandidates.every((c) => c.lines === undefined)).toBe(true);
  });

  it('always terminates the worker when OCR recognition throws an unexpected error', async () => {
    const { worker, create } = mockWorker();
    worker.recognize.mockRejectedValue(new Error('wasm recognize fault'));

    await expect(new ImageProbe().compiledImage(await image(), 1000)).rejects.toMatchObject({
      reason: 'unavailable',
    });
    expect(create).toHaveBeenCalledTimes(1);
    expect(worker.terminate).toHaveBeenCalledTimes(1);
  });

  it('always terminates the shared PDF worker on whole-PDF timeout', async () => {
    const { worker, create } = mockWorker();
    worker.recognize.mockImplementation(() => new Promise(() => undefined));

    const pdfBytes = await mixedPdf([{ text: cvText, scanned: true }]);
    await expect(
      new LocalOcrEngine(800).extract({
        contents: pdfBytes,
        fileKind: 'pdf',
        mimeType: 'application/pdf',
      }),
    ).rejects.toMatchObject({ reason: 'timeout' });

    expect(create).toHaveBeenCalledTimes(1);
    expect(worker.terminate).toHaveBeenCalledTimes(1);
  });
});
