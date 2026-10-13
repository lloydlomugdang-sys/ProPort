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
    pages: {
      type: 'array',
      maxItems: 100,
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['pageNumber', 'status'],
        properties: {
          pageNumber: { type: 'integer', minimum: 1 },
          originalFileName: { type: 'string' },
          mimeType: { type: 'string' },
          status: { enum: ['ready', 'failed'] },
          rawText: { type: 'string' },
        },
      },
    },
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

export const documentPatchSchema = {
  type: 'object',
  additionalProperties: false,
  properties: {
    categoryKey: { type: 'string', minLength: 1, maxLength: 100 },
    folderKey: { type: 'string', minLength: 1, maxLength: 100 },
    title: { type: 'string', minLength: 1, maxLength: 250 },
    documentDate: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$' },
    description: { type: 'string', maxLength: 2_000 },
    reflection: { type: 'string', maxLength: 5_000 },
  },
} as const;

export const compiledAnalyzeResponseSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['data', 'meta'],
  properties: {
    data: {
      type: 'object',
      additionalProperties: false,
      required: ['sessionId', 'originalFileName', 'totalPages', 'documents', 'pages', 'detection'],
      properties: {
        sessionId: { type: 'string' },
        detection: { enum: ['single', 'multiple', 'needs_review'] },
        metadataSuggestions: documentOcrSchema.properties.metadataSuggestions,
        metadataAnalysis: documentOcrSchema.properties.metadataAnalysis,
        pages: {
          type: 'array', maxItems: 100,
          items: {
            type: 'object', additionalProperties: false, required: ['pageNumber', 'text', 'source', 'status'],
            properties: {
              pageNumber: { type: 'integer', minimum: 1 }, text: { type: 'string' },
              source: { enum: ['digital', 'ocr', 'blank', 'failed'] }, status: { enum: ['ready', 'unresolved'] },
            },
          },
        },
        originalFileName: { type: 'string' },
        totalPages: { type: 'integer', minimum: 1 },
        documents: {
          type: 'array',
          items: {
            type: 'object',
            additionalProperties: false,
            required: ['startPage', 'endPage', 'categoryKey', 'folderKey', 'title', 'documentDate', 'confidence'],
            properties: {
              startPage: { type: 'integer', minimum: 1 },
              endPage: { type: 'integer', minimum: 1 },
              categoryKey: { type: 'string' },
              folderKey: { type: 'string' },
              title: { type: 'string' },
              documentDate: { type: ['string', 'null'] },
              confidence: { type: 'number' },
              rationale: { type: ['string', 'null'] },
              warning: { type: ['string', 'null'] },
            },
          },
        },
      },
    },
    meta: metaSchema,
  },
} as const;

export const compiledSplitSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['sessionId', 'idempotencyKey', 'segments'],
  properties: {
    sessionId: { type: 'string' },
    idempotencyKey: { type: 'string', minLength: 1, maxLength: 128 },
    segments: {
      type: 'array',
      minItems: 1,
      maxItems: 100,
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['startPage', 'endPage', 'categoryKey', 'folderKey', 'title', 'documentDate'],
        properties: {
          startPage: { type: 'integer', minimum: 1 },
          endPage: { type: 'integer', minimum: 1 },
          categoryKey: { type: 'string' },
          folderKey: { type: 'string' },
          title: { type: 'string', minLength: 1, maxLength: 250 },
          documentDate: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$' },
          description: { type: 'string', maxLength: 2_000 },
          reflection: { type: 'string', maxLength: 5_000 },
        },
      },
    },
  },
} as const;

export const compiledSplitResponseSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['data', 'meta'],
  properties: {
    data: {
      type: 'object',
      additionalProperties: false,
      required: ['documents'],
      properties: {
        documents: {
          type: 'array',
          items: documentSchema,
        },
      },
    },
    meta: metaSchema,
  },
} as const;

export const compiledCancelSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['sessionId'],
  properties: {
    sessionId: { type: 'string' },
  },
} as const;

export const compiledCancelResponseSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['data', 'meta'],
  properties: {
    data: {
      type: 'object',
      additionalProperties: false,
      required: ['cancelled'],
      properties: {
        cancelled: { type: 'boolean' },
      },
    },
    meta: metaSchema,
  },
} as const;
