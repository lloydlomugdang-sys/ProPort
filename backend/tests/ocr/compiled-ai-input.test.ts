import { expect, it } from 'vitest';
import { AiMetadataService, AI_MAX_INPUT_LENGTH } from '../../src/modules/documents/ai-metadata.service.js';
import { GeminiMetadataProvider } from '../../src/infrastructure/ai/gemini-metadata-provider.js';

it('normalizes numbered compiled text, strips credential lines, and never sends images or changes raw text', async () => {
  let sent: Record<string, unknown> | undefined;
  const provider = new GeminiMetadataProvider({ apiKey: 'test-only-placeholder', model: 'gemini-test', timeoutMs: 1000 }, async (_url, init) => {
    sent = JSON.parse(init!.body as string) as Record<string, unknown>;
    return new Response(JSON.stringify({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: '{"documents":[]}' }] } }] }), { status: 200 });
  });
  const service = new AiMetadataService(provider);
  const text = 'CERTIFICATE   OF PARTICIPATION\r\nAPI_KEY=not-a-real-secret\r\n   University    seminar\r\n\r\nStudent evidence';
  const pages = Array.from({ length: 100 }, (_, index) => ({ pageNumber: index + 1, text }));
  const original = JSON.stringify(pages);
  await service.separateCompiled(pages, []);
  const contents = sent!.contents as { parts: { text: string }[] }[];
  const payload = JSON.parse(contents[0]!.parts[0]!.text) as { pages: { pageNumber: number; text: string }[] };
  expect(payload.pages).toHaveLength(100);
  expect(payload.pages[0]!.text).toContain('CERTIFICATE OF PARTICIPATION\nUniversity seminar');
  expect(payload.pages.map((page) => page.text).join('')).not.toContain('not-a-real-secret');
  expect(payload.pages.reduce((sum, page) => sum + page.text.length, 0)).toBeLessThanOrEqual(AI_MAX_INPUT_LENGTH);
  expect(payload.pages[99]!.pageNumber).toBe(100);
  expect(JSON.stringify(pages)).toBe(original);
  expect(contents.every((content) => content.parts.every((part) => Object.keys(part).join() === 'text'))).toBe(true);
});
