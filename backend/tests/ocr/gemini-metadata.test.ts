import Fastify from 'fastify';
import { describe, expect, it, vi } from 'vitest';
import { createLoggerOptions } from '../../src/common/logging/logger-options.js';
import { loadConfig, loadDatabaseConfig } from '../../src/config/env.js';
import { CATEGORY_SEEDS } from '../../src/database/seeds/categories.seed.js';
import { GeminiMetadataProvider } from '../../src/infrastructure/ai/gemini-metadata-provider.js';
import { MetadataProviderError, metadataRecommendationSchema } from '../../src/infrastructure/ai/metadata-provider.js';
import { AiMetadataService, AI_MAX_INPUT_LENGTH, normalizeAiText, validateAiMetadata } from '../../src/modules/documents/ai-metadata.service.js';
import { DocumentService } from '../../src/modules/documents/document.service.js';
import { createTestServices } from '../helpers/build-test-app.js';

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
    expect(body.generationConfig).toEqual({
      responseMimeType: 'application/json', responseJsonSchema: metadataRecommendationSchema, maxOutputTokens: 4096,
    });
    expect(body.generationConfig).not.toHaveProperty('candidateCount');
    expect(body.generationConfig).not.toHaveProperty('responseSchema');
    expect(body.generationConfig).not.toHaveProperty('thinkingConfig');
    expect(body.contents).toHaveLength(1);
    expect(JSON.stringify(body)).not.toMatch(/inlineData|fileData|test-only-gemini-key/);
    expect(JSON.stringify(body.systemInstruction)).toContain('Do not generate Reflection');
  });

  it('uses the Gemini 3.5 structured request without legacy candidateCount or sampling options', async () => {
    const fetcher = vi.fn<typeof fetch>().mockImplementation(async (_url, options) => {
      const body = JSON.parse(String(options?.body)) as { generationConfig: Record<string, unknown> };
      // A configured model can reject unsupported options even when a plain
      // hello-world request with the same key/model succeeds.
      if (Object.hasOwn(body.generationConfig, 'candidateCount')) return new Response('', { status: 400 });
      expect(body.generationConfig).toEqual({
        maxOutputTokens: 4096, thinkingConfig: { thinkingLevel: 'LOW' },
        responseMimeType: 'application/json', responseJsonSchema: metadataRecommendationSchema,
      });
      return new Response(envelope(result));
    });
    const provider = new GeminiMetadataProvider({ ...config, model: 'gemini-3.5-flash' }, fetcher);
    expect(await provider.recommend(text, CATEGORY_SEEDS)).toEqual(result);
    expect(fetcher.mock.calls[0]![0]).toBe('https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent');
  });

  it('accepts split JSON text parts while excluding thought parts', async () => {
    const json = JSON.stringify(result);
    const body = JSON.stringify({ candidates: [{ finishReason: 'STOP', content: { role: 'model', parts: [
      { thought: true, text: 'Private reasoning must not become metadata.' },
      { text: json.slice(0, 50), thoughtSignature: 'opaque-signature' },
      { text: json.slice(50) },
    ] } }] });
    const provider = new GeminiMetadataProvider(config, vi.fn<typeof fetch>().mockResolvedValue(new Response(body)));
    expect(await provider.recommend(text, CATEGORY_SEEDS)).toEqual(result);
  });

  it.each([400, 401, 403, 404, 429, 500, 503])('sanitizes HTTP %s and never exposes provider details', async (status) => {
    const provider = new GeminiMetadataProvider(config, vi.fn<typeof fetch>().mockResolvedValue(new Response(`private ${config.apiKey}`, { status })));
    await expect(provider.recommend(text, [])).rejects.toMatchObject({
      message: 'AI metadata recommendations are temporarily unavailable.', code: `AI_HTTP_${status}`, httpStatus: status,
    });
    await expect(new GeminiMetadataProvider(config, vi.fn<typeof fetch>().mockRejectedValue(new Error(config.apiKey))).recommend(text, [])).rejects.not.toThrow(config.apiKey);
  });

  it.each(['not json', '{}', envelope(result, 'MAX_TOKENS'), envelope(result, 'SAFETY'), JSON.stringify({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: '```json not JSON' }] } }] }), 'x'.repeat(65537)])('rejects malformed, blocked, truncated or oversized responses %#', async (body) => {
    const provider = new GeminiMetadataProvider(config, vi.fn<typeof fetch>().mockResolvedValue(new Response(body)));
    await expect(provider.recommend(text, [])).rejects.toBeInstanceOf(MetadataProviderError);
  });

  it('times out and aborts stalled headers or response bodies without retries', async () => {
    const fetcher = vi.fn<typeof fetch>().mockImplementation(() => new Promise(() => undefined));
    await expect(new GeminiMetadataProvider({ ...config, timeoutMs: 5 }, fetcher).recommend(text, [])).rejects.toMatchObject({ category: 'timeout', code: 'AI_TIMEOUT' });
    expect(fetcher.mock.calls[0]![1]?.signal?.aborted).toBe(true);
    expect(fetcher).toHaveBeenCalledTimes(1);
    const cancel = vi.fn();
    const stream = new ReadableStream<Uint8Array>({ start() {}, cancel });
    const bodyFetcher = vi.fn<typeof fetch>().mockResolvedValue(new Response(stream));
    await expect(new GeminiMetadataProvider({ ...config, timeoutMs: 5 }, bodyFetcher).recommend(text, [])).rejects.toMatchObject({ category: 'timeout' });
    expect(cancel).toHaveBeenCalledTimes(1);
  });
});

