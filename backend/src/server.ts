import { buildApp } from './app.js';
import { ConfigurationError, loadConfig } from './config/env.js';

async function start(): Promise<void> {
  const config = loadConfig();
  const app = await buildApp({ config });

  const shutdown = async (signal: string): Promise<void> => {
    app.log.info({ signal }, 'Graceful shutdown requested');
    await app.close();
    process.exitCode = 0;
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
