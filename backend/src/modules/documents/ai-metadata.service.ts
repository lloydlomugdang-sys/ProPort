import type { MetadataProvider } from '../../infrastructure/ai/metadata-provider.js';
import { metadataRecommendationSchema } from '../../infrastructure/ai/metadata-provider.js';
import type { PublicDocumentCategory } from './document.service.js';
import { suggestDocumentMetadata, type MetadataSuggestions } from './metadata-suggestion.service.js';

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
  if (typeof value !== 'object' || value === null || Array.isArray(value)) throw new Error('Invalid AI metadata.');
  const record = value as Record<string, unknown>;
  const keys = metadataRecommendationSchema.required;
  if (Object.keys(record).some((key) => !keys.includes(key as typeof keys[number])) ||
      keys.some((key) => !Object.hasOwn(record, key)) ||
      keys.filter((key) => key !== 'descriptionQuotes').some((key) => record[key] !== null && typeof record[key] !== 'string') ||
      !Array.isArray(record.descriptionQuotes) || record.descriptionQuotes.length > 3 ||
      record.descriptionQuotes.some((quote: unknown) => typeof quote !== 'string')) {
    throw new Error('Invalid AI metadata.');
  }
  const evidence = plainText(record.classificationEvidence, 500);
  const content = plainText(record.content, 100);
  const folder = plainText(record.folder, 100);
  const category = grounded(evidence, text) && content !== undefined
    ? categories.find((item) => [item.key, item.name].some((key) => comparable(key) === comparable(content))) : undefined;
  const matchedFolder = category?.folders.find((item) => folder !== undefined &&
    [item.key, item.name].some((key) => comparable(key) === comparable(folder)));
  const title = plainText(record.title, 250);
  // Recipient lines are evidence of identity, not of an activity title.
  const recipients = [...text.matchAll(/(?:presented|awarded|issued)\s+to[^\S\n]*\n?([^\n]+)/gi)]
    .map((match) => comparable(match[1]!.split(/\s+for\b/i)[0]!));
  const safeTitle = grounded(title, text) && !recipients.includes(comparable(title)) &&
    !/^certificate\s+of\s+/i.test(title) ? title : undefined;
  const date = plainText(record.date, 10);
  // Conservative calendar/evidence check also excludes DOB, expiry and ambiguous dates.
  const supportedDate = suggestDocumentMetadata({ rawText: text }, []).documentDate;
  const documentDate = date !== undefined && /^\d{4}-\d{2}-\d{2}$/.test(date) && date === supportedDate ? date : undefined;
  const quotes = record.descriptionQuotes.map((quote: unknown) => plainText(quote, 600));
  const description = quotes.length > 0 && quotes.every((quote) => grounded(quote, text))
    ? quotes.join(' — ') : undefined;
  return {
    ...(category === undefined ? {} : { categoryKey: category.key }),
    ...(matchedFolder === undefined ? {} : { folderKey: matchedFolder.key }),
    ...(safeTitle === undefined ? {} : { title: safeTitle }),
    ...(documentDate === undefined ? {} : { documentDate }),
    ...(description === undefined ? {} : { description }),
  };
}

export class AiMetadataService {
  constructor(private readonly provider?: MetadataProvider) {}

  async recommend(ocr: { readonly reviewedText?: string; readonly rawText?: string }, categories: readonly PublicDocumentCategory[]): Promise<{
    metadataSuggestions: MetadataSuggestions; metadataAnalysis: MetadataAnalysis;
  }> {
    // Reviewed empty text is authoritative. Never send session, user, filename or file bytes.
    const text = normalizeAiText(ocr.reviewedText ?? ocr.rawText ?? '');
    let aiStatus: MetadataAnalysis['aiStatus'] = this.provider === undefined ? 'disabled' : 'not_needed';
    if (this.provider !== undefined && text.length >= 20) {
      try {
        const metadataSuggestions = validateAiMetadata(await this.provider.recommend(text, categories), text, categories);
        if (Object.keys(metadataSuggestions).length > 0) {
          return { metadataSuggestions, metadataAnalysis: { source: 'gemini', aiStatus: 'success' } };
        }
      } catch {
        // An outage, unsafe answer or malformed output must not turn successful OCR into an error.
      }
      aiStatus = 'unavailable';
    }
    let metadataSuggestions: MetadataSuggestions = {};
    try {
      metadataSuggestions = suggestDocumentMetadata(ocr, categories);
    } catch {
      // Even if neither recommender can help, the extracted text remains usable.
    }
    return {
      metadataSuggestions,
      metadataAnalysis: { source: Object.keys(metadataSuggestions).length ? 'rules' : 'none', aiStatus },
    };
  }
}
