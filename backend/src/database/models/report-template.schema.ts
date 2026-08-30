import { Schema } from 'mongoose';

export const REPORT_ANSWER_OPTIONS = ['very_often', 'often', 'sometimes', 'never'] as const;
export type ReportAnswerOption = (typeof REPORT_ANSWER_OPTIONS)[number];

export interface ReportQuestion {
  key: string;
  text: string;
  sortOrder: number;
  options: ReportAnswerOption[];
}

export interface ReportTemplate {
  key: string;
  version: number;
  title: string;
  prompt: string;
  questions: ReportQuestion[];
  active: boolean;
  createdAt: Date;
  updatedAt: Date;
}

const reportQuestionSchema = new Schema<ReportQuestion>(
  {
    key: { type: String, required: true, trim: true, maxlength: 100 },
    text: { type: String, required: true, trim: true, maxlength: 1_000 },
    sortOrder: { type: Number, required: true, min: 0 },
    options: {
      type: [{ type: String, enum: REPORT_ANSWER_OPTIONS }],
      required: true,
      validate: {
        validator: (options: string[]) => options.length > 0,
        message: 'At least one answer option is required.',
      },
    },
  },
  { _id: false, strict: 'throw' },
);

export const reportTemplateSchema = new Schema<ReportTemplate>(
  {
    key: { type: String, required: true, trim: true, maxlength: 100 },
    version: { type: Number, required: true, min: 1 },
    title: { type: String, required: true, trim: true, maxlength: 250 },
    prompt: { type: String, required: true, trim: true, maxlength: 2_000 },
    questions: { type: [reportQuestionSchema], required: true, default: [] },
    active: { type: Boolean, required: true, default: true },
  },
  { strict: 'throw', timestamps: true, versionKey: false },
);

reportTemplateSchema.index(
  { key: 1, version: 1 },
  { unique: true, name: 'uniq_report_templates_key_version' },
);
reportTemplateSchema.index({ key: 1, active: 1 }, { name: 'idx_report_templates_key_active' });
