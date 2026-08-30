import { isDeepStrictEqual } from 'node:util';
import type { Connection } from 'mongoose';
import { registerModels } from '../../infrastructure/database/model-registry.js';
import { getMigrationStatus } from '../migrations/migration-runner.js';
import { CATEGORY_SEEDS, seedDocumentCategories } from './categories.seed.js';
import {
  COLLEGE_ENGAGEMENT_TEMPLATE_V1,
  seedReportTemplate,
} from './report-template.seed.js';

export interface SeedVerificationResult {
  readonly categoryCount: number;
  readonly reportTemplateCount: number;
  readonly issues: readonly string[];
  readonly ok: boolean;
}

export interface SeedRunResult extends SeedVerificationResult {
  readonly insertedCategories: number;
  readonly insertedReportTemplates: number;
}

function comparableCategory(value: Record<string, unknown>): Record<string, unknown> {
  return {
    key: value.key,
    name: value.name,
    sortOrder: value.sortOrder,
    active: value.active,
    folders: value.folders,
  };
}

function comparableTemplate(value: Record<string, unknown>): Record<string, unknown> {
  return {
    key: value.key,
    version: value.version,
    title: value.title,
    prompt: value.prompt,
    questions: value.questions,
    active: value.active,
  };
}

export async function verifySeedData(connection: Connection): Promise<SeedVerificationResult> {
  const { DocumentCategory, ReportTemplate } = registerModels(connection);
  const categoryKeys = CATEGORY_SEEDS.map((category) => category.key);
  const categories = (await DocumentCategory.find({ key: { $in: categoryKeys } })
    .select('-_id key name sortOrder active folders')
    .sort({ sortOrder: 1 })
    .lean()
    .exec()) as unknown as Record<string, unknown>[];
  const templates = (await ReportTemplate.find({
    key: COLLEGE_ENGAGEMENT_TEMPLATE_V1.key,
    version: COLLEGE_ENGAGEMENT_TEMPLATE_V1.version,
  })
    .select('-_id key version title prompt questions active')
    .lean()
    .exec()) as unknown as Record<string, unknown>[];

  const issues: string[] = [];
  for (const expected of CATEGORY_SEEDS) {
    const actual = categories.find((category) => category.key === expected.key);
    if (actual === undefined || !isDeepStrictEqual(comparableCategory(actual), expected)) {
      issues.push(`Category seed ${expected.key} is missing or differs.`);
    }
  }

  const actualTemplate = templates[0];
  if (
    actualTemplate === undefined ||
    !isDeepStrictEqual(comparableTemplate(actualTemplate), COLLEGE_ENGAGEMENT_TEMPLATE_V1)
  ) {
    issues.push('Report template seed college-engagement-v1 is missing or differs.');
  }

  return {
    categoryCount: categories.length,
    reportTemplateCount: templates.length,
    issues,
    ok: issues.length === 0,
  };
}

export async function seedDatabase(connection: Connection): Promise<SeedRunResult> {
  const db = connection.db;
  if (db === undefined) {
    throw new Error('MongoDB connection is unavailable.');
  }
  const migrationStatus = await getMigrationStatus(db);
  if (migrationStatus.pending.length > 0) {
    throw new Error('Seeds refused: database migrations are pending.');
  }

  const { DocumentCategory, ReportTemplate } = registerModels(connection);
  const categoryFilter = { key: { $in: CATEGORY_SEEDS.map((category) => category.key) } };
  const templateFilter = {
    key: COLLEGE_ENGAGEMENT_TEMPLATE_V1.key,
    version: COLLEGE_ENGAGEMENT_TEMPLATE_V1.version,
  };
  const beforeCategories = await DocumentCategory.countDocuments(categoryFilter);
  const beforeTemplates = await ReportTemplate.countDocuments(templateFilter);

  await seedDocumentCategories(connection);
  await seedReportTemplate(connection);

  const verification = await verifySeedData(connection);
  if (!verification.ok) {
    throw new Error(`Seed verification failed: ${verification.issues.join(' ')}`);
  }

  return {
    ...verification,
    insertedCategories: verification.categoryCount - beforeCategories,
    insertedReportTemplates: verification.reportTemplateCount - beforeTemplates,
  };
}
