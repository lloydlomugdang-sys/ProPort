import type { FastifyBaseLogger } from 'fastify';
import type { MetadataProvider } from '../../infrastructure/ai/metadata-provider.js';
import { MetadataProviderError, metadataRecommendationSchema } from '../../infrastructure/ai/metadata-provider.js';
import type { PublicDocumentCategory } from './document.service.js';
import { resolveCanonicalTaxonomy, suggestDocumentMetadata, type MetadataSuggestions } from './metadata-suggestion.service.js';

export const AI_MAX_INPUT_LENGTH = 12_000;

export interface MetadataAnalysis {
  readonly source: 'gemini' | 'rules' | 'none';
  readonly aiStatus: 'success' | 'unavailable' | 'disabled' | 'not_needed';
}

/** Preserve line boundaries; omit obvious credentials if they occur in a document. */
export function normalizeAiText(text: string): string {
  return text.slice(0, AI_MAX_INPUT_LENGTH * 2).normalize('NFKC').replace(/\r\n?/g, '\n')
    .split('\n').filter((line) => !/\b[\w.-]*(?:password|passwd|authorization|api[_ -]?key|access[_ -]?token|refresh[_ -]?token|reset[_ -]?token|secret|pepper)\b\s*[:=]|\bBearer\s+\S+|\beyJ[\w-]+\.[\w-]+\.[\w-]+/i.test(line))
    .map((line) => line.replace(/[^\S\n]+/g, ' ').trim()).join('\n')
    .replace(/\n{3,}/g, '\n\n').trim().slice(0, AI_MAX_INPUT_LENGTH);
}

function plainText(value: unknown, max: number): string | undefined {
  if (typeof value !== 'string' || value.length > max || /[<>]/.test(value)) return undefined;
  const result = value.normalize('NFKC').replace(/\p{Cc}|\p{Cf}/gu, ' ').replace(/\s+/g, ' ').trim();
  return result.length > 0 && result.length <= max && !/[<>]/.test(result) ? result : undefined;
}

function comparable(value: string): string {
  return value.normalize('NFKC').replace(/\s+/g, ' ').trim().toLowerCase();
}

function grounded(value: string | undefined, text: string): value is string {
  return value !== undefined && value.length >= 4 && comparable(text).includes(comparable(value));
}

/** Service-level validation mirrors the strict JSON schema; no coercion of AI values. */
export function validateAiMetadata(value: unknown, text: string, categories: readonly PublicDocumentCategory[]): MetadataSuggestions {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new MetadataProviderError('invalid_response', 'AI_SCHEMA_VALIDATION_FAILED');
  }
  const record = value as Record<string, unknown>;
  const keys = metadataRecommendationSchema.required;
  if (Object.keys(record).some((key) => !keys.includes(key as typeof keys[number])) ||
      keys.some((key) => !Object.hasOwn(record, key)) ||
      keys.filter((key) => key !== 'descriptionQuotes').some((key) => record[key] !== null && typeof record[key] !== 'string') ||
      !Array.isArray(record.descriptionQuotes) || record.descriptionQuotes.length > 3 ||
      record.descriptionQuotes.some((quote: unknown) => typeof quote !== 'string')) {
    throw new MetadataProviderError('invalid_response', 'AI_SCHEMA_VALIDATION_FAILED');
  }
  const evidence = plainText(record.classificationEvidence, 500);
  const content = plainText(record.content, 100);
  const folder = plainText(record.folder, 100);
  const resolved = grounded(evidence, text) && content !== undefined
    ? resolveCanonicalTaxonomy(content, folder, categories)
    : {};
  const category = resolved.category;
  const matchedFolderKey = resolved.folderKey;
  const title = plainText(record.title, 250);
  // Recipient lines are evidence of identity, not of an activity title.
  const recipients = [...text.matchAll(/(?:presented|awarded|issued)\s+to[^\S\n]*\n?([^\n]+)/gi)]
    .map((match) => comparable(match[1]!.split(/\s+for\b/i)[0]!));
  const isCertificateCategory = category?.key === 'certificates';
  const safeTitle = grounded(title, text) &&
    (!isCertificateCategory || (!recipients.includes(comparable(title)) && !/^certificate\s+of\s+/i.test(title)))
    ? title : undefined;

  const date = plainText(record.date, 10);
  let documentDate: string | undefined;
  if (date !== undefined && /^\d{4}-\d{2}-\d{2}$/.test(date)) {
    const supportedDate = suggestDocumentMetadata({ rawText: text }, []).documentDate;
    if (date === supportedDate) {
      documentDate = date;
    } else {
      const [y, m, d] = date.split('-').map(Number);
      if (y && m && d && y >= 1990 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        const testDate = new Date(Date.UTC(y, m - 1, d));
        if (testDate.getUTCFullYear() === y && testDate.getUTCMonth() === m - 1 && testDate.getUTCDate() === d) {
          const yearStr = String(y);
          const dayStr = String(d);
          if (text.includes(yearStr) && (text.includes(dayStr) || text.toLowerCase().includes(String(m)))) {
            const beforeMatch = text.slice(0, Math.max(0, text.indexOf(yearStr)));
            if (!/\b(?:birth|born|expires?|expiry|expiration|valid until)\b/i.test(beforeMatch)) {
              documentDate = date;
            }
          }
        }
      }
    }
  }
  const quotes = record.descriptionQuotes.map((quote: unknown) => plainText(quote, 600));
  const description = quotes.length > 0 && quotes.every((quote) => grounded(quote, text))
    ? quotes.join(' — ') : undefined;

  const hasMeaningfulField = category !== undefined || safeTitle !== undefined || documentDate !== undefined || description !== undefined;
  if (!hasMeaningfulField) {
    return {};
  }

  let confidence: 'high' | 'medium' | 'low';
  if (category !== undefined) {
    if (safeTitle !== undefined && documentDate !== undefined) {
      confidence = 'high';
    } else if (safeTitle !== undefined || matchedFolderKey !== undefined) {
      confidence = 'medium';
    } else {
      confidence = 'low';
    }
  } else {
    confidence = 'low';
  }

  return {
    ...(category === undefined ? {} : { categoryKey: category.key }),
    ...(matchedFolderKey === undefined ? {} : { folderKey: matchedFolderKey }),
    ...(safeTitle === undefined ? {} : { title: safeTitle }),
    ...(documentDate === undefined ? {} : { documentDate }),
    ...(description === undefined ? {} : { description }),
    confidence,
  };
}

