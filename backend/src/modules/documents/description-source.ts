import { AppError } from '../../common/errors/app-error.js';

export const DESCRIPTION_SOURCES = ['user', 'confirmed', 'suggested', 'unknown'] as const;
export type DescriptionSource = (typeof DESCRIPTION_SOURCES)[number];
export const descriptionSourceSchema = { enum: DESCRIPTION_SOURCES } as const;
export function descriptionSource(value: unknown): DescriptionSource {
  if (value === undefined) return 'unknown';
  if (DESCRIPTION_SOURCES.includes(value as DescriptionSource)) return value as DescriptionSource;
  throw new AppError(400, 'VALIDATION_ERROR', 'The request is invalid.', { descriptionSource: ['must be user, confirmed, suggested, or unknown'] });
}
/** Legacy non-empty text is not proof of consent. Never infer provenance from prose. */
export function exportDescription(document: { description?: string; descriptionSource?: DescriptionSource }): string | undefined {
  return document.descriptionSource === 'user' || document.descriptionSource === 'confirmed' ? document.description?.trim() || undefined : undefined;
}
