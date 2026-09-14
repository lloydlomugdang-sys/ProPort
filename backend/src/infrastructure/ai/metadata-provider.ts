import type { PublicDocumentCategory } from '../../modules/documents/document.service.js';

/** Provider output is untrusted until validated by the recommendation service. */
export interface MetadataProvider {
  readonly model?: string;
  recommend(text: string, categories: readonly PublicDocumentCategory[]): Promise<unknown>;
}

export type MetadataFailureCode =
  | 'AI_PROVIDER_ERROR'
  | `AI_HTTP_${number}`
  | 'AI_TIMEOUT'
  | 'AI_INVALID_JSON'
  | 'AI_INVALID_RESPONSE'
  | 'AI_RESPONSE_TOO_LARGE'
  | 'AI_RESPONSE_TRUNCATED'
  | 'AI_RESPONSE_BLOCKED'
  | 'AI_SCHEMA_VALIDATION_FAILED'
  | 'AI_GROUNDING_REJECTED';

/** Only locally generated diagnostics; never retain raw provider errors/causes. */
export class MetadataProviderError extends Error {
  constructor(
    readonly category: 'timeout' | 'unavailable' | 'invalid_response',
    readonly code: MetadataFailureCode = category === 'timeout' ? 'AI_TIMEOUT'
      : category === 'unavailable' ? 'AI_PROVIDER_ERROR' : 'AI_INVALID_RESPONSE',
    readonly httpStatus?: number,
  ) {
    super('AI metadata recommendations are temporarily unavailable.');
    this.name = 'MetadataProviderError';
  }
}

// A deliberately small JSON schema; mirrored by strict runtime validation.
// Extractive description snippets allow grounding checks without trusting prose.
export const metadataRecommendationSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['content', 'folder', 'classificationEvidence', 'title', 'date', 'descriptionQuotes'],
  properties: {
    content: { type: ['string', 'null'] },
    folder: { type: ['string', 'null'] },
    classificationEvidence: { type: ['string', 'null'] },
    title: { type: ['string', 'null'] },
    date: { type: ['string', 'null'] },
    descriptionQuotes: { type: 'array', maxItems: 3, items: { type: 'string' } },
  },
} as const;