describe('sanitized AI diagnostics through real logger serialization', () => {
  const privateValue = 'private-document-and-provider-error-sentinel';
  const ungrounded = {
    content: 'Unknown', folder: 'Unknown', classificationEvidence: privateValue,
    title: privateValue, date: '2027-01-01', descriptionQuotes: [privateValue],
  };
  const cases = [
    { code: 'AI_SUCCESS', body: envelope(result), status: 200 },
    ...[400, 401, 403, 404, 429, 500, 503].map((status) => ({
      code: `AI_HTTP_${status}`, status,
      body: JSON.stringify({ error: { code: status, message: `${config.apiKey} ${privateValue} ${text}` } }),
    })),
    { code: 'AI_INVALID_JSON', body: `not-json ${privateValue}`, status: 200 },
    { code: 'AI_INVALID_JSON', body: JSON.stringify({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: privateValue }] } }] }), status: 200 },
    { code: 'AI_INVALID_RESPONSE', body: '{}', status: 200 },
    { code: 'AI_RESPONSE_TOO_LARGE', body: 'x'.repeat(65537), status: 200 },
    { code: 'AI_RESPONSE_TRUNCATED', body: envelope(result, 'MAX_TOKENS'), status: 200 },
    { code: 'AI_RESPONSE_BLOCKED', body: envelope(result, 'SAFETY'), status: 200 },
    { code: 'AI_RESPONSE_BLOCKED', body: JSON.stringify({ promptFeedback: { blockReason: 'SAFETY' } }), status: 200 },
    { code: 'AI_SCHEMA_VALIDATION_FAILED', body: envelope({ ...result, reflection: privateValue }), status: 200 },
    { code: 'AI_GROUNDING_REJECTED', body: envelope(ungrounded), status: 200 },
    { code: 'AI_TIMEOUT', body: '', status: undefined },
    { code: 'AI_PROVIDER_ERROR', body: '', status: undefined },
  ];

  it.each(cases)('$code (HTTP $status) is request-linked, sanitized and selects the right source', async (testCase) => {
    const messages: string[] = [];
    const options = createLoggerOptions('info');
    if (options === false) throw new Error('Test logging must be enabled.');
    const app = Fastify({ logger: { ...options, stream: { write: (message: string) => { messages.push(message); } } } });
    try {
      const fetcher = vi.fn<typeof fetch>().mockImplementation(async () => {
        if (testCase.code === 'AI_TIMEOUT') return new Promise(() => undefined);
        if (testCase.code === 'AI_PROVIDER_ERROR') throw new Error(`${config.apiKey} ${privateValue} ${text}`);
        return new Response(testCase.body, { status: testCase.status ?? 200 });
      });
      const provider = new GeminiMetadataProvider({ ...config, model: 'gemini-3.5-flash', timeoutMs: 20 }, fetcher);
      const response = await new AiMetadataService(provider, app.log).recommend({ rawText: text }, CATEGORY_SEEDS, 'test-request-id');
      const success = testCase.code === 'AI_SUCCESS';
      expect(response.metadataAnalysis).toEqual({ source: success ? 'gemini' : 'rules', aiStatus: success ? 'success' : 'unavailable' });
      expect(response.metadataSuggestions).toMatchObject({ categoryKey: 'certificates', folderKey: 'trainings', title: result.title, documentDate: result.date });
      expect(response.metadataSuggestions).not.toHaveProperty('reflection');
      expect(messages).toHaveLength(1);
      const log = JSON.parse(messages[0]!) as Record<string, unknown>;
      expect(log).toMatchObject({
        level: success ? 30 : 40, requestId: 'test-request-id', provider: 'gemini', model: 'gemini-3.5-flash',
        code: testCase.code, latencyMs: expect.any(Number),
      });
      expect(log.latencyMs).toBeGreaterThanOrEqual(0);
      expect(log.httpStatus).toBe(testCase.status);
      for (const secret of [privateValue, config.apiKey, text, result.title, 'JUAN DELA CRUZ', 'generativelanguage.googleapis.com']) {
        expect(messages.join('')).not.toContain(secret);
      }
      expect(log).not.toHaveProperty('err');
      expect(log).not.toHaveProperty('error');
      expect(fetcher).toHaveBeenCalledTimes(1);
    } finally {
      await app.close();
    }
  });
});

