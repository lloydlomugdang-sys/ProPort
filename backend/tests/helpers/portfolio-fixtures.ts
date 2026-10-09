import { Readable } from 'node:stream';
import { Types } from 'mongoose';
import type { DocumentRecord } from '../../src/database/repositories/document.repository.js';
import type { PortfolioExportInfo } from '../../src/modules/portfolios/portfolio-generator.service.js';
import type { ObjectStorage } from '../../src/infrastructure/storage/object-storage.js';

export const PORTFOLIO_TEST_INFO: PortfolioExportInfo = {
  fullName: 'Test Student', yearAndSection: 'Fourth Year - A', schedule: 'Monday 9:00 AM - 11:00 AM',
  instructorName: 'Test Instructor', course: 'Seminars and Fieldtrip', courseCode: 'TEST401',
  semesterAndYear: 'Test Semester / Test Academic Year',
};

export function portfolioDocument(patch: Partial<DocumentRecord> = {}): DocumentRecord {
  return {
    _id: new Types.ObjectId(), ownerId: new Types.ObjectId(),
    categoryKey: 'certificates', folderKey: 'seminars', title: 'Test seminar',
    documentDate: new Date('2026-01-01'), createdAt: new Date('2026-01-01'), updatedAt: new Date('2026-01-01'),
    objectKey: 'test/image.png', originalFileName: 'image.png', mimeType: 'image/png',
    fileKind: 'image', extension: 'png', sizeBytes: 1, sha256: 'test', ...patch,
  } as DocumentRecord;
}

export function portfolioMemoryStorage(files = new Map<string, Buffer>()): ObjectStorage {
  return {
    async get(key) {
      const bytes = files.get(key);
      if (!bytes) throw new Error('Missing test file');
      return Readable.from([bytes]);
    },
    async put(key, stream) {
      const chunks: Buffer[] = [];
      for await (const chunk of stream) chunks.push(Buffer.from(chunk));
      const bytes = Buffer.concat(chunks);
      files.set(key, bytes);
      return { key, sizeBytes: bytes.length };
    },
    async delete(key) { files.delete(key); },
    async exists(key) { return files.has(key); },
    async healthCheck() { return { status: 'local' }; },
  };
}
