import { initialIndexesMigration } from './001-initial-indexes.js';
import type { DatabaseMigration } from './migration.types.js';

export const DATABASE_MIGRATIONS: readonly DatabaseMigration[] = [initialIndexesMigration] as const;
