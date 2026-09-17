export const documentPathParamsSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['documentId'],
  properties: {
    documentId: { type: 'string', pattern: '^[a-fA-F0-9]{24}$' },
  },
} as const;

export const documentQuerySchema = {
  type: 'object',
  additionalProperties: false,
  maxProperties: 0,
} as const;

export const documentAttachmentPathParamsSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['documentId', 'attachmentId'],
  properties: {
    documentId: { type: 'string', pattern: '^[a-fA-F0-9]{24}$' },
    attachmentId: { type: 'string', minLength: 1, maxLength: 100 },
  },
} as const;

const attachmentSchema = {
  type: 'object',
  additionalProperties: false,
  required: [
    'id',
    'originalFileName',
    'mimeType',
    'fileKind',
    'extension',
    'sizeBytes',
    'order',
  ],
  properties: {
    id: { type: 'string' },
    originalFileName: { type: 'string' },
    mimeType: { type: 'string' },
    fileKind: { enum: ['image', 'pdf'] },
    extension: { type: 'string' },
    sizeBytes: { type: 'integer', minimum: 1 },
    order: { type: 'integer', minimum: 0 },
  },
} as const;

const documentSchema = {
  type: 'object',
  additionalProperties: false,
  required: [
    'id',
    'categoryKey',
    'folderKey',
    'title',
    'documentDate',
    'originalFileName',
    'mimeType',
    'fileKind',
    'extension',
    'sizeBytes',
    'createdAt',
    'updatedAt',
  ],
  properties: {
    id: { type: 'string' },
    categoryKey: { type: 'string' },
    folderKey: { type: 'string' },
    title: { type: 'string' },
    documentDate: { type: 'string', format: 'date-time' },
    description: { type: 'string' },
    reflection: { type: 'string' },
    originalFileName: { type: 'string' },
    mimeType: { type: 'string' },
    fileKind: { enum: ['image', 'pdf', 'docx'] },
    extension: { type: 'string' },
    sizeBytes: { type: 'integer', minimum: 1 },
    attachments: { type: 'array', items: attachmentSchema },
    createdAt: { type: 'string', format: 'date-time' },
    updatedAt: { type: 'string', format: 'date-time' },
  },
} as const;

const metaSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['requestId'],
  properties: { requestId: { type: 'string' } },
} as const;

export const documentResponseSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['data', 'meta'],
  properties: {
    data: {
      type: 'object',
      additionalProperties: false,
      required: ['document'],
      properties: { document: documentSchema },
    },
    meta: metaSchema,
  },
} as const;

const countMapSchema = {
  type: 'object',
  additionalProperties: { type: 'integer', minimum: 0 },
} as const;

export const documentListResponseSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['data', 'meta'],
  properties: {
    data: {
      type: 'object',
      additionalProperties: false,
      required: ['documents', 'summary'],
      properties: {
        documents: { type: 'array', items: documentSchema },
        summary: {
          type: 'object',
          additionalProperties: false,
          required: ['totalCount', 'categoryCounts', 'folderCounts'],
          properties: {
            totalCount: { type: 'integer', minimum: 0 },
            categoryCounts: countMapSchema,
            folderCounts: countMapSchema,
          },
        },
      },
    },
    meta: metaSchema,
  },
} as const;

const folderSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['key', 'name'],
  properties: {
    key: { type: 'string' },
    name: { type: 'string' },
  },
} as const;

const categorySchema = {
  type: 'object',
  additionalProperties: false,
  required: ['key', 'name', 'folders'],
  properties: {
    key: { type: 'string' },
    name: { type: 'string' },
    folders: { type: 'array', items: folderSchema },
  },
} as const;

export const documentCategoryListResponseSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['data', 'meta'],
  properties: {
    data: {
      type: 'object',
      additionalProperties: false,
      required: ['categories'],
      properties: {
        categories: { type: 'array', items: categorySchema },
      },
    },
    meta: metaSchema,
  },
} as const;

export const documentDeleteResponseSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['data', 'meta'],
  properties: {
    data: {
      type: 'object',
      additionalProperties: false,
      required: ['status', 'documentId'],
      properties: {
        status: { type: 'string', const: 'deleted' },
        documentId: { type: 'string' },
      },
    },
    meta: metaSchema,
  },
} as const;

const documentOcrSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['status'],
  properties: {
    status: { enum: ['not_processed', 'processing', 'ready', 'failed'] },
    rawText: { type: 'string' },
    reviewedText: { type: 'string' },
    engine: { enum: ['tesseract.js', 'pdfjs'] },
    processedAt: { type: 'string', format: 'date-time' },
    updatedAt: { type: 'string', format: 'date-time' },
    metadataAnalysis: {
      type: 'object', additionalProperties: false, required: ['source', 'aiStatus'],
      properties: {
        source: { enum: ['gemini', 'rules', 'none'] },
        aiStatus: { enum: ['success', 'unavailable', 'disabled', 'not_needed'] },
      },
    },
    metadataSuggestions: {
      type: 'object',
      additionalProperties: false,
      properties: {
        categoryKey: { type: 'string' },
        folderKey: { type: 'string' },
        title: { type: 'string' },
        documentDate: { type: 'string', format: 'date' },
        description: { type: 'string' },
        confidence: { enum: ['high', 'medium', 'low'] },
      },
    },
  },
} as const;

export const documentOcrResponseSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['data', 'meta'],
  properties: {
    data: {
      type: 'object',
      additionalProperties: false,
      required: ['ocr'],
      properties: { ocr: documentOcrSchema },
    },
    meta: metaSchema,
  },
} as const;

export const documentOcrPatchSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['reviewedText'],
  properties: {
    reviewedText: { type: 'string', maxLength: 200_000 },
  },
} as const;
