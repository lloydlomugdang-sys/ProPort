import { executeDatabaseCommand } from '../cli/database-command.js';
import { seedDatabase } from './seed-database.js';

void executeDatabaseCommand(
  { allowedAccessModes: ['maintenance'] },
  async ({ connection, config }) => {
    const result = await seedDatabase(connection);
    process.stdout.write(
      `${JSON.stringify({
        database: config.mongodbDbName,
        seeds: {
          categoryCount: result.categoryCount,
          reportTemplateCount: result.reportTemplateCount,
          insertedCategories: result.insertedCategories,
          insertedReportTemplates: result.insertedReportTemplates,
        },
      })}\n`,
    );
  },
);
