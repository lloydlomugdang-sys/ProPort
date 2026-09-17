const emailSchema = {
  type: 'string',
  minLength: 3,
  maxLength: 320,
  pattern: '^\\s*[^\\s@]+@[^\\s@]+\\.[^\\s@]+\\s*$',
} as const;

const strongPasswordSchema = {
  type: 'string',
  minLength: 8,
  maxLength: 128,
} as const;

const opaqueTokenSchema = {
  type: 'string',
  minLength: 43,
  maxLength: 128,
  pattern: '^[A-Za-z0-9_-]+$',
} as const;

const codeSchema = {
  type: 'string',
  pattern: '^[0-9]{6}$',
} as const;

const metadataSchema = {
  type: 'object',
  required: ['requestId'],
  additionalProperties: false,
  properties: { requestId: { type: 'string' } },
} as const;

const authUserSchema = {
  type: 'object',
  required: [
    'id',
    'email',
    'firstName',
    'lastName',
    'program',
    'yearLevel',
    'school',
    'status',
    'emailVerifiedAt',
    'hasAvatar',
  ],
  additionalProperties: false,
  properties: {
    id: { type: 'string' },
    email: emailSchema,
    firstName: { type: 'string' },
    lastName: { type: 'string' },
    program: { type: 'string' },
    yearLevel: { type: 'string' },
    school: { type: 'string' },
    status: { enum: ['pendingVerification', 'active', 'disabled'] },
    emailVerifiedAt: {
      anyOf: [{ type: 'string', format: 'date-time' }, { type: 'null' }],
    },
    hasAvatar: { type: 'boolean' },
  },
} as const;

const tokenBundleSchema = {
  type: 'object',
  required: [
    'tokenType',
    'accessToken',
    'accessTokenExpiresAt',
    'refreshToken',
    'refreshTokenExpiresAt',
  ],
  additionalProperties: false,
  properties: {
    tokenType: { const: 'Bearer' },
    accessToken: { type: 'string', minLength: 1 },
    accessTokenExpiresAt: { type: 'string', format: 'date-time' },
    refreshToken: opaqueTokenSchema,
    refreshTokenExpiresAt: { type: 'string', format: 'date-time' },
  },
} as const;

export const registerBodySchema = {
  type: 'object',
  required: ['firstName', 'lastName', 'email', 'password'],
  additionalProperties: false,
  properties: {
    firstName: { type: 'string', minLength: 2, maxLength: 100 },
    lastName: { type: 'string', minLength: 2, maxLength: 100 },
    email: emailSchema,
    password: strongPasswordSchema,
  },
} as const;

export const emailCodeBodySchema = {
  type: 'object',
  required: ['email', 'code'],
  additionalProperties: false,
  properties: { email: emailSchema, code: codeSchema },
} as const;

export const emailOnlyBodySchema = {
  type: 'object',
  required: ['email'],
  additionalProperties: false,
  properties: { email: emailSchema },
} as const;

export const loginBodySchema = {
  type: 'object',
  required: ['email', 'password'],
  additionalProperties: false,
  properties: {
    email: emailSchema,
    password: { type: 'string', minLength: 1, maxLength: 128 },
  },
} as const;

export const resetPasswordBodySchema = {
  type: 'object',
  required: ['resetToken', 'newPassword'],
  additionalProperties: false,
  properties: { resetToken: opaqueTokenSchema, newPassword: strongPasswordSchema },
} as const;

export const refreshTokenBodySchema = {
  type: 'object',
  required: ['refreshToken'],
  additionalProperties: false,
  properties: { refreshToken: opaqueTokenSchema },
} as const;

export const changePasswordBodySchema = {
  type: 'object', required: ['currentPassword', 'newPassword'], additionalProperties: false,
  properties: {
    currentPassword: { type: 'string', minLength: 1, maxLength: 128 },
    newPassword: strongPasswordSchema,
  },
} as const;

export const registerResponseSchema = {
  type: 'object',
  required: ['data', 'meta'],
  additionalProperties: false,
  properties: {
    data: {
      type: 'object',
      required: ['user', 'verification'],
      additionalProperties: false,
      properties: {
        user: authUserSchema,
        verification: {
          type: 'object',
          required: ['required', 'codeExpiresAt', 'resendAvailableAt'],
          additionalProperties: false,
          properties: {
            required: { const: true },
            codeExpiresAt: { type: 'string', format: 'date-time' },
            resendAvailableAt: { type: 'string', format: 'date-time' },
          },
        },
      },
    },
    meta: metadataSchema,
  },
} as const;

export const userResponseSchema = {
  type: 'object',
  required: ['data', 'meta'],
  additionalProperties: false,
  properties: {
    data: {
      type: 'object',
      required: ['user'],
      additionalProperties: false,
      properties: { user: authUserSchema },
    },
    meta: metadataSchema,
  },
} as const;

export const sessionResponseSchema = {
  type: 'object',
  required: ['data', 'meta'],
  additionalProperties: false,
  properties: {
    data: {
      type: 'object',
      required: ['user', 'tokens'],
      additionalProperties: false,
      properties: { user: authUserSchema, tokens: tokenBundleSchema },
    },
    meta: metadataSchema,
  },
} as const;

export const resetGrantResponseSchema = {
  type: 'object',
  required: ['data', 'meta'],
  additionalProperties: false,
  properties: {
    data: {
      type: 'object',
      required: ['resetToken', 'resetTokenExpiresAt'],
      additionalProperties: false,
      properties: {
        resetToken: opaqueTokenSchema,
        resetTokenExpiresAt: { type: 'string', format: 'date-time' },
      },
    },
    meta: metadataSchema,
  },
} as const;

export function statusResponseSchema(status: string) {
  return {
    type: 'object',
    required: ['data', 'meta'],
    additionalProperties: false,
    properties: {
      data: {
        type: 'object',
        required: ['status'],
        additionalProperties: false,
        properties: { status: { const: status } },
      },
      meta: metadataSchema,
    },
  } as const;
}
