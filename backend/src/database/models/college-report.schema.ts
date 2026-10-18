import { Schema, type Types } from 'mongoose';

export const COLLEGE_REPORT_STATUSES = ['draft', 'submitted'] as const;
export type CollegeReportStatus = (typeof COLLEGE_REPORT_STATUSES)[number];

export interface CollegeReportAnswer {
  questionKey: string;
  value: string | number | null;
}

export interface CollegeReport {
  ownerId: Types.ObjectId;
  templateId?: Types.ObjectId;
  academicYear: string;
  questionnaireVersion?: number;
  essay?: string;
  answers: CollegeReportAnswer[];
  status: CollegeReportStatus;
  submittedAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

const collegeReportAnswerSchema = new Schema<CollegeReportAnswer>(
  {
    questionKey: { type: String, required: true, trim: true, maxlength: 100 },
    value: {
      type: Schema.Types.Mixed, default: null,
      validate: {
        validator: (value: unknown) => value === null ||
          (typeof value === 'string' && value.length <= 5000) ||
          (typeof value === 'number' && Number.isInteger(value) && value >= 1 && value <= 7),
        message: 'Unsupported answer representation.',
      },
    },
  },
  { _id: false, strict: 'throw' },
);

export const collegeReportSchema = new Schema<CollegeReport>(
  {
    ownerId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    // Bundled, versioned questionnaires need no seeded template ID. Legacy
    // reports retain their references and the existing owner/template/year index.
    templateId: { type: Schema.Types.ObjectId, ref: 'ReportTemplate' },
    academicYear: {
      type: String,
      required: true,
      trim: true,
      match: /^(?:\d{4}-\d{4}|current)$/,
      maxlength: 9,
    },
    answers: { type: [collegeReportAnswerSchema], required: true, default: [] },
    questionnaireVersion: { type: Number, min: 1 },
    essay: { type: String, maxlength: 10000 },
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
