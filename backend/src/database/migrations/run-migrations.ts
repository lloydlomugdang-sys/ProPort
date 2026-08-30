import { executeDatabaseCommand } from '../cli/database-command.js';
import { runMigrations } from './migration-runner.js';

void executeDatabaseCommand({ requiredAccessMode: 'maintenance' }, async ({ db, config }) => {
  const result = await runMigrations(db);
  process.stdout.write(
    `${JSON.stringify({ database: config.mongodbDbName, migration: result })}\n`,
  );
});
