import { Schema, type Types } from 'mongoose';
import type { PortfolioTemplateOverride } from '../../modules/portfolios/portfolio-template.js';

export interface Portfolio {
  ownerId: Types.ObjectId;
  fullName: string;
  yearAndSection: string;
  schedule: string;
  instructorName: string;
  course: string;
  courseCode: string;
  semesterAndYear: string;
  creativeTitles?: Record<string, string>;
  templateOverrides?: PortfolioTemplateOverride | null;
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
    creativeTitles: { type: Map, of: { type: String, trim: true, maxlength: 200 }, default: undefined },
    templateOverrides: {
      type: new Schema(
        {
          includeTableOfContents: { type: Boolean },
          sections: [
            new Schema(
              {
                key: { type: String, required: true },
                label: { type: String, maxlength: 120 },
                order: { type: Number, min: 0 },
                enabled: { type: Boolean },
                generateCreativeTitle: { type: Boolean },
              },
              { _id: false },
            ),
          ],
        },
        { _id: false },
      ),
      default: undefined,
    },
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
