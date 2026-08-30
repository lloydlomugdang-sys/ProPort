import { Schema, type Types } from 'mongoose';

export const FILE_KINDS = ['image', 'pdf', 'docx'] as const;
export type FileKind = (typeof FILE_KINDS)[number];

export interface Document {
  ownerId: Types.ObjectId;
  categoryKey: string;
  folderKey: string;
  title: string;
  documentDate: Date;
  description?: string;
  reflection?: string;
  originalFileName: string;
  objectKey: string;
  mimeType: string;
  fileKind: FileKind;
  extension: string;
  sizeBytes: number;
  sha256: string;
  createdAt: Date;
  updatedAt: Date;
}

export const documentSchema = new Schema<Document>(
  {
    ownerId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    categoryKey: { type: String, required: true, trim: true, maxlength: 100 },
    folderKey: { type: String, required: true, trim: true, maxlength: 100 },
    title: { type: String, required: true, trim: true, minlength: 1, maxlength: 250 },
    documentDate: { type: Date, required: true },
    description: { type: String, trim: true, maxlength: 2_000 },
    reflection: { type: String, trim: true, maxlength: 5_000 },
    originalFileName: { type: String, required: true, trim: true, maxlength: 255 },
    objectKey: { type: String, required: true, trim: true, maxlength: 1024 },
    mimeType: { type: String, required: true, trim: true, maxlength: 150 },
    fileKind: { type: String, enum: FILE_KINDS, required: true },
    extension: { type: String, required: true, lowercase: true, trim: true, maxlength: 10 },
    sizeBytes: { type: Number, required: true, min: 1, max: 15 * 1024 * 1024 },
    sha256: { type: String, required: true, lowercase: true, trim: true, minlength: 64, maxlength: 64 },
  },
  { strict: 'throw', timestamps: true, versionKey: false },
);

documentSchema.index(
  { ownerId: 1, categoryKey: 1, folderKey: 1, createdAt: -1 },
  { name: 'idx_documents_owner_category_folder_created' },
);
documentSchema.index(
  { ownerId: 1, fileKind: 1, createdAt: -1 },
  { name: 'idx_documents_owner_kind_created' },
);
documentSchema.index(
  { ownerId: 1, documentDate: -1 },
  { name: 'idx_documents_owner_document_date' },
);
documentSchema.index({ objectKey: 1 }, { unique: true, name: 'uniq_documents_object_key' });
