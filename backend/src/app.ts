import { randomUUID } from 'node:crypto';
import Fastify, { LogController, type FastifyInstance } from 'fastify';
import { registerErrorHandling } from './common/errors/error-handler.js';
import { createLoggerOptions } from './common/logging/logger-options.js';
import type { AppConfig } from './config/env.types.js';
import { createServices, type AppServices } from './infrastructure/create-services.js';
import { registerHealthRoutes } from './modules/health/health.routes.js';

export interface BuildAppOptions {
  readonly config: AppConfig;
  readonly services?: AppServices;
  readonly connectDatabase?: boolean;
}

export async function buildApp(options: BuildAppOptions): Promise<FastifyInstance> {
  const app = Fastify({
    logger: createLoggerOptions(options.config.logLevel),
    genReqId: () => randomUUID(),
    requestIdHeader: false,
    logController: new LogController({ requestIdLogLabel: 'requestId' }),
  });
  const services = options.services ?? createServices(options.config, app.log);

  app.addHook('onRequest', (request, reply, done) => {
    void reply.header('x-request-id', request.id);
    done();
  });

  registerErrorHandling(app);
  registerHealthRoutes(app, {
    services,
    timeoutMs: options.config.readyCheckTimeoutMs,
  });

  if (options.connectDatabase !== false) {
    try {
      await services.database.connect();
    } catch (error) {
      app.log.error({ err: error }, 'Database connection failed; readiness will remain unavailable');
    }
  }

  app.addHook('onClose', async () => {
    await services.database.disconnect();
  });

  return app;
}
