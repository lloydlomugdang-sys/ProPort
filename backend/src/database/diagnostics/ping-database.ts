import { executeDatabaseCommand } from '../cli/database-command.js';

void executeDatabaseCommand(
  {
    allowedAccessModes: ['runtime', 'maintenance'],
    requireConfirmation: false,
  },
  async ({ db, config }) => {
    const startedAt = Date.now();
    await db.admin().ping();
    process.stdout.write(
      `${JSON.stringify({
        database: config.mongodbDbName,
        status: 'up',
        elapsedMs: Date.now() - startedAt,
      })}\n`,
    );
  },
);
