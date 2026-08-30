import { loadConfig } from '../../config/env.js';
import { MongooseDatabaseConnection } from '../../infrastructure/database/mongoose-database.js';
import { seedDocumentCategories } from './categories.seed.js';
import { seedReportTemplate } from './report-template.seed.js';

async function run(): Promise<void> {
  const config = loadConfig();
  if (config.databaseDriver !== 'mongodb' || config.mongodbUri === undefined) {
    throw new Error('Seed refused: configure DATABASE_DRIVER=mongodb and MONGODB_URI explicitly.');
  }

  const database = new MongooseDatabaseConnection({
    uri: config.mongodbUri,
    databaseName: config.mongodbDbName,
  });

  try {
    await database.connect();
    const connection = database.mongooseConnection;
    if (connection === undefined) {
      throw new Error('MongoDB connection is unavailable.');
    }
    await seedDocumentCategories(connection);
    await seedReportTemplate(connection);
    process.stdout.write('GradPort seed definitions applied successfully.\n');
  } finally {
    await database.disconnect();
  }
}

run().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : 'Unknown seed failure.';
  process.stderr.write(`Seed failed: ${message}\n`);
  process.exitCode = 1;
});
