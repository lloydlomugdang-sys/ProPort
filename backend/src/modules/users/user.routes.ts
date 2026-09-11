import type { FastifyInstance, FastifyRequest } from 'fastify';
import { Types } from 'mongoose';
import { AppError } from '../../common/errors/app-error.js';
import { successResponse } from '../../common/http/api-response.js';
import type { AppServices } from '../../infrastructure/create-services.js';
import {
  currentUserPatchBodySchema,
  currentUserQuerySchema,
  currentUserResponseSchema,
} from './user.schemas.js';
import {
  CurrentUserService,
  type CurrentUserIdentity,
  type UpdateCurrentUserProfileInput,
} from './user.service.js';

interface AccessTokenClaims {
  readonly sub: string;
  readonly sid: string;
}

const UNAUTHORIZED = new AppError(
  401,
  'UNAUTHORIZED',
  'Authentication is required to access this resource.',
);

function objectId(value: unknown): Types.ObjectId {
  if (typeof value !== 'string' || !Types.ObjectId.isValid(value)) {
    throw UNAUTHORIZED;
  }
  return new Types.ObjectId(value);
}

export async function registerCurrentUserRoutes(
  app: FastifyInstance,
  services: AppServices,
): Promise<void> {
  const currentUsers = new CurrentUserService(services.database);
  const identities = new WeakMap<FastifyRequest, CurrentUserIdentity>();

  async function requireCurrentUser(request: FastifyRequest): Promise<void> {
    let claims: AccessTokenClaims;
    try {
      claims = await request.jwtVerify<AccessTokenClaims>();
    } catch {
      throw UNAUTHORIZED;
    }

    const identity = await currentUsers.authenticate(objectId(claims.sub), objectId(claims.sid));
    identities.set(request, identity);
  }

  function identityFor(request: FastifyRequest): CurrentUserIdentity {
    const identity = identities.get(request);
    if (identity === undefined) {
      throw UNAUTHORIZED;
    }
    return identity;
  }

  app.get(
    '/api/v1/users/me',
    {
      onRequest: requireCurrentUser,
      schema: {
        querystring: currentUserQuerySchema,
        response: { 200: currentUserResponseSchema },
      },
    },
    async (request) => successResponse({ user: identityFor(request).profile }, request.id),
  );

  app.patch<{ Body: UpdateCurrentUserProfileInput }>(
    '/api/v1/users/me',
    {
      onRequest: requireCurrentUser,
      schema: {
        body: currentUserPatchBodySchema,
        querystring: currentUserQuerySchema,
        response: { 200: currentUserResponseSchema },
      },
    },
    async (request) => {
      const user = await currentUsers.updateProfile(identityFor(request).userId, request.body);
      return successResponse({ user }, request.id);
    },
  );
}