export class AiMetadataService {
  constructor(
    private readonly provider?: MetadataProvider,
    private readonly logger?: Pick<FastifyBaseLogger, 'info' | 'warn'>,
  ) {}

  async recommend(ocr: { readonly reviewedText?: string; readonly rawText?: string }, categories: readonly PublicDocumentCategory[], requestId?: string): Promise<{
    metadataSuggestions: MetadataSuggestions; metadataAnalysis: MetadataAnalysis;
  }> {
    // Reviewed empty text is authoritative. Never send session, user, filename or file bytes.
    const text = normalizeAiText(ocr.reviewedText ?? ocr.rawText ?? '');
    let aiStatus: MetadataAnalysis['aiStatus'] = this.provider === undefined ? 'disabled' : 'not_needed';
    if (this.provider !== undefined && text.length >= 20) {
      const startedAt = performance.now();
      let received = false;
      try {
        const output = await this.provider.recommend(text, categories);
        received = true;
        const metadataSuggestions = validateAiMetadata(output, text, categories);
        if (Object.keys(metadataSuggestions).length > 0) {
          this.logger?.info({
            requestId, provider: 'gemini', model: this.provider.model ?? 'unknown',
            code: 'AI_SUCCESS', httpStatus: 200, latencyMs: Math.round(performance.now() - startedAt),
          }, 'AI metadata suggestions accepted.');
          return { metadataSuggestions, metadataAnalysis: { source: 'gemini', aiStatus: 'success' } };
        }
        throw new MetadataProviderError('invalid_response', 'AI_GROUNDING_REJECTED');
      } catch (error) {
        // An outage, unsafe answer or malformed output must not turn successful OCR into an error.
        // Whitelist only diagnostics we created ourselves, never the error/message,
        // provider response, request body, OCR text, or rejected metadata values.
        const failure = error instanceof MetadataProviderError ? error : new MetadataProviderError('unavailable');
        this.logger?.warn({
          requestId, provider: 'gemini', model: this.provider.model ?? 'unknown',
          code: failure.code, httpStatus: failure.httpStatus ?? (received ? 200 : undefined),
          latencyMs: Math.round(performance.now() - startedAt),
        }, 'AI metadata unavailable; using deterministic fallback.');
      }
      aiStatus = 'unavailable';
    }
    let metadataSuggestions: MetadataSuggestions = {};
    try {
      metadataSuggestions = suggestDocumentMetadata(ocr, categories);
      if (Object.keys(metadataSuggestions).length > 0 && !metadataSuggestions.confidence) {
        const hasCategory = metadataSuggestions.categoryKey !== undefined;
        const hasTitle = metadataSuggestions.title !== undefined;
        const hasDate = metadataSuggestions.documentDate !== undefined;
        let confidence: 'high' | 'medium' | 'low';
        if (hasCategory && hasTitle && hasDate) {
          confidence = 'high';
        } else if (hasCategory && (hasTitle || metadataSuggestions.folderKey !== undefined)) {
          confidence = 'medium';
        } else if (hasCategory) {
          confidence = 'medium';
        } else {
          confidence = 'low';
        }
        metadataSuggestions = { ...metadataSuggestions, confidence };
      }
    } catch {
      // Even if neither recommender can help, the extracted text remains usable.
    }
    return {
      metadataSuggestions,
      metadataAnalysis: { source: Object.keys(metadataSuggestions).length ? 'rules' : 'none', aiStatus },
    };
  }
}
