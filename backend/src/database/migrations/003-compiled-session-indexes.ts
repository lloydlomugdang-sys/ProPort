import { createHash } from 'node:crypto';
import { COLLECTION_NAMES } from '../collection-names.js';
import { COMPILED_SESSION_INDEXES } from '../indexes/index-definitions.js';
import type { DatabaseMigration } from './migration.types.js';

export const compiledSessionIndexesMigration: DatabaseMigration = {
  version: 3,
  name: '003_compiled_session_indexes',
  description: 'Register compiled-session indexes; retain expired cleanup records until object deletion.',
  checksum: createHash('sha256').update(JSON.stringify(COMPILED_SESSION_INDEXES) + ':remove-legacy-expiry-ttl').digest('hex'),
  async up(db) {
    const collection = db.collection(COLLECTION_NAMES.compiledDocumentSessions);
    // Only replace the exact TTL index previously created by this application.
    if (await db.listCollections({ name: collection.collectionName }, { nameOnly: true }).hasNext()) {
      const indexes = await collection.listIndexes().toArray();
      const legacy = indexes.find((index) => index.name === 'expiresAt_1' &&
        index.expireAfterSeconds === 0 && JSON.stringify(index.key) === '{"expiresAt":1}');
      if (legacy) await collection.dropIndex('expiresAt_1');
    }
    for (const index of COMPILED_SESSION_INDEXES) {
      await collection.createIndex({ ...index.key }, { name: index.name, ...(index.unique ? { unique: true } : {}) });
    }
  },
};
