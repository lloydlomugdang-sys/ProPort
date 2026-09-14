import { describe, expect, it, vi } from 'vitest';
import { loadConfig, loadDatabaseConfig } from '../../src/config/env.js';
import { CATEGORY_SEEDS } from '../../src/database/seeds/categories.seed.js';
import { GeminiMetadataProvider } from '../../src/infrastructure/ai/gemini-metadata-provider.js';
import { MetadataProviderError } from '../../src/infrastructure/ai/metadata-provider.js';
import { AiMetadataService, AI_MAX_INPUT_LENGTH, normalizeAiText, validateAiMetadata } from '../../src/modules/documents/ai-metadata.service.js';

const text = `CERTIFICATE OF COMPLETION
This certificate is proudly presented to
JUAN DELA CRUZ
for successfully completing the course
Introduction to Digital Documentation and OCR Systems
conducted by
GradPort Learning and Development Center
on September 14, 2026`;
const result = {
  content: 'Certificates', folder: 'Trainings', classificationEvidence: 'completing the course',
  title: 'Introduction to Digital Documentation and OCR Systems', date: '2026-09-14',
  descriptionQuotes: ['CERTIFICATE OF COMPLETION', 'Introduction to Digital Documentation and OCR Systems', 'conducted by GradPort Learning and Development Center'],
};
const config = { apiKey: 'test-only-gemini-key', model: 'gemini-test', timeoutMs: 100 };
const envelope = (output: unknown, finishReason = 'STOP') => JSON.stringify({
  candidates: [{ finishReason, content: { parts: [{ text: JSON.stringify(output) }] } }],
});

describe('backend Gemini configuration', () => {
  it('requires key/model only when enabled, sanitizes errors and bounds timeout', () => {
    expect(loadConfig({ NODE_ENV: 'test' }).aiProvider).toBe('none');
    expect(() => loadConfig({ NODE_ENV: 'test', AI_PROVIDER: 'gemini' })).toThrow('GEMINI_API_KEY is required');
    expect(() => loadConfig({ NODE_ENV: 'test', AI_PROVIDER: 'gemini', GEMINI_API_KEY: config.apiKey })).toThrow('GEMINI_MODEL is required');
    const env = { NODE_ENV: 'test', AI_PROVIDER: 'gemini', GEMINI_API_KEY: config.apiKey, GEMINI_MODEL: config.model };
    expect(loadConfig(env).gemini).toEqual({ ...config, timeoutMs: 20000 });
    for (const timeout of ['0', '-1', '30001', 'NaN']) {
      expect(() => loadConfig({ ...env, GEMINI_TIMEOUT_MS: timeout })).toThrow('GEMINI_TIMEOUT_MS');
    }
    expect(() => loadConfig({ ...env, GEMINI_MODEL: 'https://untrusted.invalid' })).toThrow('GEMINI_MODEL must');
    expect(() => loadConfig({ ...env, AI_PROVIDER: 'invalid' })).toThrow('AI_PROVIDER must');
    expect(() => loadDatabaseConfig({ NODE_ENV: 'test', AI_PROVIDER: 'gemini' })).not.toThrow();
  });
});

describe('Gemini text-only transport (no real requests)', () => {
  it('requests strict JSON using a key header, configurable model, one text-only call', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(new Response(envelope(result)));
    const provider = new GeminiMetadataProvider(config, fetcher);
    expect(await provider.recommend(text, CATEGORY_SEEDS)).toEqual(result);
    expect(fetcher).toHaveBeenCalledTimes(1);
    const [url, options] = fetcher.mock.calls[0]!;
    expect(url).toBe('https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent');
    expect(String(url)).not.toContain(config.apiKey);
    expect(options?.headers).toMatchObject({ 'x-goog-api-key': config.apiKey });
    expect(options?.redirect).toBe('error');
    const body = JSON.parse(String(options?.body)) as { generationConfig: Record<string, unknown>; contents: unknown[]; systemInstruction: unknown };
    expect(body.generationConfig).toMatchObject({ responseMimeType: 'application/json', candidateCount: 1 });
    expect(body.contents).toHaveLength(1);
    expect(JSON.stringify(body)).not.toMatch(/inlineData|fileData|test-only-gemini-key/);
    expect(JSON.stringify(body.systemInstruction)).toContain('Do not generate Reflection');
  });

  it.each([400, 401, 429, 500, 503])('sanitizes HTTP %s and never exposes provider details', async (status) => {
    const provider = new GeminiMetadataProvider(config, vi.fn<typeof fetch>().mockResolvedValue(new Response(`private ${config.apiKey}`, { status })));
    await expect(provider.recommend(text, [])).rejects.toThrow('AI metadata recommendations are temporarily unavailable.');
    await expect(new GeminiMetadataProvider(config, vi.fn<typeof fetch>().mockRejectedValue(new Error(config.apiKey))).recommend(text, [])).rejects.not.toThrow(config.apiKey);
  });

  it.each(['not json', '{}', envelope(result, 'MAX_TOKENS'), envelope(result, 'SAFETY'), JSON.stringify({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: '```json not JSON' }] } }] }), 'x'.repeat(65537)])('rejects malformed, blocked, truncated or oversized responses %#', async (body) => {
    const provider = new GeminiMetadataProvider(config, vi.fn<typeof fetch>().mockResolvedValue(new Response(body)));
    await expect(provider.recommend(text, [])).rejects.toBeInstanceOf(MetadataProviderError);
  });

  it('times out and aborts stalled headers or response bodies without retries', async () => {
    const fetcher = vi.fn<typeof fetch>().mockImplementation(() => new Promise(() => undefined));
    await expect(new GeminiMetadataProvider({ ...config, timeoutMs: 5 }, fetcher).recommend(text, [])).rejects.toMatchObject({ category: 'timeout' });
    expect(fetcher.mock.calls[0]![1]?.signal?.aborted).toBe(true);
    expect(fetcher).toHaveBeenCalledTimes(1);
    const stream = new ReadableStream<Uint8Array>({ start() {} });
    const bodyFetcher = vi.fn<typeof fetch>().mockResolvedValue(new Response(stream));
    await expect(new GeminiMetadataProvider({ ...config, timeoutMs: 5 }, bodyFetcher).recommend(text, [])).rejects.toMatchObject({ category: 'timeout' });
  });
});

