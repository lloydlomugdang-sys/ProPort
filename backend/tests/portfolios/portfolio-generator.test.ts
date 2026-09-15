import { Readable } from 'node:stream';
import { inflateSync } from 'node:zlib';
import { PDFDocument } from 'pdf-lib';
import { describe, expect, it } from 'vitest';
import {
  PortfolioGeneratorService,
  type PortfolioExportInfo,
} from '../../src/modules/portfolios/portfolio-generator.service.js';
import type { ObjectStorage, StoredObject } from '../../src/infrastructure/storage/object-storage.js';
import type { DocumentRecord } from '../../src/database/repositories/document.repository.js';
import type { ServiceHealth } from '../../src/common/types/service-health.js';
import { Types } from 'mongoose';

function hexToString(hex: string): string {
  let str = '';
  for (let i = 0; i < hex.length; i += 2) {
    str += String.fromCharCode(parseInt(hex.slice(i, i + 2), 16));
  }
  return str;
}

function extractAllPdfText(pdfBytes: Buffer): string {
  const raw = pdfBytes.toString('latin1');
  let accumulated = raw;
  const regex = /stream\r?\n([\s\S]*?)\r?\nendstream/g;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(raw)) !== null) {
    const streamContent = match[1];
    if (!streamContent) continue;
    const streamBuffer = Buffer.from(streamContent, 'latin1');
    try {
      const decompressed = inflateSync(streamBuffer).toString('latin1');
      accumulated += '\n' + decompressed;
      const hexMatches = decompressed.matchAll(/<([0-9a-fA-F]+)>/g);
      for (const h of hexMatches) {
        const hex = h[1];
        if (hex) accumulated += ' ' + hexToString(hex);
      }
    } catch {
      // Ignore non-zlib streams
    }
  }
  return accumulated;
}

const SAMPLE_1X1_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  'base64',
);

const SAMPLE_1X1_JPG = Buffer.from(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/Af/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQMBAT8Bf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQIBAT8Bf//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAT8Af//Z',
  'base64',
);

class InMemoryStorage implements ObjectStorage {
  readonly items = new Map<string, Buffer>();

  set(key: string, buffer: Buffer): void {
    this.items.set(key, buffer);
  }

  async put(key: string, contents: Readable): Promise<StoredObject> {
    const chunks: Buffer[] = [];
    for await (const chunk of contents) {
      chunks.push(typeof chunk === 'string' ? Buffer.from(chunk) : chunk);
    }
    const buf = Buffer.concat(chunks);
    this.items.set(key, buf);
    return { key, sizeBytes: buf.length };
  }

  async get(key: string): Promise<Readable> {
    const data = this.items.get(key);
    if (!data) throw new Error(`Object not found in test storage: ${key}`);
    return Readable.from([data]);
  }

  async delete(key: string): Promise<void> {
    this.items.delete(key);
  }

  async exists(key: string): Promise<boolean> {
    return this.items.has(key);
  }

  async healthCheck(): Promise<ServiceHealth> {
    return { status: 'local' };
  }
}

async function createSamplePdf(pageCount = 2): Promise<Buffer> {
  const doc = await PDFDocument.create();
  for (let i = 0; i < pageCount; i++) {
    const page = doc.addPage([612, 792]);
    page.drawText(`Sample PDF Page ${i + 1}`, { x: 50, y: 700 });
  }
  const bytes = await doc.save();
  return Buffer.from(bytes);
}

const testInfo: PortfolioExportInfo = {
  fullName: 'John Lloyd Tester',
  yearAndSection: 'BSIT 4-A',
  schedule: 'MW 9:00AM - 11:00AM',
  instructorName: 'Prof. Alan Turing',
  course: 'Senior Practicum Portfolio',
  courseCode: 'IT-401',
  semesterAndYear: '2nd Semester 2025-2026',
};

