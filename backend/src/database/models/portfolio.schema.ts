import { Schema, type Types } from 'mongoose';

export interface Portfolio {
  ownerId: Types.ObjectId;
  fullName: string;
  yearAndSection: string;
  schedule: string;
  instructorName: string;
  course: string;
  courseCode: string;
  semesterAndYear: string;
  createdAt: Date;
  updatedAt: Date;
}

export const portfolioSchema = new Schema<Portfolio>(
  {
    ownerId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    fullName: { type: String, required: true, trim: true, minlength: 1, maxlength: 200 },
    yearAndSection: {
      type: String,
      required: true,
      trim: true,
      minlength: 1,
      maxlength: 100,
    },
    schedule: { type: String, required: true, trim: true, minlength: 1, maxlength: 200 },
    instructorName: {
      type: String,
      required: true,
      trim: true,
      minlength: 1,
      maxlength: 200,
    },
    course: { type: String, trim: true, maxlength: 200, default: '' },
    courseCode: { type: String, trim: true, maxlength: 100, default: '' },
    semesterAndYear: {
      type: String,
      trim: true,
      maxlength: 100,
      default: '',
    },
  },
  { strict: 'throw', timestamps: true, versionKey: false },
);

portfolioSchema.index(
  { ownerId: 1, updatedAt: -1 },
  { name: 'idx_portfolios_owner_updated' },
);
