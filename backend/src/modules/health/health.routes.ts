import type { FastifyInstance } from 'fastify';
import type { ServiceHealth } from '../../common/types/service-health.js';
import { errorResponse, successResponse } from '../../common/http/api-response.js';
import type { AppServices } from '../../infrastructure/create-services.js';
import {
  healthResponseSchema,
  readinessErrorSchema,
  readyResponseSchema,
} from './health.schemas.js';

export interface HealthRoutesOptions {
  readonly services: AppServices;
  readonly timeoutMs: number;
}

function withTimeout(check: Promise<ServiceHealth>, timeoutMs: number): Promise<ServiceHealth> {
  let timeout: NodeJS.Timeout | undefined;
  const timeoutResult = new Promise<ServiceHealth>((resolve) => {
    timeout = setTimeout(
      () => resolve({ status: 'down', detail: 'Health check timed out.' }),
      timeoutMs,
    );
  });

  return Promise.race([check, timeoutResult]).finally(() => {
    if (timeout !== undefined) {
      clearTimeout(timeout);
    }
  });
}

async function safeCheck(check: () => Promise<ServiceHealth>, timeoutMs: number): Promise<ServiceHealth> {
  try {
    return await withTimeout(check(), timeoutMs);
  } catch {
    return { status: 'down', detail: 'Health check failed.' };
  }
}

export function registerHealthRoutes(app: FastifyInstance, options: HealthRoutesOptions): void {
  app.get(
    '/health',
    {
      schema: {
        response: { 200: healthResponseSchema },
      },
    },
    async (request) =>
      successResponse(
        { status: 'ok' as const, service: 'gradport-api' as const, timestamp: new Date().toISOString() },
        request.id,
      ),
  );

  app.get(
    '/ready',
    {
      schema: {
        response: { 200: readyResponseSchema, 503: readinessErrorSchema },
      },
    },
    async (request, reply) => {
      const [database, storage, email] = await Promise.all([
        safeCheck(() => options.services.database.ping(), options.timeoutMs),
        safeCheck(() => options.services.storage.healthCheck(), options.timeoutMs),
        safeCheck(() => options.services.email.healthCheck(), options.timeoutMs),
      ]);
      const checks = {
        database: database.status,
        storage: storage.status,
        email: email.status,
      };
      const isReady = Object.values(checks).every((status) => status !== 'down');

      if (!isReady) {
        return reply.status(503).send(
          errorResponse(
            'SERVICE_NOT_READY',
            'One or more required services are unavailable.',
            request.id,
            { details: checks },
          ),
        );
      }

      return reply.send(
        successResponse(
          {
            status: 'ready' as const,
            service: 'gradport-api' as const,
            timestamp: new Date().toISOString(),
            checks,
          },
          request.id,
        ),
      );
    },
  );
}
