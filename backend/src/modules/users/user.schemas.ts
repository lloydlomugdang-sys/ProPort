import { userResponseSchema } from '../auth/auth.schemas.js';
import { profileOptionsSchema } from './profile-options.js';

export const currentUserPatchBodySchema = {
  type: 'object',
  minProperties: 1,
  additionalProperties: false,
  properties: {
    firstName: { type: 'string', minLength: 2, maxLength: 100 },
    lastName: { type: 'string', minLength: 2, maxLength: 100 },
    program: { type: 'string', maxLength: 200 },
    yearLevel: { type: 'string', maxLength: 50 },
    school: { type: 'string', maxLength: 200 },
  },
} as const;

export const currentUserQuerySchema = {
  type: 'object',
  maxProperties: 0,
  additionalProperties: false,
} as const;

export const currentUserResponseSchema = {
  ...userResponseSchema,
  properties: {
    ...userResponseSchema.properties,
    data: {
      ...userResponseSchema.properties.data,
      required: ['user', 'profileOptions'],
      properties: { ...userResponseSchema.properties.data.properties, profileOptions: profileOptionsSchema },
    },
  },
} as const;
