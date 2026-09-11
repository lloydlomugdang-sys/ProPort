import { initialIndexesMigration } from './001-initial-indexes.js';
import { portfolioIndexesMigration } from './002-portfolio-indexes.js';
import type { DatabaseMigration } from './migration.types.js';

export const DATABASE_MIGRATIONS: readonly DatabaseMigration[] = [
  initialIndexesMigration,
  portfolioIndexesMigration,
] as const;
