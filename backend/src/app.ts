import { randomUUID } from 'node:crypto';
import Fastify, { LogController, type FastifyInstance } from 'fastify';
import multipart from '@fastify/multipart';
import { registerErrorHandling } from './common/errors/error-handler.js';
import { createLoggerOptions } from './common/logging/logger-options.js';
import type { AppConfig } from './config/env.types.js';
import { createServices, type AppServices } from './infrastructure/create-services.js';
import { toSafeDatabaseError } from './infrastructure/database/database-error.js';
import { registerAuthRoutes } from './modules/auth/auth.routes.js';
import { registerHealthRoutes } from './modules/health/health.routes.js';
import {
  documentMultipartLimits,
  registerDocumentRoutes,
} from './modules/documents/document.routes.js';
import { registerPortfolioRoutes } from './modules/portfolios/portfolio.routes.js';
import { registerCurrentUserRoutes } from './modules/users/user.routes.js';

export interface BuildAppOptions {
  readonly config: AppConfig;
  readonly services?: AppServices;
  readonly connectDatabase?: boolean;
}

export async function buildApp(options: BuildAppOptions): Promise<FastifyInstance> {
  const configuredTrustProxy = options.config.trustProxy;
  const trustProxy =
    typeof configuredTrustProxy === 'number'
      ? (_address: string, hop: number) => hop < configuredTrustProxy
      : configuredTrustProxy;
  const app = Fastify({
    logger: createLoggerOptions(options.config.logLevel),
    ajv: { customOptions: { removeAdditional: false } },
    genReqId: () => randomUUID(),
    requestIdHeader: false,
    logController: new LogController({ requestIdLogLabel: 'requestId' }),
    trustProxy,
  });
  const services = options.services ?? createServices(options.config, app.log);

  app.addHook('onRequest', (request, reply, done) => {
    void reply.header('x-request-id', request.id);
    done();
  });

  registerErrorHandling(app);
  await app.register(multipart, { limits: documentMultipartLimits });
  registerHealthRoutes(app, {
    services,
    timeoutMs: options.config.readyCheckTimeoutMs,
  });
  await registerAuthRoutes(app, { config: options.config, services });
  await registerCurrentUserRoutes(app, services);
  await registerPortfolioRoutes(app, services);
  await registerDocumentRoutes(app, { config: options.config, services });

  if (options.connectDatabase !== false) {
    try {
      await services.database.connect();
    } catch (error) {
      const safeError = toSafeDatabaseError(error);
      app.log.error(
        { code: safeError.code },
        'Database connection failed; readiness will remain unavailable',
      );
    }
  }

  app.addHook('onClose', async () => {
    await services.database.disconnect();
  });

  return app;
}
