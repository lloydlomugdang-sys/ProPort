import { buildApp } from './app.js';
import { ConfigurationError, loadConfig } from './config/env.js';

async function start(): Promise<void> {
  const config = loadConfig();
  const app = await buildApp({ config });
  let shutdownPromise: Promise<void> | undefined;

  const shutdown = (signal: string): Promise<void> => {
    shutdownPromise ??= (async () => {
      app.log.info({ signal }, 'Graceful shutdown requested');
      const timeout = setTimeout(() => {
        app.log.error('Graceful shutdown timed out');
        process.exitCode = 1;
      }, 10_000);
      timeout.unref();
      try {
        await app.close();
        process.exitCode = 0;
      } finally {
        clearTimeout(timeout);
      }
    })();
    return shutdownPromise;
  };

  process.once('SIGINT', () => void shutdown('SIGINT'));
  process.once('SIGTERM', () => void shutdown('SIGTERM'));

  await app.listen({ host: config.host, port: config.port });
}

start().catch((error: unknown) => {
  if (error instanceof ConfigurationError) {
    process.stderr.write(`${error.message}\n`);
  } else {
    const message = error instanceof Error ? error.message : 'Unknown startup failure.';
    process.stderr.write(`GradPort API failed to start: ${message}\n`);
  }
  process.exitCode = 1;
});
