import { SafeDatabaseError } from '../../infrastructure/database/database-error.js';
import { executeDatabaseCommand } from '../cli/database-command.js';
import { verifyApplicationIndexes } from '../indexes/verify-indexes.js';
import { getMigrationStatus } from '../migrations/migration-runner.js';
import { verifySeedData } from '../seeds/seed-database.js';

void executeDatabaseCommand(
  { allowedAccessModes: ['maintenance'], requireConfirmation: false },
  async ({ db, connection, config }) => {
    await db.admin().ping();
    const migrations = await getMigrationStatus(db);
    const indexes = await verifyApplicationIndexes(db);
    const seeds = await verifySeedData(connection);
    const ok = migrations.pending.length === 0 && indexes.ok && seeds.ok;

    process.stdout.write(
      `${JSON.stringify({
        database: config.mongodbDbName,
        status: ok ? 'verified' : 'invalid',
        migrations: {
          appliedCount: migrations.applied.length,
          pendingCount: migrations.pending.length,
        },
        indexes,
        seeds,
      })}\n`,
    );

    if (!ok) {
      throw new SafeDatabaseError(
        'DATABASE_UNAVAILABLE',
        'MongoDB verification found incomplete persistence state.',
      );
    }
  },
);
