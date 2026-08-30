import type { Connection, Model, Schema } from 'mongoose';
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

function modelFor<T>(connection: Connection, name: string, schema: Schema<T>): Model<T> {
  const registered = connection.models[name] as Model<T> | undefined;
  return registered ?? connection.model<T>(name, schema);
}

export function registerModels(connection: Connection): GradPortModels {
  return {
    User: modelFor(connection, 'User', userSchema),
    Session: modelFor(connection, 'Session', sessionSchema),
    OneTimeCode: modelFor(connection, 'OneTimeCode', oneTimeCodeSchema),
    DocumentCategory: modelFor(connection, 'DocumentCategory', documentCategorySchema),
    Document: modelFor(connection, 'Document', documentSchema),
    ReportTemplate: modelFor(connection, 'ReportTemplate', reportTemplateSchema),
    CollegeReport: modelFor(connection, 'CollegeReport', collegeReportSchema),
  };
}
