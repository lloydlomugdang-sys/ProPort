import type { Db, IndexDescription } from 'mongodb';
import {
  APPLICATION_INDEX_CHECKSUM,
  APPLICATION_INDEXES,
} from '../indexes/index-definitions.js';
import type { DatabaseMigration } from './migration.types.js';

export const initialIndexesMigration: DatabaseMigration = {
  version: 1,
  name: '001_initial_indexes',
  description: 'Create the initial GradPort application indexes.',
  checksum: APPLICATION_INDEX_CHECKSUM,
  async up(db: Db): Promise<void> {
    for (const definition of APPLICATION_INDEXES) {
      const options: IndexDescription = {
        key: { ...definition.key },
        name: definition.name,
        ...(definition.unique === undefined ? {} : { unique: definition.unique }),
        ...(definition.expireAfterSeconds === undefined
          ? {}
          : { expireAfterSeconds: definition.expireAfterSeconds }),
      };
      await db.collection(definition.collection).createIndexes([options]);
    }
  },
};
