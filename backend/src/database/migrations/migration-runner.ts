import { randomUUID } from 'node:crypto';
import type { Collection, Db } from 'mongodb';
import { COLLECTION_NAMES } from '../collection-names.js';
import { DATABASE_MIGRATIONS } from './migration-registry.js';
import type { AppliedMigrationRecord, DatabaseMigration } from './migration.types.js';

interface MigrationLock {
  readonly _id: 'database-migrations';
  readonly ownerId: string;
  readonly expiresAt: Date;
}

export class MigrationError extends Error {
  override readonly name = 'MigrationError';
}

export interface MigrationStatus {
  readonly applied: readonly AppliedMigrationRecord[];
  readonly pending: readonly Pick<DatabaseMigration, 'version' | 'name' | 'checksum'>[];
}

export interface MigrationRunResult {
  readonly appliedVersions: readonly number[];
  readonly pendingCount: number;
}

function isDuplicateKey(error: unknown): boolean {
  return typeof error === 'object' && error !== null && 'code' in error && error.code === 11000;
}

function validateAppliedMigrations(applied: readonly AppliedMigrationRecord[]): void {
  for (const record of applied) {
    const migration = DATABASE_MIGRATIONS.find((candidate) => candidate.version === record._id);
    if (migration === undefined) {
      throw new MigrationError(`Unknown applied migration version ${record._id}.`);
    }
    if (migration.name !== record.name || migration.checksum !== record.checksum) {
      throw new MigrationError(`Applied migration ${record._id} has changed.`);
    }
  }

  const appliedVersions = applied.map((record) => record._id);
  const expectedPrefix = DATABASE_MIGRATIONS.slice(0, applied.length).map(
    (migration) => migration.version,
  );
  if (JSON.stringify(appliedVersions) !== JSON.stringify(expectedPrefix)) {
    throw new MigrationError('Applied migration history is out of order.');
  }
}

function migrationCollection(db: Db): Collection<AppliedMigrationRecord> {
  return db.collection<AppliedMigrationRecord>(COLLECTION_NAMES.migrations);
}

async function readAppliedMigrations(db: Db): Promise<AppliedMigrationRecord[]> {
  return migrationCollection(db).find().sort({ _id: 1 }).toArray();
}

async function acquireLock(db: Db, ownerId: string): Promise<void> {
  const locks = db.collection<MigrationLock>(COLLECTION_NAMES.migrationLock);
  const now = new Date();
  try {
    const lock = await locks.findOneAndUpdate(
      {
        _id: 'database-migrations',
        $or: [{ expiresAt: { $lte: now } }, { ownerId }],
      },
      {
        $set: { ownerId, expiresAt: new Date(now.getTime() + 120_000) },
      },
      { upsert: true, returnDocument: 'after' },
    );
    if (lock?.ownerId !== ownerId) {
      throw new MigrationError('Another database migration process holds the lock.');
    }
  } catch (error) {
    if (isDuplicateKey(error)) {
      throw new MigrationError('Another database migration process holds the lock.');
    }
    throw error;
  }
}

async function releaseLock(db: Db, ownerId: string): Promise<void> {
  await db
    .collection<MigrationLock>(COLLECTION_NAMES.migrationLock)
    .deleteOne({ _id: 'database-migrations', ownerId });
}

export async function getMigrationStatus(db: Db): Promise<MigrationStatus> {
  const applied = await readAppliedMigrations(db);
  validateAppliedMigrations(applied);
  const appliedVersions = new Set(applied.map((record) => record._id));
  const pending = DATABASE_MIGRATIONS.filter(
    (migration) => !appliedVersions.has(migration.version),
  ).map(({ version, name, checksum }) => ({ version, name, checksum }));
  return { applied, pending };
}

export async function runMigrations(db: Db): Promise<MigrationRunResult> {
  const initialStatus = await getMigrationStatus(db);
  if (initialStatus.pending.length === 0) {
    return { appliedVersions: [], pendingCount: 0 };
  }

  const ownerId = randomUUID();
  await acquireLock(db, ownerId);
  const appliedVersions: number[] = [];
  try {
    const status = await getMigrationStatus(db);
    for (const pending of status.pending) {
      const migration = DATABASE_MIGRATIONS.find(
        (candidate) => candidate.version === pending.version,
      );
      if (migration === undefined) {
        throw new MigrationError(`Migration ${pending.version} is unavailable.`);
      }
      const startedAt = Date.now();
      await migration.up(db);
      await migrationCollection(db).insertOne({
        _id: migration.version,
        name: migration.name,
        checksum: migration.checksum,
        appliedAt: new Date(),
        executionMs: Date.now() - startedAt,
      });
      appliedVersions.push(migration.version);
    }
  } finally {
    await releaseLock(db, ownerId);
  }

  const finalStatus = await getMigrationStatus(db);
  return { appliedVersions, pendingCount: finalStatus.pending.length };
}
