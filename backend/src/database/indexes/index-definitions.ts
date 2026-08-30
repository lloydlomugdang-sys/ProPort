import { createHash } from 'node:crypto';
import { COLLECTION_NAMES, type ApplicationCollectionName } from '../collection-names.js';

export type IndexDirection = 1 | -1;

export interface ApplicationIndexDefinition {
  readonly collection: ApplicationCollectionName;
  readonly name: string;
  readonly key: Readonly<Record<string, IndexDirection>>;
  readonly unique?: true;
  readonly expireAfterSeconds?: number;
}

export const APPLICATION_INDEXES: readonly ApplicationIndexDefinition[] = [
  {
    collection: COLLECTION_NAMES.users,
    name: 'uniq_users_email',
    key: { email: 1 },
    unique: true,
  },
  {
    collection: COLLECTION_NAMES.sessions,
    name: 'uniq_sessions_refresh_token_hash',
    key: { refreshTokenHash: 1 },
    unique: true,
  },
  {
    collection: COLLECTION_NAMES.sessions,
    name: 'idx_sessions_user_revoked',
    key: { userId: 1, revokedAt: 1 },
  },
  {
    collection: COLLECTION_NAMES.sessions,
    name: 'idx_sessions_family',
    key: { familyId: 1 },
  },
  {
    collection: COLLECTION_NAMES.sessions,
    name: 'ttl_sessions_expires_at',
    key: { expiresAt: 1 },
    expireAfterSeconds: 0,
  },
  {
    collection: COLLECTION_NAMES.oneTimeCodes,
    name: 'idx_one_time_codes_user_type_consumed',
    key: { userId: 1, type: 1, consumedAt: 1 },
  },
  {
    collection: COLLECTION_NAMES.oneTimeCodes,
    name: 'ttl_one_time_codes_expires_at',
    key: { expiresAt: 1 },
    expireAfterSeconds: 0,
  },
  {
    collection: COLLECTION_NAMES.documentCategories,
    name: 'uniq_document_categories_key',
    key: { key: 1 },
    unique: true,
  },
  {
    collection: COLLECTION_NAMES.documentCategories,
    name: 'idx_categories_active_order',
    key: { active: 1, sortOrder: 1 },
  },
  {
    collection: COLLECTION_NAMES.documents,
    name: 'idx_documents_owner_category_folder_created',
    key: { ownerId: 1, categoryKey: 1, folderKey: 1, createdAt: -1 },
  },
  {
    collection: COLLECTION_NAMES.documents,
    name: 'idx_documents_owner_kind_created',
    key: { ownerId: 1, fileKind: 1, createdAt: -1 },
  },
  {
    collection: COLLECTION_NAMES.documents,
    name: 'idx_documents_owner_document_date',
    key: { ownerId: 1, documentDate: -1 },
  },
  {
    collection: COLLECTION_NAMES.documents,
    name: 'uniq_documents_object_key',
    key: { objectKey: 1 },
    unique: true,
  },
  {
    collection: COLLECTION_NAMES.reportTemplates,
    name: 'uniq_report_templates_key_version',
    key: { key: 1, version: 1 },
    unique: true,
  },
  {
    collection: COLLECTION_NAMES.reportTemplates,
    name: 'idx_report_templates_key_active',
    key: { key: 1, active: 1 },
  },
  {
    collection: COLLECTION_NAMES.collegeReports,
    name: 'uniq_college_reports_owner_template_year',
    key: { ownerId: 1, templateId: 1, academicYear: 1 },
    unique: true,
  },
  {
    collection: COLLECTION_NAMES.collegeReports,
    name: 'idx_college_reports_owner_created',
    key: { ownerId: 1, createdAt: -1 },
  },
] as const;

export const APPLICATION_INDEX_CHECKSUM = createHash('sha256')
  .update(JSON.stringify(APPLICATION_INDEXES))
  .digest('hex');
