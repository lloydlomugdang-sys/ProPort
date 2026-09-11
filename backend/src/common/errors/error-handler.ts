import type { FastifyError, FastifyInstance } from 'fastify';
import { AppError } from './app-error.js';
import { errorResponse } from '../http/api-response.js';

interface ValidationIssue {
  readonly instancePath?: string;
  readonly params?: {
    readonly missingProperty?: string;
    readonly additionalProperty?: string;
  };
  readonly message?: string;
}

function validationFields(error: FastifyError): Readonly<Record<string, readonly string[]>> {
  const fields: Record<string, string[]> = {};
  const issues = (error.validation ?? []) as readonly ValidationIssue[];

  for (const issue of issues) {
    const field =
      issue.params?.missingProperty ??
      issue.params?.additionalProperty ??
      issue.instancePath?.replace(/^\//, '') ??
      'request';
    const message = issue.message ?? 'is invalid';
    (fields[field] ??= []).push(message);
  }

  return fields;
}

export function registerErrorHandling(app: FastifyInstance): void {
  app.setNotFoundHandler((request, reply) => {
    void reply.status(404).send(
      errorResponse('ROUTE_NOT_FOUND', 'The requested route was not found.', request.id),
    );
  });

  app.setErrorHandler((error: FastifyError, request, reply) => {
    if (error.validation !== undefined) {
      void reply.status(400).send(
        errorResponse('VALIDATION_ERROR', 'The request is invalid.', request.id, {
          fields: validationFields(error),
        }),
      );
      return;
    }

    if (error instanceof AppError) {
      if (error.statusCode >= 500) {
        request.log.error({ err: error }, 'Request failed');
      }
      if (error.headers !== undefined) {
        void reply.headers(error.headers);
      }
      void reply.status(error.statusCode).send(
        errorResponse(error.code, error.message, request.id, {
          ...(error.fields === undefined ? {} : { fields: error.fields }),
        }),
      );
      return;
    }

    request.log.error({ err: error }, 'Unhandled request error');
    void reply.status(500).send(
      errorResponse('INTERNAL_ERROR', 'An unexpected error occurred.', request.id),
    );
  });
}
