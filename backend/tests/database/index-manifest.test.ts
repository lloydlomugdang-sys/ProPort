import mongoose from 'mongoose';
import { describe, expect, it } from 'vitest';
import { APPLICATION_INDEXES } from '../../src/database/indexes/index-definitions.js';
import { COLLECTION_NAMES } from '../../src/database/collection-names.js';
import { registerModels } from '../../src/infrastructure/database/model-registry.js';

describe('application index manifest', () => {
  it('matches every index declared by the eight Mongoose schemas', async () => {
    const connection = mongoose.createConnection();
    const models = registerModels(connection);
    const modelList = [
      models.User,
      models.Session,
      models.OneTimeCode,
      models.Portfolio,
      models.DocumentCategory,
      models.Document,
      models.ReportTemplate,
      models.CollegeReport,
    ] as const;
    const actual = modelList.flatMap((model) =>
      model.schema.indexes().map(([key, options]) => ({
        collection: model.collection.collectionName,
        name: options.name,
        key,
        ...(options.unique === true ? { unique: true as const } : {}),
        ...(options.expireAfterSeconds === undefined
          ? {}
          : { expireAfterSeconds: options.expireAfterSeconds }),
      })),
    );

    expect(actual).toEqual(APPLICATION_INDEXES);
    expect(APPLICATION_INDEXES).toHaveLength(18);
    await connection.destroy();
  });

  it('uses explicit application collection names without GridFS collections', () => {
    const names = Object.values(COLLECTION_NAMES);
    expect(names).toContain('documents');
    expect(names).toContain('portfolios');
    expect(names).not.toContain('fs.files');
    expect(names).not.toContain('fs.chunks');
    expect(names.some((name) => name.includes('gridfs'))).toBe(false);
  });
});
