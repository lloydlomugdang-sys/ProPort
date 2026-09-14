import type { PublicDocumentCategory } from '../../modules/documents/document.service.js';

/** Provider output is untrusted until validated by the recommendation service. */
export interface MetadataProvider {
  recommend(text: string, categories: readonly PublicDocumentCategory[]): Promise<unknown>;
}

export class MetadataProviderError extends Error {
  constructor(readonly category: 'timeout' | 'unavailable' | 'invalid_response') {
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
