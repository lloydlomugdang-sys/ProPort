import { AppError } from '../../common/errors/app-error.js';

export interface ScholasticDetails {
  readonly studyYear?: number;
  readonly semester?: '1st Semester' | '2nd Semester';
  readonly reflectionIncluded: boolean;
}

export const scholasticDetailsSchema = {
  type: 'object', additionalProperties: false, required: ['reflectionIncluded'],
  properties: {
    studyYear: { type: 'integer', minimum: 1, maximum: 20 },
    semester: { type: 'string', enum: ['1st Semester', '2nd Semester'] },
    reflectionIncluded: { type: 'boolean' },
  },
} as const;

export function validateScholasticDetails(value: unknown): ScholasticDetails | undefined {
  if (value === undefined) return undefined;
  const invalid = () => new AppError(400, 'VALIDATION_ERROR', 'Invalid scholastic coverage details.');
  if (typeof value !== 'object' || value === null || Array.isArray(value)) throw invalid();
  const input = value as Record<string, unknown>;
  if (Object.keys(input).some((key) => !['studyYear', 'semester', 'reflectionIncluded'].includes(key)) ||
      typeof input.reflectionIncluded !== 'boolean' ||
      (input.studyYear !== undefined && (!Number.isInteger(input.studyYear) || Number(input.studyYear) < 1 || Number(input.studyYear) > 20)) ||
      (input.semester !== undefined && !['1st Semester', '2nd Semester'].includes(String(input.semester)))) throw invalid();
  return input as unknown as ScholasticDetails;
}

export function requireTorReflection(category: string, folder: string, reflection?: string, details?: ScholasticDetails): void {
  if (category === 'scholastic-record' && folder === 'unofficial-tor-with-reflections' && !reflection?.trim() && details?.reflectionIncluded !== true) {
    throw new AppError(400, 'VALIDATION_ERROR', 'Enter a TOR reflection or confirm that it is already included in the uploaded document.', {
      reflection: ['A reflection or confirmation of an included reflection is required.'],
    });
  }
}
