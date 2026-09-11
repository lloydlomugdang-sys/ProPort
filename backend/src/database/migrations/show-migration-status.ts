import { executeDatabaseCommand } from '../cli/database-command.js';
import { getMigrationStatus } from './migration-runner.js';

void executeDatabaseCommand(
  { allowedAccessModes: ['maintenance'], requireConfirmation: false },
  async ({ db, config }) => {
    const status = await getMigrationStatus(db);
    process.stdout.write(
      `${JSON.stringify({
        database: config.mongodbDbName,
        applied: status.applied.map(({ _id, name, appliedAt }) => ({
          version: _id,
          name,
          appliedAt,
        })),
        pending: status.pending.map(({ version, name }) => ({ version, name })),
      })}\n`,
    );
  },
);
