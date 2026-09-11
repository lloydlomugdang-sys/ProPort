const portfolioProperties = {
  fullName: { type: 'string', minLength: 1, maxLength: 200 },
  yearAndSection: { type: 'string', minLength: 1, maxLength: 100 },
  schedule: { type: 'string', minLength: 1, maxLength: 200 },
  instructorName: { type: 'string', minLength: 1, maxLength: 200 },
  course: { type: 'string', maxLength: 200 },
  courseCode: { type: 'string', maxLength: 100 },
  semesterAndYear: { type: 'string', maxLength: 100 },
} as const;

export const portfolioCreateBodySchema = {
  type: 'object',
  additionalProperties: false,
  required: [
    'fullName',
    'yearAndSection',
    'schedule',
    'instructorName',
    'course',
    'courseCode',
    'semesterAndYear',
  ],
  properties: portfolioProperties,
} as const;

export const portfolioPatchBodySchema = {
  type: 'object',
  additionalProperties: false,
  minProperties: 1,
  properties: portfolioProperties,
} as const;

export const portfolioPathParamsSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['portfolioId'],
  properties: {
    portfolioId: { type: 'string', pattern: '^[a-fA-F0-9]{24}$' },
  },
} as const;

export const portfolioQuerySchema = {
  type: 'object',
  additionalProperties: false,
  maxProperties: 0,
} as const;

const portfolioSchema = {
  type: 'object',
  additionalProperties: false,
  required: [
    'id',
    'fullName',
    'yearAndSection',
    'schedule',
    'instructorName',
    'course',
    'courseCode',
    'semesterAndYear',
    'createdAt',
    'updatedAt',
  ],
  properties: {
    id: { type: 'string' },
    ...portfolioProperties,
    createdAt: { type: 'string', format: 'date-time' },
    updatedAt: { type: 'string', format: 'date-time' },
  },
} as const;

const metaSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['requestId'],
  properties: { requestId: { type: 'string' } },
} as const;

export const portfolioResponseSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['data', 'meta'],
  properties: {
    data: {
      type: 'object',
      additionalProperties: false,
      required: ['portfolio'],
      properties: { portfolio: portfolioSchema },
    },
    meta: metaSchema,
  },
} as const;

export const portfolioListResponseSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['data', 'meta'],
  properties: {
    data: {
      type: 'object',
      additionalProperties: false,
      required: ['portfolios'],
      properties: {
        portfolios: { type: 'array', items: portfolioSchema },
      },
    },
    meta: metaSchema,
  },
} as const;

export const portfolioDeleteResponseSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['data', 'meta'],
  properties: {
    data: {
      type: 'object',
      additionalProperties: false,
      required: ['status', 'portfolioId'],
      properties: {
        status: { type: 'string', const: 'deleted' },
        portfolioId: { type: 'string' },
      },
    },
    meta: metaSchema,
  },
} as const;
