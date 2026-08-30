import type { Connection, Model, Schema } from 'mongoose';
import { COLLECTION_NAMES } from '../../database/collection-names.js';
import {
  collegeReportSchema,
  documentCategorySchema,
  documentSchema,
  oneTimeCodeSchema,
  reportTemplateSchema,
  sessionSchema,
  userSchema,
  type CollegeReport,
  type Document,
  type DocumentCategory,
  type OneTimeCode,
  type ReportTemplate,
  type Session,
  type User,
} from '../../database/models/index.js';

export interface GradPortModels {
  readonly User: Model<User>;
  readonly Session: Model<Session>;
  readonly OneTimeCode: Model<OneTimeCode>;
  readonly DocumentCategory: Model<DocumentCategory>;
  readonly Document: Model<Document>;
  readonly ReportTemplate: Model<ReportTemplate>;
  readonly CollegeReport: Model<CollegeReport>;
}

function modelFor<T>(
  connection: Connection,
  name: string,
  schema: Schema<T>,
  collectionName: string,
): Model<T> {
  const registered = connection.models[name] as Model<T> | undefined;
  return registered ?? connection.model<T>(name, schema, collectionName);
}

export function registerModels(connection: Connection): GradPortModels {
  return {
    User: modelFor(connection, 'User', userSchema, COLLECTION_NAMES.users),
    Session: modelFor(connection, 'Session', sessionSchema, COLLECTION_NAMES.sessions),
    OneTimeCode: modelFor(
      connection,
      'OneTimeCode',
      oneTimeCodeSchema,
      COLLECTION_NAMES.oneTimeCodes,
    ),
    DocumentCategory: modelFor(
      connection,
      'DocumentCategory',
      documentCategorySchema,
      COLLECTION_NAMES.documentCategories,
    ),
    Document: modelFor(connection, 'Document', documentSchema, COLLECTION_NAMES.documents),
    ReportTemplate: modelFor(
      connection,
      'ReportTemplate',
      reportTemplateSchema,
      COLLECTION_NAMES.reportTemplates,
    ),
    CollegeReport: modelFor(
      connection,
      'CollegeReport',
      collegeReportSchema,
      COLLECTION_NAMES.collegeReports,
    ),
  };
}
