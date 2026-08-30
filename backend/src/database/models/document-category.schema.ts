import { Schema } from 'mongoose';

export interface CategoryFolder {
  key: string;
  name: string;
  sortOrder: number;
  active: boolean;
}

export interface DocumentCategory {
  key: string;
  name: string;
  sortOrder: number;
  active: boolean;
  folders: CategoryFolder[];
  createdAt: Date;
  updatedAt: Date;
}

const categoryFolderSchema = new Schema<CategoryFolder>(
  {
    key: { type: String, required: true, trim: true, maxlength: 100 },
    name: { type: String, required: true, trim: true, maxlength: 150 },
    sortOrder: { type: Number, required: true, min: 0 },
    active: { type: Boolean, required: true, default: true },
  },
  { _id: false, strict: 'throw' },
);

export const documentCategorySchema = new Schema<DocumentCategory>(
  {
    key: { type: String, required: true, trim: true, maxlength: 100 },
    name: { type: String, required: true, trim: true, maxlength: 150 },
    sortOrder: { type: Number, required: true, min: 0 },
    active: { type: Boolean, required: true, default: true },
    folders: { type: [categoryFolderSchema], required: true, default: [] },
  },
  { strict: 'throw', timestamps: true, versionKey: false },
);

documentCategorySchema.index(
  { key: 1 },
  { unique: true, name: 'uniq_document_categories_key' },
);
documentCategorySchema.index({ active: 1, sortOrder: 1 }, { name: 'idx_categories_active_order' });
