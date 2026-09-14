import type { FastifyInstance, FastifyRequest } from 'fastify';
import { Types } from 'mongoose';
import { AppError } from '../../common/errors/app-error.js';
import { successResponse } from '../../common/http/api-response.js';
import type { AppConfig } from '../../config/env.types.js';
import type { AppServices } from '../../infrastructure/create-services.js';
import { CurrentUserService, type CurrentUserIdentity } from '../users/user.service.js';
import {
  documentCategoryListResponseSchema,
  documentDeleteResponseSchema,
  documentListResponseSchema,
  documentOcrPatchSchema,
  documentOcrResponseSchema,
  documentPathParamsSchema,
  documentQuerySchema,
  documentResponseSchema,
} from './document.schemas.js';
import {
  DocumentService,
  MAX_DOCUMENT_FILE_SIZE_BYTES,
  type DocumentFileInput,
  type DocumentUploadInput,
} from './document.service.js';

interface AccessTokenClaims {
  readonly sub: string;
  readonly sid: string;
}

interface DocumentParams {
  readonly documentId: string;
}

interface DocumentOcrPatchBody {
  readonly reviewedText: string;
}

const UPLOAD_FIELDS = new Set([
  'categoryKey',
  'folderKey',
  'title',
  'documentDate',
  'description',
  'reflection',
]);

const UNAUTHORIZED = new AppError(
  401,
  'UNAUTHORIZED',
  'Authentication is required to access this resource.',
);

function objectId(value: unknown): Types.ObjectId {
  if (typeof value !== 'string' || !Types.ObjectId.isValid(value)) throw UNAUTHORIZED;
  return new Types.ObjectId(value);
}

function uploadValidation(field: string, message: string): AppError {
  return new AppError(400, 'VALIDATION_ERROR', 'The request is invalid.', {
    [field]: [message],
  });
}

function requiredField(fields: Readonly<Record<string, string>>, name: string): string {
  const value = fields[name];
  if (value === undefined) throw uploadValidation(name, 'is required');
  return value;
}

function mapMultipartError(error: unknown): AppError {
  const code =
    typeof error === 'object' && error !== null && 'code' in error
      ? String(error.code)
      : '';
  if (code.includes('FILE_TOO_LARGE')) {
    return new AppError(413, 'FILE_TOO_LARGE', 'The file exceeds the 15 MB upload limit.');
  }
  if (code.includes('LIMIT')) {
    return uploadValidation('request', 'contains too many multipart fields or files');
  }
  return new AppError(
    400,
    'INVALID_MULTIPART_REQUEST',
    'The upload request is invalid.',
  );
}

async function parseFileParts(request: FastifyRequest, allowedFields: ReadonlySet<string>) {
  if (!request.isMultipart()) {
    throw new AppError(
      415,
      'UNSUPPORTED_MEDIA_TYPE',
      'Document uploads must use multipart/form-data.',
    );
  }

  const fields: Record<string, string> = {};
  let file:
    | {
        readonly filename: string;
        readonly mimetype: string;
        readonly contents: Buffer;
      }
    | undefined;

  try {
    for await (const part of request.parts()) {
      if (part.type === 'file') {
        if (part.fieldname !== 'file') {
          part.file.resume();
          throw uploadValidation(part.fieldname, 'is not supported');
        }
        if (file !== undefined) {
          part.file.resume();
          throw uploadValidation('file', 'must contain exactly one file');
        }
        file = {
          filename: part.filename,
          mimetype: part.mimetype,
          contents: await part.toBuffer(),
        };
        continue;
      }

      if (part.fieldnameTruncated || part.valueTruncated) {
        throw uploadValidation('request', 'contains an overlong multipart field');
      }
      if (!allowedFields.has(part.fieldname)) {
        throw uploadValidation(part.fieldname, 'is not supported');
      }
      if (fields[part.fieldname] !== undefined || typeof part.value !== 'string') {
        throw uploadValidation(part.fieldname, 'must be a single text value');
      }
      fields[part.fieldname] = part.value;
    }
  } catch (error) {
    if (error instanceof AppError) throw error;
    throw mapMultipartError(error);
  }

  if (file === undefined) throw uploadValidation('file', 'is required');
  const input: DocumentFileInput = {
    originalFileName: file.filename,
    mimeType: file.mimetype,
    contents: file.contents,
  };
  return { fields, file: input };
}

async function parseUpload(request: FastifyRequest): Promise<DocumentUploadInput> {
  const { fields, file } = await parseFileParts(request, UPLOAD_FIELDS);
  return {
    categoryKey: requiredField(fields, 'categoryKey'),
    folderKey: requiredField(fields, 'folderKey'),
    title: requiredField(fields, 'title'),
    documentDate: requiredField(fields, 'documentDate'),
    ...(fields.description === undefined ? {} : { description: fields.description }),
    ...(fields.reflection === undefined ? {} : { reflection: fields.reflection }),
    ...file,
  };
}