describe('validated grounded recommendations and fallback', () => {
  it('carries the preview request ID into diagnostics, never into the provider input', async () => {
    const recommend = vi.fn().mockResolvedValue(result);
    const logger = { info: vi.fn(), warn: vi.fn() };
    const services = createTestServices();
    const documents = new DocumentService(services.database, services.storage, {
      extract: async () => ({ rawText: text, engine: 'pdfjs' }),
    }, new AiMetadataService({ recommend, model: config.model }, logger));
    vi.spyOn(documents, 'listCategories').mockResolvedValue(CATEGORY_SEEDS);
    const response = await documents.previewOcr({
      originalFileName: 'private-filename.pdf', mimeType: 'application/pdf',
      contents: Buffer.from('%PDF-1.4\n%%EOF'),
    }, 'server-preview-request');
    expect(response.metadataAnalysis).toEqual({ source: 'gemini', aiStatus: 'success' });
    expect(recommend).toHaveBeenCalledWith(text, CATEGORY_SEEDS);
    expect(logger.info).toHaveBeenCalledWith(expect.objectContaining({ requestId: 'server-preview-request', code: 'AI_SUCCESS' }), expect.any(String));
    expect(JSON.stringify(logger.info.mock.calls)).not.toContain('private-filename');
  });

  it('classifies the certificate with useful title, date and grounded description; never Reflection', async () => {
    const recommend = vi.fn().mockResolvedValue(result);
    const response = await new AiMetadataService({ recommend }).recommend({ rawText: 'Ignored original', reviewedText: text }, CATEGORY_SEEDS);
    expect(response.metadataAnalysis).toEqual({ source: 'gemini', aiStatus: 'success' });
    expect(response.metadataSuggestions).toMatchObject({ categoryKey: 'certificates', folderKey: 'trainings', title: result.title, documentDate: '2026-09-14', confidence: 'high' });
    expect(response.metadataSuggestions.description).toContain('GradPort Learning and Development Center');
    expect(response.metadataSuggestions).not.toHaveProperty('reflection');
    expect(recommend).toHaveBeenCalledWith(text, CATEGORY_SEEDS);
  });

  it('evaluates confidence level: high, medium, or low based on field presence and grounding', () => {
    // High: category + title + date
    const high = validateAiMetadata(result, text, CATEGORY_SEEDS);
    expect(high.confidence).toBe('high');

    // Medium: category + title, no date
    const mediumWithTitle = validateAiMetadata({ ...result, date: null }, text, CATEGORY_SEEDS);
    expect(mediumWithTitle.confidence).toBe('medium');

    // Medium: category + folder, no title or date
    const mediumWithFolder = validateAiMetadata({ ...result, title: null, date: null }, text, CATEGORY_SEEDS);
    expect(mediumWithFolder.confidence).toBe('medium');

    // Low: ungrounded/unknown category with only grounded title
    const lowNoCategory = validateAiMetadata({ ...result, content: 'Invented Category', classificationEvidence: 'completing the course', date: null }, text, CATEGORY_SEEDS);
    expect(lowNoCategory.confidence).toBe('low');
    expect(lowNoCategory).not.toHaveProperty('categoryKey');
    expect(lowNoCategory).toHaveProperty('title');
  });

  it('accepts only current content/folder pairs, ignoring unknown or inactive values', () => {
    expect(validateAiMetadata({ ...result, content: 'Invented' }, text, CATEGORY_SEEDS)).not.toHaveProperty('categoryKey');
    expect(validateAiMetadata({ ...result, folder: 'projects' }, text, CATEGORY_SEEDS)).not.toHaveProperty('folderKey');
    expect(validateAiMetadata(result, text, [])).not.toHaveProperty('categoryKey');
    expect(validateAiMetadata({ ...result, content: ' certificates ', folder: 'TRAININGS' }, text, CATEGORY_SEEDS)).toMatchObject({ categoryKey: 'certificates', folderKey: 'trainings' });
    expect(validateAiMetadata({ ...result, classificationEvidence: 'Invented evidence' }, text, CATEGORY_SEEDS)).not.toHaveProperty('categoryKey');
  });

  it('maps internal document type aliases to canonical GradPort categories and folders', () => {
    expect(validateAiMetadata({ ...result, content: 'resume', folder: null }, text, CATEGORY_SEEDS))
      .toMatchObject({ categoryKey: 'curriculum-vitae', folderKey: 'curriculum-vitae' });
    expect(validateAiMetadata({ ...result, content: 'transcripts', folder: null }, text, CATEGORY_SEEDS))
      .toMatchObject({ categoryKey: 'scholastic-record', folderKey: 'unofficial-tor-with-reflections' });
    expect(validateAiMetadata({ ...result, content: 'certifications', folder: null }, text, CATEGORY_SEEDS))
      .toMatchObject({ categoryKey: 'certificates', folderKey: 'trainings' });
    expect(validateAiMetadata({ ...result, content: 'thesis', folder: null }, text, CATEGORY_SEEDS))
      .toMatchObject({ categoryKey: 'accomplishments', folderKey: 'thesis-capstone' });
    expect(validateAiMetadata({ ...result, content: 'award', folder: null }, text, CATEGORY_SEEDS))
      .toMatchObject({ categoryKey: 'other-achievements', folderKey: 'projects' });
    expect(validateAiMetadata({ ...result, content: 'OJT', folder: null }, text, CATEGORY_SEEDS))
      .toMatchObject({ categoryKey: 'college-report', folderKey: 'college-report' });
    expect(validateAiMetadata({ ...result, content: 'creative title artifact', folder: null }, text, CATEGORY_SEEDS))
      .toMatchObject({ categoryKey: 'curriculum-vitae', folderKey: 'creative-title' });
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
