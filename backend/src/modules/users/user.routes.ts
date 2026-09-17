import type { FastifyInstance, FastifyRequest } from 'fastify';
import { Types } from 'mongoose';
import { AppError } from '../../common/errors/app-error.js';
import { successResponse } from '../../common/http/api-response.js';
import type { AppServices } from '../../infrastructure/create-services.js';
import { PROFILE_OPTIONS } from './profile-options.js';
import {
  currentUserPatchBodySchema,
  currentUserQuerySchema,
  currentUserResponseSchema,
} from './user.schemas.js';
import {
  CurrentUserService,
  MAX_AVATAR_FILE_SIZE_BYTES,
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

function mapAvatarMultipartError(error: unknown): AppError {
  const code =
    typeof error === 'object' && error !== null && 'code' in error
      ? String(error.code)
      : '';
  if (code.includes('FILE_TOO_LARGE')) {
    return new AppError(413, 'FILE_TOO_LARGE', 'The profile image exceeds the 5 MB upload limit.');
  }
  return new AppError(
    400,
    'INVALID_MULTIPART_REQUEST',
    'The upload request is invalid.',
  );
}

async function parseAvatarFile(request: FastifyRequest): Promise<{ contents: Buffer; mimeType: string }> {
  if (!request.isMultipart()) {
    throw new AppError(
      415,
      'UNSUPPORTED_MEDIA_TYPE',
      'Avatar upload must use multipart/form-data.',
    );
  }

  let fileBuffer: Buffer | undefined;
  let fileMimeType: string | undefined;

  try {
    for await (const part of request.parts({ limits: { fileSize: MAX_AVATAR_FILE_SIZE_BYTES } })) {
      if (part.type === 'file') {
        if (fileBuffer !== undefined) {
          part.file.resume();
          throw new AppError(400, 'VALIDATION_ERROR', 'The request is invalid.', {
            avatar: ['only a single image file may be uploaded'],
          });
        }
        fileBuffer = await part.toBuffer();
        fileMimeType = part.mimetype;
      }
    }
  } catch (error) {
    if (error instanceof AppError) throw error;
    throw mapAvatarMultipartError(error);
  }

  if (!fileBuffer || fileBuffer.length === 0) {
    throw new AppError(400, 'VALIDATION_ERROR', 'The request is invalid.', {
      avatar: ['image file is required'],
    });
  }

  return { contents: fileBuffer, mimeType: fileMimeType ?? 'image/jpeg' };
}

export async function registerCurrentUserRoutes(
  app: FastifyInstance,
  services: AppServices,
): Promise<void> {
  const currentUsers = new CurrentUserService(services.database, services.storage, app.log);
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
    async (request) => successResponse({ user: identityFor(request).profile, profileOptions: PROFILE_OPTIONS }, request.id),
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
      return successResponse({ user, profileOptions: PROFILE_OPTIONS }, request.id);
    },
  );

  app.get(
    '/api/v1/users/me/avatar',
    {
      onRequest: requireCurrentUser,
      schema: {
        querystring: currentUserQuerySchema,
      },
    },
    async (request, reply) => {
      const avatar = await currentUsers.getAvatar(identityFor(request).userId);
      return reply
        .type(avatar.mimeType)
        .header('cache-control', 'private, max-age=300')
        .send(avatar.stream);
    },
  );

  app.post(
    '/api/v1/users/me/avatar',
    {
      onRequest: requireCurrentUser,
      schema: {
        querystring: currentUserQuerySchema,
        response: { 200: currentUserResponseSchema },
      },
    },
    async (request) => {
      const file = await parseAvatarFile(request);
      const user = await currentUsers.uploadAvatar(identityFor(request).userId, file);
      return successResponse({ user, profileOptions: PROFILE_OPTIONS }, request.id);
    },
  );

  app.delete(
    '/api/v1/users/me/avatar',
    {
      onRequest: requireCurrentUser,
      schema: {
        querystring: currentUserQuerySchema,
        response: { 200: currentUserResponseSchema },
      },
    },
    async (request) => {
      const user = await currentUsers.deleteAvatar(identityFor(request).userId);
      return successResponse({ user, profileOptions: PROFILE_OPTIONS }, request.id);
    },
  );
}