describe('validated grounded recommendations and fallback', () => {
  it('classifies the certificate with useful title, date and grounded description; never Reflection', async () => {
    const recommend = vi.fn().mockResolvedValue(result);
    const response = await new AiMetadataService({ recommend }).recommend({ rawText: 'Ignored original', reviewedText: text }, CATEGORY_SEEDS);
    expect(response.metadataAnalysis).toEqual({ source: 'gemini', aiStatus: 'success' });
    expect(response.metadataSuggestions).toMatchObject({ categoryKey: 'certificates', folderKey: 'trainings', title: result.title, documentDate: '2026-09-14' });
    expect(response.metadataSuggestions.description).toContain('GradPort Learning and Development Center');
    expect(response.metadataSuggestions).not.toHaveProperty('reflection');
    expect(recommend).toHaveBeenCalledWith(text, CATEGORY_SEEDS);
  });

  it('accepts only current content/folder pairs, ignoring unknown or inactive values', () => {
    expect(validateAiMetadata({ ...result, content: 'Invented' }, text, CATEGORY_SEEDS)).not.toHaveProperty('categoryKey');
    expect(validateAiMetadata({ ...result, folder: 'projects' }, text, CATEGORY_SEEDS)).not.toHaveProperty('folderKey');
    expect(validateAiMetadata(result, text, [])).not.toHaveProperty('categoryKey');
    expect(validateAiMetadata({ ...result, content: ' certificates ', folder: 'TRAININGS' }, text, CATEGORY_SEEDS)).toMatchObject({ categoryKey: 'certificates', folderKey: 'trainings' });
    expect(validateAiMetadata({ ...result, classificationEvidence: 'Invented evidence' }, text, CATEGORY_SEEDS)).not.toHaveProperty('categoryKey');
  });

  it('rejects unsupported dates, invented titles/organizations, markup and recipient titles', () => {
    for (const date of ['tomorrow', '2026-02-30', '2026-09-15', '2026-9-14']) {
      expect(validateAiMetadata({ ...result, date }, text, CATEGORY_SEEDS)).not.toHaveProperty('documentDate');
    }
    for (const title of ['Imaginary course', 'JUAN DELA CRUZ', '<script>alert</script>', 'x'.repeat(251)]) {
      expect(validateAiMetadata({ ...result, title }, text, CATEGORY_SEEDS)).not.toHaveProperty('title');
    }
    expect(validateAiMetadata({ ...result, descriptionQuotes: ['Invented University'] }, text, CATEGORY_SEEDS)).not.toHaveProperty('description');
    expect(validateAiMetadata(result, text.replace('on September', 'expires September'), CATEGORY_SEEDS)).not.toHaveProperty('documentDate');
  });

  it.each([null, [], {}, { ...result, reflection: 'I learned a lot' }, { ...result, title: 123 }, { ...result, descriptionQuotes: 'Not an array' }])('falls back for malformed/extra properties %#', async (value) => {
    const response = await new AiMetadataService({ recommend: async () => value }).recommend({ rawText: text }, CATEGORY_SEEDS);
    expect(response.metadataAnalysis).toEqual({ source: 'rules', aiStatus: 'unavailable' });
    expect(response.metadataSuggestions).toMatchObject({ categoryKey: 'certificates', folderKey: 'trainings', title: result.title, documentDate: '2026-09-14' });
    expect(response.metadataSuggestions).not.toHaveProperty('reflection');
  });

  it('falls back on outage; no useful AI/rules still returns an empty usable result', async () => {
    const service = new AiMetadataService({ recommend: async () => { throw new Error(config.apiKey); } });
    expect((await service.recommend({ rawText: text }, CATEGORY_SEEDS)).metadataAnalysis.source).toBe('rules');
    const response = await service.recommend({ rawText: 'Unstructured miscellaneous document words' }, CATEGORY_SEEDS);
    expect(response).toEqual({ metadataSuggestions: {}, metadataAnalysis: { source: 'none', aiStatus: 'unavailable' } });
    expect(JSON.stringify(response)).not.toContain(config.apiKey);
  });

  it('bounds and normalizes text, preserves reviewed empty text and omits obvious credentials', async () => {
    expect(normalizeAiText('  Line one\t here\r\n\r\n\r\nNext line\nAPI_KEY=private\nGEMINI_API_KEY=private\nAUTH_JWT_SECRET=private\nAuthorization: Bearer private\nBearer private\neyJexample.payload.signature')).toBe('Line one here\n\nNext line');
    expect(normalizeAiText('x'.repeat(100000))).toHaveLength(AI_MAX_INPUT_LENGTH);
    const recommend = vi.fn().mockResolvedValue(result);
    const response = await new AiMetadataService({ recommend }).recommend({ rawText: text, reviewedText: '' }, CATEGORY_SEEDS);
    expect(recommend).not.toHaveBeenCalled();
    expect(response.metadataSuggestions).toEqual({});
    expect(response.metadataAnalysis.aiStatus).toBe('not_needed');
    expect((await new AiMetadataService().recommend({ rawText: text }, CATEGORY_SEEDS)).metadataAnalysis.aiStatus).toBe('disabled');
  });
});
