export const healthResponseSchema = {
  type: 'object',
  required: ['data', 'meta'],
  additionalProperties: false,
  properties: {
    data: {
      type: 'object',
      required: ['status', 'service', 'timestamp'],
      additionalProperties: false,
      properties: {
        status: { const: 'ok' },
        service: { const: 'gradport-api' },
        timestamp: { type: 'string', format: 'date-time' },
      },
    },
    meta: {
      type: 'object',
      required: ['requestId'],
      additionalProperties: false,
      properties: { requestId: { type: 'string' } },
    },
  },
} as const;

const readinessChecksSchema = {
  type: 'object',
  required: ['database', 'storage', 'email'],
  additionalProperties: false,
  properties: {
    database: { enum: ['up', 'down', 'mock', 'local', 'console'] },
    storage: { enum: ['up', 'down', 'mock', 'local', 'console'] },
    email: { enum: ['up', 'down', 'mock', 'local', 'console'] },
  },
} as const;

export const readyResponseSchema = {
  type: 'object',
  required: ['data', 'meta'],
  additionalProperties: false,
  properties: {
    data: {
      type: 'object',
      required: ['status', 'service', 'timestamp', 'checks'],
      additionalProperties: false,
      properties: {
        status: { const: 'ready' },
        service: { const: 'gradport-api' },
        timestamp: { type: 'string', format: 'date-time' },
        checks: readinessChecksSchema,
      },
    },
    meta: {
      type: 'object',
      required: ['requestId'],
      additionalProperties: false,
      properties: { requestId: { type: 'string' } },
    },
  },
} as const;

export const readinessErrorSchema = {
  type: 'object',
  required: ['error'],
  additionalProperties: false,
  properties: {
    error: {
      type: 'object',
      required: ['code', 'message', 'requestId', 'details'],
      additionalProperties: false,
      properties: {
        code: { const: 'SERVICE_NOT_READY' },
        message: { type: 'string' },
        requestId: { type: 'string' },
        details: readinessChecksSchema,
      },
    },
  },
} as const;
