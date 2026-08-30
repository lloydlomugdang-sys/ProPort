import type { Connection } from 'mongoose';
import { registerModels } from '../../infrastructure/database/model-registry.js';
import { CollegeReportRepository } from './college-report.repository.js';
import { DocumentCategoryRepository } from './document-category.repository.js';
import { DocumentRepository } from './document.repository.js';
import { OneTimeCodeRepository } from './one-time-code.repository.js';
import { ReportTemplateRepository } from './report-template.repository.js';
import { SessionRepository } from './session.repository.js';
import { UserRepository } from './user.repository.js';

export interface GradPortRepositories {
  readonly users: UserRepository;
  readonly sessions: SessionRepository;
  readonly oneTimeCodes: OneTimeCodeRepository;
  readonly documentCategories: DocumentCategoryRepository;
  readonly documents: DocumentRepository;
  readonly reportTemplates: ReportTemplateRepository;
  readonly collegeReports: CollegeReportRepository;
}

export function createRepositories(connection: Connection): GradPortRepositories {
  const models = registerModels(connection);
  return {
    users: new UserRepository(models.User),
    sessions: new SessionRepository(models.Session),
    oneTimeCodes: new OneTimeCodeRepository(models.OneTimeCode),
    documentCategories: new DocumentCategoryRepository(models.DocumentCategory),
    documents: new DocumentRepository(models.Document),
    reportTemplates: new ReportTemplateRepository(models.ReportTemplate),
    collegeReports: new CollegeReportRepository(models.CollegeReport),
  };
}

export { CollegeReportRepository } from './college-report.repository.js';
export { DocumentCategoryRepository } from './document-category.repository.js';
export { DocumentRepository } from './document.repository.js';
export { OneTimeCodeRepository } from './one-time-code.repository.js';
export { ReportTemplateRepository } from './report-template.repository.js';
export { SessionRepository } from './session.repository.js';
export { UserRepository } from './user.repository.js';
export { RepositoryInputError } from './repository.types.js';