function contentDisposition(fileName: string): string {
  const fallback = fileName.replace(/[^\x20-\x7e]|["\\]/g, '_');
  return `inline; filename="${fallback}"; filename*=UTF-8''${encodeURIComponent(fileName)}`;
}

export async function registerDocumentRoutes(
  app: FastifyInstance,
  options: { readonly config: AppConfig; readonly services: AppServices },
): Promise<void> {
  const { services } = options;
  const currentUsers = new CurrentUserService(services.database);
  const documents = new DocumentService(services.database, services.storage, services.ocr, services.metadata);
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

  function ownerIdFor(request: FastifyRequest): Types.ObjectId {
    const identity = identities.get(request);
    if (identity === undefined) throw UNAUTHORIZED;
    return identity.userId;
  }

  // Reuse one limiter/store for previews and stored-document extraction so
  // switching endpoints cannot double the existing per-user OCR allowance.
  const limitOcr = app.rateLimit({
    max: options.config.documentOcrRateLimitMax,
    timeWindow: '1 minute',
    keyGenerator: (request) => ownerIdFor(request).toString(),
  });

  app.get(
    '/api/v1/documents/categories',
    {
      onRequest: requireCurrentUser,
      schema: {
        querystring: documentQuerySchema,
        response: { 200: documentCategoryListResponseSchema },
      },
    },
    async (request) =>
      successResponse({ categories: await documents.listCategories() }, request.id),
  );

  app.get(
    '/api/v1/documents',
    {
      onRequest: requireCurrentUser,
      schema: {
        querystring: documentQuerySchema,
        response: { 200: documentListResponseSchema },
      },
    },
    async (request) => successResponse(await documents.list(ownerIdFor(request)), request.id),
  );

  app.post(
    '/api/v1/documents',
    {
      onRequest: requireCurrentUser,
      config: {
        rateLimit: {
          max: options.config.documentUploadRateLimitMax,
          timeWindow: '1 minute',
          groupId: 'documents-upload-user',
          keyGenerator: (request) => ownerIdFor(request).toString(),
        },
      },
      schema: {
        querystring: documentQuerySchema,
        response: { 201: documentResponseSchema },
      },
    },
    async (request, reply) => {
      const document = await documents.upload(ownerIdFor(request), await parseUpload(request));
      return reply.status(201).send(successResponse({ document }, request.id));
    },
  );

  app.post(
    '/api/v1/documents/ocr-preview',
    {
      onRequest: [requireCurrentUser, limitOcr],
      config: { rateLimit: false },
      schema: {
        querystring: documentQuerySchema,
        response: { 200: documentOcrResponseSchema },
      },
    },
    async (request) => {
      const { file } = await parseFileParts(request, new Set());
      return successResponse({ ocr: await documents.previewOcr(file, request.id) }, request.id);
    },
  );

  app.get<{ Params: DocumentParams }>(
    '/api/v1/documents/:documentId',
    {
      onRequest: requireCurrentUser,
      schema: {
        params: documentPathParamsSchema,
        querystring: documentQuerySchema,
        response: { 200: documentResponseSchema },
      },
    },
    async (request) =>
      successResponse(
        { document: await documents.get(ownerIdFor(request), request.params.documentId) },
        request.id,
      ),
  );

  app.get<{ Params: DocumentParams }>(
    '/api/v1/documents/:documentId/content',
    {
      onRequest: requireCurrentUser,
      schema: {
        params: documentPathParamsSchema,
        querystring: documentQuerySchema,
      },
    },
    async (request, reply) => {
      const content = await documents.openContent(
        ownerIdFor(request),
        request.params.documentId,
      );
      return reply
        .type(content.document.mimeType)
        .header('content-length', content.document.sizeBytes)
        .header('content-disposition', contentDisposition(content.document.originalFileName))
        .send(content.contents);
    },
  );

  app.get<{ Params: DocumentParams }>(
    '/api/v1/documents/:documentId/ocr',
    {
      onRequest: requireCurrentUser,
      schema: {
        params: documentPathParamsSchema,
        querystring: documentQuerySchema,
        response: { 200: documentOcrResponseSchema },
      },
    },
    async (request) =>
      successResponse(
        { ocr: await documents.getOcr(ownerIdFor(request), request.params.documentId) },
        request.id,
      ),
  );

  app.post<{ Params: DocumentParams }>(
    '/api/v1/documents/:documentId/ocr',
    {
      onRequest: [requireCurrentUser, limitOcr],
      config: { rateLimit: false },
      schema: {
        params: documentPathParamsSchema,
        querystring: documentQuerySchema,
        body: {
          type: 'object',
          additionalProperties: false,
          maxProperties: 0,
        },
        response: { 200: documentOcrResponseSchema },
      },
    },
    async (request) =>
      successResponse(
        { ocr: await documents.extractOcr(ownerIdFor(request), request.params.documentId) },
        request.id,
      ),
  );

  app.patch<{ Params: DocumentParams; Body: DocumentOcrPatchBody }>(
    '/api/v1/documents/:documentId/ocr',
    {
      onRequest: requireCurrentUser,
      schema: {
        params: documentPathParamsSchema,
        querystring: documentQuerySchema,
        body: documentOcrPatchSchema,
        response: { 200: documentOcrResponseSchema },
      },
    },
    async (request) =>
      successResponse(
        {
          ocr: await documents.updateOcr(
            ownerIdFor(request),
            request.params.documentId,
            request.body.reviewedText,
          ),
        },
        request.id,
      ),
  );

  app.delete<{ Params: DocumentParams }>(
    '/api/v1/documents/:documentId',
    {
      onRequest: requireCurrentUser,
      schema: {
        params: documentPathParamsSchema,
        querystring: documentQuerySchema,
        response: { 200: documentDeleteResponseSchema },
      },
    },
    async (request) => {
      await documents.delete(ownerIdFor(request), request.params.documentId);
      return successResponse(
        { status: 'deleted' as const, documentId: request.params.documentId },
        request.id,
      );
    },
  );
}

export const documentMultipartLimits = {
  fileSize: MAX_DOCUMENT_FILE_SIZE_BYTES,
  files: 1,
  fields: 6,
  parts: 7,
  fieldSize: 5_000,
} as const;