function createMockDocument(data: Partial<DocumentRecord>): DocumentRecord {
  const ext = data.extension ?? (data.mimeType === 'image/jpeg' ? 'jpg' : data.mimeType === 'application/pdf' ? 'pdf' : 'png');
  return {
    _id: new Types.ObjectId(),
    ownerId: new Types.ObjectId(),
    categoryKey: 'certificates',
    folderKey: 'certificate-of-attendance',
    title: 'Certificate of Attendance',
    documentDate: new Date('2026-01-15T00:00:00.000Z'),
    description: 'Attendance at annual conference',
    reflection: 'Gained valuable insights on software architecture.',
    originalFileName: `cert.${ext}`,
    objectKey: `users/123/documents/cert.${ext}`,
    mimeType: ext === 'jpg' ? 'image/jpeg' : ext === 'pdf' ? 'application/pdf' : 'image/png',
    fileKind: ext === 'pdf' ? 'pdf' : 'image',
    extension: ext,
    sizeBytes: SAMPLE_1X1_PNG.length,
    sha256: 'abc123',
    createdAt: new Date('2026-01-15T00:00:00.000Z'),
    updatedAt: new Date('2026-01-15T00:00:00.000Z'),
    ...data,
  } as DocumentRecord;
}

describe('PortfolioGeneratorService', () => {
  it('generates a valid canonical PDF with title page and empty TOC when no documents exist', async () => {
    const storage = new InMemoryStorage();
    const generator = new PortfolioGeneratorService(undefined, storage);

    const pdfBytes = await generator.generateFromDocuments([], testInfo);

    expect(pdfBytes).toBeInstanceOf(Buffer);
    expect(pdfBytes.length).toBeGreaterThan(0);

    const loaded = await PDFDocument.load(pdfBytes);
    // Title page (1) + Table of Contents (1) = 2 pages
    expect(loaded.getPageCount()).toBe(2);
  });

  it('generates academic portfolio with title page, TOC, dividers, and embedded image & PDF artifacts', async () => {
    const storage = new InMemoryStorage();
    const generator = new PortfolioGeneratorService(undefined, storage);

    const samplePdfBytes = await createSamplePdf(2);
    storage.set('users/123/documents/cert.png', SAMPLE_1X1_PNG);
    storage.set('users/123/documents/photo.jpg', SAMPLE_1X1_JPG);
    storage.set('users/123/documents/cv.pdf', samplePdfBytes);

    const docImage = createMockDocument({
      categoryKey: 'certificates',
      folderKey: 'certificate-of-attendance',
      title: 'Dev Conference Cert',
      description: 'Proof of attendance at national summit',
      reflection: 'Deepened understanding of distributed systems.',
      objectKey: 'users/123/documents/cert.png',
      originalFileName: 'cert.png',
      mimeType: 'image/png',
      fileKind: 'image',
      sizeBytes: SAMPLE_1X1_PNG.length,
    });

    const docJpg = createMockDocument({
      categoryKey: 'accomplishments',
      folderKey: 'awards-recognitions',
      title: 'Dean’s Honor Award',
      description: 'First honor recipient',
      reflection: 'Consistent effort throughout the academic year.',
      objectKey: 'users/123/documents/photo.jpg',
      originalFileName: 'photo.jpg',
      mimeType: 'image/jpeg',
      fileKind: 'image',
      sizeBytes: SAMPLE_1X1_JPG.length,
    });

    const docPdf = createMockDocument({
      categoryKey: 'cv',
      folderKey: 'curriculum-vitae',
      title: 'Curriculum Vitae',
      description: 'Updated resume with technical projects',
      reflection: 'Highlights engineering experiences.',
      objectKey: 'users/123/documents/cv.pdf',
      originalFileName: 'cv.pdf',
      mimeType: 'application/pdf',
      fileKind: 'pdf',
      sizeBytes: samplePdfBytes.length,
    });

    const pdfBytes = await generator.generateFromDocuments(
      [docImage, docJpg, docPdf],
      testInfo,
    );

    expect(pdfBytes).toBeInstanceOf(Buffer);
    const loaded = await PDFDocument.load(pdfBytes);

    // Expected pages:
    // 1: Title page
    // 2: Table of contents
    // 3: CV Section divider
    // 4: CV metadata overview sheet (since it has description/reflection)
    // 5: CV uploaded PDF page 1
    // 6: CV uploaded PDF page 2
    // 7: Certificates Section divider
    // 8: Certificates image artifact page
    // 9: Accomplishments Section divider
    // 10: Accomplishments image artifact page
    // Total = 10 pages
    expect(loaded.getPageCount()).toBe(10);
  });

  it('embeds multi-page logical document preserving order and rendering page indicators', async () => {
    const storage = new InMemoryStorage();
    const generator = new PortfolioGeneratorService(undefined, storage);

    storage.set('users/123/documents/page1.png', SAMPLE_1X1_PNG);
    storage.set('users/123/documents/page2.png', SAMPLE_1X1_PNG);

    const multiPageDoc = createMockDocument({
      categoryKey: 'scholastic-record',
      folderKey: 'transcript-of-records',
      title: 'Official TOR',
      description: 'Complete academic marks',
      reflection: 'Reflects my cumulative coursework performance.',
      objectKey: 'users/123/documents/page1.png',
      originalFileName: 'page1.png',
      mimeType: 'image/png',
      fileKind: 'image',
      sizeBytes: SAMPLE_1X1_PNG.length * 2,
      attachments: [
        {
          id: '1',
          originalFileName: 'page1.png',
          objectKey: 'users/123/documents/page1.png',
          mimeType: 'image/png',
          fileKind: 'image',
          extension: 'png',
          sizeBytes: SAMPLE_1X1_PNG.length,
          sha256: 'abc123',
          order: 0,
        },
        {
          id: '2',
          originalFileName: 'page2.png',
          objectKey: 'users/123/documents/page2.png',
          mimeType: 'image/png',
          fileKind: 'image',
          extension: 'png',
          sizeBytes: SAMPLE_1X1_PNG.length,
          sha256: 'abc123',
          order: 1,
        },
      ],
    });

    const pdfBytes = await generator.generateFromDocuments([multiPageDoc], testInfo);

    const loaded = await PDFDocument.load(pdfBytes);
    // 1: Title page
    // 2: Table of Contents
    // 3: Scholastic Record Section Divider
    // 4: Attachment page 1
    // 5: Attachment page 2
    // Total = 5 pages
    expect(loaded.getPageCount()).toBe(5);
  });

  it('handles college report as an uploaded category in canonical order', async () => {
    const storage = new InMemoryStorage();
    const generator = new PortfolioGeneratorService(undefined, storage);

    storage.set('users/123/documents/report.png', SAMPLE_1X1_PNG);

    const reportDoc = createMockDocument({
      categoryKey: 'college-report',
      folderKey: 'college-report',
      title: 'Dean’s Terminal Report',
      description: 'Departmental internship report',
      reflection: 'Summarizes practicum hours completed.',
      objectKey: 'users/123/documents/report.png',
      originalFileName: 'report.png',
      mimeType: 'image/png',
      fileKind: 'image',
      sizeBytes: SAMPLE_1X1_PNG.length,
    });

    const pdfBytes = await generator.generateFromDocuments([reportDoc], testInfo);

    const loaded = await PDFDocument.load(pdfBytes);
    // 1: Title page
    // 2: TOC
    // 3: College Report Section Divider
    // 4: Artifact page
    // Total = 4 pages
    expect(loaded.getPageCount()).toBe(4);
  });

  it('rejects portfolio exceeding total source byte limit', async () => {
    const storage = new InMemoryStorage();
    const generator = new PortfolioGeneratorService(undefined, storage);

    const hugeDoc = createMockDocument({
      sizeBytes: 55 * 1024 * 1024, // 55 MB > 50 MB limit
    });

    await expect(
      generator.generateFromDocuments([hugeDoc], testInfo),
    ).rejects.toThrow('Your portfolio is too large to generate in one export.');
  });

  it('rejects corrupted PDF artifacts with honest failure code', async () => {
    const storage = new InMemoryStorage();
    const generator = new PortfolioGeneratorService(undefined, storage);

    storage.set('users/123/documents/corrupt.pdf', Buffer.from('not a real pdf content'));

    const corruptDoc = createMockDocument({
      fileKind: 'pdf',
      mimeType: 'application/pdf',
      objectKey: 'users/123/documents/corrupt.pdf',
      sizeBytes: 100,
    });

    await expect(
      generator.generateFromDocuments([corruptDoc], testInfo),
    ).rejects.toMatchObject({
      code: 'PORTFOLIO_ARTIFACT_CORRUPT',
    });
  });

  describe('real artifact incorporation verification', () => {
    it('embeds real JPEG and real PNG with correct PDF image XObjects', async () => {
      const storage = new InMemoryStorage();
      const generator = new PortfolioGeneratorService(undefined, storage);

      storage.set('users/123/documents/real_image.jpg', SAMPLE_1X1_JPG);
      storage.set('users/123/documents/real_image.png', SAMPLE_1X1_PNG);

      const jpgDoc = createMockDocument({
        categoryKey: 'certificates',
        folderKey: 'certificate-of-attendance',
        title: 'Real JPEG Certificate',
        objectKey: 'users/123/documents/real_image.jpg',
        originalFileName: 'real_image.jpg',
        mimeType: 'image/jpeg',
        fileKind: 'image',
        extension: 'jpg',
      });

      const pngDoc = createMockDocument({
        categoryKey: 'accomplishments',
        folderKey: 'awards-recognitions',
        title: 'Real PNG Award',
        objectKey: 'users/123/documents/real_image.png',
        originalFileName: 'real_image.png',
        mimeType: 'image/png',
        fileKind: 'image',
        extension: 'png',
      });

      const pdfBytes = await generator.generateFromDocuments([jpgDoc, pngDoc], testInfo);
      const pdfString = pdfBytes.toString('latin1');

      // Verify JPEG DCTDecode filter and PNG FlateDecode filter in PDF image XObjects
      expect(pdfString).toContain('/Subtype /Image');
      expect(pdfString).toContain('/Filter /DCTDecode');
      expect(pdfString).toContain('/Filter /FlateDecode');
    });

    it('copies all pages from actual multi-page source PDF via copyPages and preserves vector/text content', async () => {
      const storage = new InMemoryStorage();
      const generator = new PortfolioGeneratorService(undefined, storage);

      // Create a 3-page vector PDF with unique text markers and drawing commands
      const sourceDoc = await PDFDocument.create();
      const markers = [
        'VECTOR_CONTENT_PAGE_1_MARKER_9981',
        'VECTOR_CONTENT_PAGE_2_MARKER_9982',
        'VECTOR_CONTENT_PAGE_3_MARKER_9983',
      ];
      for (const marker of markers) {
        const page = sourceDoc.addPage([612, 792]);
        page.drawText(marker, { x: 50, y: 700 });
        page.drawRectangle({ x: 50, y: 600, width: 100, height: 50 });
      }
      const sourceBytes = Buffer.from(await sourceDoc.save());
      storage.set('users/123/documents/multipage.pdf', sourceBytes);

      const pdfDoc = createMockDocument({
        categoryKey: 'cv',
        folderKey: 'curriculum-vitae',
        title: '3-Page Official CV',
        description: 'Comprehensive curriculum vitae',
        reflection: 'VECTOR_REFLECTION_MARKER_4455',
        objectKey: 'users/123/documents/multipage.pdf',
        originalFileName: 'multipage.pdf',
        mimeType: 'application/pdf',
        fileKind: 'pdf',
        extension: 'pdf',
        sizeBytes: sourceBytes.length,
      });

      const pdfBytes = await generator.generateFromDocuments([pdfDoc], testInfo);
      const loaded = await PDFDocument.load(pdfBytes);

      // 1: Title page, 2: TOC, 3: CV divider, 4: CV metadata overview, 5: Page 1, 6: Page 2, 7: Page 3 = 7 pages total
      expect(loaded.getPageCount()).toBe(7);

      const allText = extractAllPdfText(pdfBytes);
      // All 3 vector text markers preserved from source PDF
      for (const marker of markers) {
        expect(allText).toContain(marker);
      }
      expect(allText).toContain('VECTOR_REFLECTION_MARKER_4455');
    });

    it('maintains deterministic order of multiple image attachments within a logical document', async () => {
      const storage = new InMemoryStorage();
      const generator = new PortfolioGeneratorService(undefined, storage);

      storage.set('users/123/documents/doc_page_01.png', SAMPLE_1X1_PNG);
      storage.set('users/123/documents/doc_page_02.jpg', SAMPLE_1X1_JPG);

      const multiPageDoc = createMockDocument({
        categoryKey: 'scholastic-record',
        folderKey: 'transcript-of-records',
        title: 'Official Transcripts',
        description: 'Semester 1 and 2 transcript sheets',
        reflection: 'Maintained consistent high remarks.',
        objectKey: 'users/123/documents/doc_page_01.png',
        originalFileName: 'doc_page_01.png',
        mimeType: 'image/png',
        fileKind: 'image',
        sizeBytes: SAMPLE_1X1_PNG.length + SAMPLE_1X1_JPG.length,
        attachments: [
          {
            id: 'page-1',
            originalFileName: 'doc_page_01.png',
            objectKey: 'users/123/documents/doc_page_01.png',
            mimeType: 'image/png',
            fileKind: 'image',
            extension: 'png',
            sizeBytes: SAMPLE_1X1_PNG.length,
            sha256: 'hash1',
            order: 0,
          },
          {
            id: 'page-2',
            originalFileName: 'doc_page_02.jpg',
            objectKey: 'users/123/documents/doc_page_02.jpg',
            mimeType: 'image/jpeg',
            fileKind: 'image',
            extension: 'jpg',
            sizeBytes: SAMPLE_1X1_JPG.length,
            sha256: 'hash2',
            order: 1,
          },
        ],
      });

      const pdfBytes = await generator.generateFromDocuments([multiPageDoc], testInfo);
      const loaded = await PDFDocument.load(pdfBytes);

      // Title (1) + TOC (1) + Section Divider (1) + Page 1 (1) + Page 2 (1) = 5 pages
      expect(loaded.getPageCount()).toBe(5);

      const allText = extractAllPdfText(pdfBytes);
      expect(allText).toContain('Page 1 of 2');
      expect(allText).toContain('Page 2 of 2');

      const page1Pos = allText.indexOf('Page 1 of 2');
      const page2Pos = allText.indexOf('Page 2 of 2');
      expect(page1Pos).toBeGreaterThan(-1);
      expect(page2Pos).toBeGreaterThan(page1Pos);
    });

    it('associates metadata and reflections with the correct distinct artifact', async () => {
      const storage = new InMemoryStorage();
      const generator = new PortfolioGeneratorService(undefined, storage);

      storage.set('users/123/documents/cert_a.png', SAMPLE_1X1_PNG);
      storage.set('users/123/documents/cert_b.png', SAMPLE_1X1_PNG);

      const docA = createMockDocument({
        categoryKey: 'certificates',
        folderKey: 'certificate-of-attendance',
        title: 'Cert A - Cloud Architecture',
        description: 'Cloud training certificate',
        reflection: 'UNIQUE_REFLECTION_CLOUD_1122',
        objectKey: 'users/123/documents/cert_a.png',
        originalFileName: 'cert_a.png',
      });

      const docB = createMockDocument({
        categoryKey: 'certificates',
        folderKey: 'certificate-of-completion',
        title: 'Cert B - Security Auditing',
        description: 'Security auditing certificate',
        reflection: 'UNIQUE_REFLECTION_SECURITY_3344',
        objectKey: 'users/123/documents/cert_b.png',
        originalFileName: 'cert_b.png',
      });

      const pdfBytes = await generator.generateFromDocuments([docA, docB], testInfo);
      const allText = extractAllPdfText(pdfBytes);

      expect(allText).toContain('Cert A - Cloud Architecture');
      expect(allText).toContain('UNIQUE_REFLECTION_CLOUD_1122');
      expect(allText).toContain('Cert B - Security Auditing');
      expect(allText).toContain('UNIQUE_REFLECTION_SECURITY_3344');

      const docAPos = allText.indexOf('UNIQUE_REFLECTION_CLOUD_1122');
      const docBPos = allText.indexOf('UNIQUE_REFLECTION_SECURITY_3344');
      expect(docAPos).toBeGreaterThan(-1);
      expect(docBPos).toBeGreaterThan(docAPos);
    });
  });
});
