import { afterEach, describe, expect, it, vi } from 'vitest';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';
import type * as PdfJs from 'pdfjs-dist/legacy/build/pdf.mjs';
import { COMPILED_ANALYSIS_TIMEOUT_MS, LocalOcrEngine } from '../../src/infrastructure/ocr/local-ocr-engine.js';

vi.mock('pdfjs-dist/legacy/build/pdf.mjs', async (importOriginal) => ({
  ...await importOriginal<typeof PdfJs>(),
  getDocument: vi.fn(),
}));

afterEach(() => { vi.useRealTimers(); vi.clearAllMocks(); });

describe('whole-PDF deadline', () => {
  it.each(['loading', 'page', 'text', 'render', 'late-page', 'late-text'])('bounds stuck %s work, not only initial PDF loading', async (stuck) => {
    vi.useFakeTimers();
    const never = new Promise<never>(() => undefined);
    let resume!: (value: unknown) => void;
    const delayed = new Promise((resolve) => { resume = resolve; });
    const destroy = vi.fn().mockResolvedValue(undefined);
    let rejectRender!: (error: Error) => void;
    const renderPromise = new Promise<never>((_resolve, reject) => { rejectRender = reject; });
    // Keep the deliberately unused render promise from causing unhandled failures.
    const cancel = vi.fn(() => rejectRender(new Error('render cancelled')));
    const page = {
      getTextContent: vi.fn(() => stuck === 'text' ? never : stuck === 'late-text' ? delayed : Promise.resolve({ items: [] })),
      getViewport: vi.fn(() => ({ width: 600, height: 800 })),
      render: vi.fn(() => ({ promise: renderPromise, cancel })),
      cleanup: vi.fn(),
    };
    const pdf = { numPages: 1, getPage: vi.fn(() => stuck === 'page' ? never : stuck === 'late-page' ? delayed : Promise.resolve(page)),
      canvasFactory: { create: vi.fn(() => ({ canvas: {}, context: {} })), destroy: vi.fn() } };
    vi.mocked(getDocument).mockReturnValue({
      promise: stuck === 'loading' ? never : Promise.resolve(pdf), destroy,
    } as unknown as ReturnType<typeof getDocument>);
    const engine = new LocalOcrEngine();
    const pending = engine.extract({ contents: Buffer.from('%PDF-fixture'), fileKind: 'pdf',
      mimeType: 'application/pdf', profile: 'compiled-analysis' });
    const assertion = expect(pending).rejects.toMatchObject({ reason: 'timeout' });
    await vi.advanceTimersByTimeAsync(COMPILED_ANALYSIS_TIMEOUT_MS - 1);
    expect(engine.isBusy()).toBe(true);
    await vi.advanceTimersByTimeAsync(1);
    await assertion;
    expect(engine.isBusy()).toBe(false);
    expect(destroy).toHaveBeenCalled();
    if (stuck === 'late-page' || stuck === 'late-text') {
      resume(stuck === 'late-page' ? page : { items: [] });
      await vi.advanceTimersByTimeAsync(0);
      expect(page.render).not.toHaveBeenCalled();
      expect(page.cleanup).toHaveBeenCalledTimes(1);
      if (stuck === 'late-page') expect(page.getTextContent).not.toHaveBeenCalled();
    }
    if (stuck === 'render') {
      expect(cancel).toHaveBeenCalledTimes(1);
      expect(pdf.canvasFactory.destroy).toHaveBeenCalledTimes(1);
      expect(page.cleanup).toHaveBeenCalledTimes(1);
    }
  });
});
