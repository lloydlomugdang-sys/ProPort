import { Schema, type Types } from 'mongoose';
import { REPORT_ANSWER_OPTIONS, type ReportAnswerOption } from './report-template.schema.js';

export const COLLEGE_REPORT_STATUSES = ['draft', 'submitted'] as const;
export type CollegeReportStatus = (typeof COLLEGE_REPORT_STATUSES)[number];

export interface CollegeReportAnswer {
  questionKey: string;
  value: ReportAnswerOption;
}

export interface CollegeReport {
  ownerId: Types.ObjectId;
  templateId: Types.ObjectId;
  academicYear: string;
  answers: CollegeReportAnswer[];
  status: CollegeReportStatus;
  submittedAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

const collegeReportAnswerSchema = new Schema<CollegeReportAnswer>(
  {
    questionKey: { type: String, required: true, trim: true, maxlength: 100 },
    value: { type: String, enum: REPORT_ANSWER_OPTIONS, required: true },
  },
  { _id: false, strict: 'throw' },
);

export const collegeReportSchema = new Schema<CollegeReport>(
  {
    ownerId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    templateId: { type: Schema.Types.ObjectId, ref: 'ReportTemplate', required: true },
    academicYear: {
      type: String,
      required: true,
      trim: true,
      match: /^\d{4}-\d{4}$/,
      maxlength: 9,
    },
    answers: { type: [collegeReportAnswerSchema], required: true, default: [] },
    status: { type: String, enum: COLLEGE_REPORT_STATUSES, required: true, default: 'draft' },
    submittedAt: { type: Date },
  },
  { strict: 'throw', timestamps: true, versionKey: false },
);

collegeReportSchema.index(
  { ownerId: 1, templateId: 1, academicYear: 1 },
  { unique: true, name: 'uniq_college_reports_owner_template_year' },
);
collegeReportSchema.index(
  { ownerId: 1, createdAt: -1 },
  { name: 'idx_college_reports_owner_created' },
);
