import { createHash } from 'node:crypto';
import type { Db, IndexDescription } from 'mongodb';
import { PORTFOLIO_INDEXES } from '../indexes/index-definitions.js';
import type { DatabaseMigration } from './migration.types.js';

const checksum = createHash('sha256').update(JSON.stringify(PORTFOLIO_INDEXES)).digest('hex');

export const portfolioIndexesMigration: DatabaseMigration = {
  version: 2,
  name: '002_portfolio_indexes',
  description: 'Create the authenticated portfolio owner/list index.',
  checksum,
  async up(db: Db): Promise<void> {
    for (const definition of PORTFOLIO_INDEXES) {
      const options: IndexDescription = {
        key: { ...definition.key },
        name: definition.name,
      };
      await db.collection(definition.collection).createIndexes([options]);
    }
  },
};
