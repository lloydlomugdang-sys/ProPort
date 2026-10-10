import type { Types } from 'mongoose';
import { AppError } from '../../common/errors/app-error.js';
import { createRepositories } from '../../database/repositories/index.js';
import type { DatabaseConnection } from '../../infrastructure/database/database-connection.js';
import { OFFICIAL_COLLEGE_REPORT, OFFICIAL_QUESTIONS, type OfficialAnswerValue } from './college-report.template.js';

export interface OfficialAnswer { readonly questionKey: string; readonly value: OfficialAnswerValue }
export interface SaveCollegeReport {
  readonly questionnaireVersion: number;
  readonly answers: readonly OfficialAnswer[];
  readonly essay?: string;
}
export interface OfficialReportView {
  readonly questionnaireVersion: number;
  readonly answers: readonly OfficialAnswer[];
  readonly essay: string;
  readonly updatedAt: string;
}

const unavailable = () => new AppError(503, 'COLLEGE_REPORT_UNAVAILABLE', 'College Report is temporarily unavailable. Please retry.');
const invalid = () => new AppError(400, 'VALIDATION_ERROR', 'College Report responses do not match the official questionnaire.');

export function validateOfficialAnswers(input: SaveCollegeReport): OfficialAnswer[] {
  if (input.questionnaireVersion !== OFFICIAL_COLLEGE_REPORT.version) throw invalid();
  if (input.essay !== undefined && (typeof input.essay !== 'string' || input.essay.length > 10000)) throw invalid();
  if (!Array.isArray(input.answers) || input.answers.length > OFFICIAL_QUESTIONS.length) throw invalid();
  const seen = new Set<string>();
  return input.answers.map((answer) => {
    const question = OFFICIAL_QUESTIONS.find((question) => question.key === answer.questionKey);
    if (!question || seen.has(answer.questionKey)) throw invalid();
    seen.add(answer.questionKey);
    const value = answer.value;
    if (value === null) return { questionKey: question.key, value: null };
    if (question.section.responseType === 'text') {
      if (typeof value !== 'string' || value.length > 5000) throw invalid();
      return { questionKey: question.key, value: value.trim() ? value : null };
    }
    if (!question.section.options.some((option) => option.value === value)) throw invalid();
    return { questionKey: question.key, value };
  });
}

export class CollegeReportService {
  constructor(private readonly database: DatabaseConnection) {}

  private repositories() {
    const connection = this.database.mongooseConnection;
    if (this.database.status !== 'connected' || !connection) throw unavailable();
    return createRepositories(connection);
  }

  async current(ownerId: Types.ObjectId): Promise<{ report: OfficialReportView | null; hasLegacyReport: boolean; templateReady: boolean }> {
    try {
      const repositories = this.repositories();
      const template = await repositories.reportTemplates.findByKeyVersion(OFFICIAL_COLLEGE_REPORT.key, OFFICIAL_COLLEGE_REPORT.version);
      const record = template ? await repositories.collegeReports.findCurrentForOwner(ownerId, template._id) : null;
      const hasLegacyReport = await repositories.collegeReports.hasLegacyForOwner(ownerId, template?._id);
      if (!record) return { report: null, hasLegacyReport, templateReady: template !== null };
      const validated = validateOfficialAnswers({ questionnaireVersion: record.questionnaireVersion ?? -1, answers: record.answers, essay: record.essay ?? '' });
      const byKey = new Map(validated.map((answer) => [answer.questionKey, answer.value]));
      return { hasLegacyReport, templateReady: true, report: {
        questionnaireVersion: OFFICIAL_COLLEGE_REPORT.version,
        answers: OFFICIAL_QUESTIONS.map((question) => ({ questionKey: question.key, value: byKey.get(question.key) ?? null })),
        essay: record.essay ?? '', updatedAt: record.updatedAt.toISOString(),
      } };
    } catch {
      // Never propagate Mongoose/provider errors containing personal answer values.
      throw unavailable();
    }
  }

  async save(ownerId: Types.ObjectId, input: SaveCollegeReport, merge = false): Promise<OfficialReportView> {
    const validated = validateOfficialAnswers(input);
    try {
      const repositories = this.repositories();
      const template = await repositories.reportTemplates.findByKeyVersion(OFFICIAL_COLLEGE_REPORT.key, OFFICIAL_COLLEGE_REPORT.version);
      if (!template) throw new AppError(503, 'COLLEGE_REPORT_UNAVAILABLE', 'The official questionnaire has not been initialized. Please contact support.');
      const previous = merge ? (await this.current(ownerId)).report : null;
      const answers = new Map(previous?.answers.map((answer) => [answer.questionKey, answer.value]) ?? []);
      for (const answer of validated) answers.set(answer.questionKey, answer.value);
      const normalized = OFFICIAL_QUESTIONS.map((q) => ({ questionKey: q.key, value: answers.get(q.key) ?? null }));
      const essay = input.essay ?? previous?.essay ?? '';
      const saved = await repositories.collegeReports.saveCurrentForOwner(ownerId, template._id, {
        questionnaireVersion: OFFICIAL_COLLEGE_REPORT.version, answers: normalized, essay,
      });
      return { questionnaireVersion: OFFICIAL_COLLEGE_REPORT.version, answers: normalized, essay, updatedAt: saved.updatedAt.toISOString() };
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw unavailable();
    }
  }
}
