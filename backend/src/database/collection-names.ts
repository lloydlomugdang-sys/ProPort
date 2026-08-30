export const COLLECTION_NAMES = {
  users: 'users',
  sessions: 'sessions',
  oneTimeCodes: 'one_time_codes',
  documentCategories: 'document_categories',
  documents: 'documents',
  reportTemplates: 'report_templates',
  collegeReports: 'college_reports',
  migrations: '_gradport_migrations',
  migrationLock: '_gradport_migration_lock',
} as const;

export type ApplicationCollectionName =
  | (typeof COLLECTION_NAMES)['users']
  | (typeof COLLECTION_NAMES)['sessions']
  | (typeof COLLECTION_NAMES)['oneTimeCodes']
  | (typeof COLLECTION_NAMES)['documentCategories']
  | (typeof COLLECTION_NAMES)['documents']
  | (typeof COLLECTION_NAMES)['reportTemplates']
  | (typeof COLLECTION_NAMES)['collegeReports'];
