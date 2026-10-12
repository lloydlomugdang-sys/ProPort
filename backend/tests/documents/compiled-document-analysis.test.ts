import { Readable } from 'node:stream';
import { Types } from 'mongoose';
import { PDFDocument, StandardFonts } from 'pdf-lib';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { runMigrations } from '../../src/database/migrations/migration-runner.js';
import { seedDatabase } from '../../src/database/seeds/seed-database.js';
import { LocalOcrEngine } from '../../src/infrastructure/ocr/local-ocr-engine.js';
import type { ObjectStorage, StoredObject } from '../../src/infrastructure/storage/object-storage.js';
import { AiMetadataService } from '../../src/modules/documents/ai-metadata.service.js';
import { CompiledDocumentService, hasCompleteCoverage } from '../../src/modules/documents/compiled-document.service.js';
import { mixedPdf } from '../helpers/mixed-pdf-fixtures.js';
import {
  createDisposableMongoDatabase,
  type DisposableMongoDatabase,
} from '../helpers/disposable-mongodb.js';

class MemoryStorage implements ObjectStorage {
  readonly objects = new Map<string, Buffer>();

  async put(key: string, contents: Readable): Promise<StoredObject> {
    const chunks: Buffer[] = [];
    for await (const chunk of contents) {
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    }
    const buf = Buffer.concat(chunks);
    this.objects.set(key, buf);
    return { key, sizeBytes: buf.length };
  }

  async get(key: string): Promise<Readable> {
    const buf = this.objects.get(key);
    if (!buf) throw new Error(`Not found: ${key}`);
    return Readable.from([buf]);
  }

  async delete(key: string): Promise<void> {
    this.objects.delete(key);
  }

  async exists(key: string): Promise<boolean> {
    return this.objects.has(key);
  }

  async healthCheck() {
    return { status: 'up' as const };
  }
}

describe('Compiled document analysis service', () => {
  let disposable: DisposableMongoDatabase;
  let storage: MemoryStorage;
  let ocrEngine: LocalOcrEngine;
  const ownerId = new Types.ObjectId();

  beforeAll(async () => {
    disposable = await createDisposableMongoDatabase();
    await runMigrations(disposable.connection.db!);
    await seedDatabase(disposable.connection);
    storage = new MemoryStorage();
    ocrEngine = new LocalOcrEngine();
  });

  afterAll(async () => {
    await disposable?.stop();
  });

  async function createMultiDocPdf(): Promise<Buffer> {
    const doc = await PDFDocument.create();
    const font = await doc.embedFont(StandardFonts.Helvetica);

    // Page 1: CV
    const p1 = doc.addPage([600, 400]);
    p1.drawText('CURRICULUM VITAE', { x: 50, y: 350, font, size: 16 });
    p1.drawText('John Lloyd - Software Engineer and Researcher', { x: 50, y: 320, font, size: 12 });
    p1.drawText('Experienced in Flutter, Dart, TypeScript, Node.js and MongoDB.', { x: 50, y: 300, font, size: 12 });

    // Page 2: TOR
    const p2 = doc.addPage([600, 400]);
    p2.drawText('TRANSCRIPT OF RECORDS', { x: 50, y: 350, font, size: 16 });
    p2.drawText('Bachelor of Science in Information Technology - CICS', { x: 50, y: 320, font, size: 12 });
    p2.drawText('Course: Advanced Mobile Development - Grade: 1.00', { x: 50, y: 300, font, size: 12 });

    // Page 3: Certificate
    const p3 = doc.addPage([600, 400]);
    p3.drawText('CERTIFICATE OF PARTICIPATION', { x: 50, y: 350, font, size: 16 });
    p3.drawText('This certifies that the participant attended the Flutter Seminar', { x: 50, y: 320, font, size: 12 });
    p3.drawText('Issued on 2024-05-15 by Tech Society', { x: 50, y: 300, font, size: 12 });

    return Buffer.from(await doc.save());
  }

  it('retains blank pages and requests manual category review', async () => {
    const doc = await PDFDocument.create();
    doc.addPage([600, 400]); // Blank page
    const emptyPdf = Buffer.from(await doc.save());

    const service = new CompiledDocumentService(
      disposable.database,
      storage,
      ocrEngine,
    );

    await expect(
      service.analyze(ownerId, {
        contents: emptyPdf,
        mimeType: 'application/pdf',
        originalFileName: 'scanned_portfolio.pdf',
      }),
    ).resolves.toMatchObject({
      detection: 'needs_review',
      pages: [{ pageNumber: 1, source: 'blank', status: 'ready' }],
    });
  });

  it('produces multiple proposed logical documents via heuristic boundary detection when AI is not configured', async () => {
    const pdfBytes = await createMultiDocPdf();
    const service = new CompiledDocumentService(
      disposable.database,
      storage,
      ocrEngine,
    );

    const result = await service.analyze(ownerId, {
      contents: pdfBytes,
      mimeType: 'application/pdf',
      originalFileName: 'compiled_portfolio.pdf',
    });

    expect(result.sessionId).toMatch(/^csess_/);
    expect(result.totalPages).toBe(3);
    expect(result.originalFileName).toBe('compiled_portfolio.pdf');

    // Should detect the 3 distinct document sections
    expect(result.documents.length).toBe(3);

    // Document 1: CV
    expect(result.documents[0]?.startPage).toBe(1);
    expect(result.documents[0]?.endPage).toBe(1);
    expect(result.documents[0]?.categoryKey).toBe('curriculum-vitae');

    // Document 2: TOR
    expect(result.documents[1]?.startPage).toBe(2);
    expect(result.documents[1]?.endPage).toBe(2);
    expect(result.documents[1]?.categoryKey).toBe('scholastic-record');

    // Document 3: Certificate
    expect(result.documents[2]?.startPage).toBe(3);
    expect(result.documents[2]?.endPage).toBe(3);
    expect(result.documents[2]?.categoryKey).toBe('certificates');

    // Temporary PDF was stored in storage
    const tempKey = `users/${ownerId.toString()}/temp-compiled/${result.sessionId}.pdf`;
    expect(await storage.exists(tempKey)).toBe(true);
  });

  it('reuses normal metadata for a single page without a second Gemini or OCR request', async () => {
    const source = await PDFDocument.load(await createMultiDocPdf());
    const single = await PDFDocument.create();
    single.addPage((await single.copyPages(source, [0]))[0]!);
    let metadataCalls = 0;
    let separationCalls = 0;
    const metadata = new AiMetadataService({
      async recommend() {
        metadataCalls++;
        return { content: 'curriculum-vitae', folder: 'curriculum-vitae', title: 'CURRICULUM VITAE',
          date: null, classificationEvidence: 'CURRICULUM VITAE',
          descriptionQuotes: ['Experienced in Flutter, Dart, TypeScript, Node.js and MongoDB.'] };
      },
      async separateCompiled() { separationCalls++; throw new Error('No page boundary needed'); },
    });
    const service = new CompiledDocumentService(disposable.database, storage, ocrEngine, metadata);
    const result = await service.analyze(ownerId, { contents: Buffer.from(await single.save()), mimeType: 'application/pdf', originalFileName: 'cv.pdf' });
    expect(metadataCalls).toBe(1);
    expect(separationCalls).toBe(0);
    expect(result.detection).toBe('single');
    expect(result.metadataAnalysis).toEqual({ source: 'gemini', aiStatus: 'success' });
    expect(result.metadataSuggestions).toMatchObject({ categoryKey: 'curriculum-vitae', folderKey: 'curriculum-vitae', title: 'CURRICULUM VITAE', description: 'Experienced in Flutter, Dart, TypeScript, Node.js and MongoDB.' });
    expect(result.pages[0]?.text).toContain('John Lloyd - Software Engineer and Researcher');
  });

  it('validates and accepts valid AI separation proposals', async () => {
    const pdfBytes = await createMultiDocPdf();

    const mockAiProvider = {
      model: 'gemini-2.5-flash',
      recommend: async () => ({}),
      separateCompiled: async () => ({
        documents: [
          {
            startPage: 1,
            endPage: 2,
            categoryKey: 'curriculum-vitae',
            folderKey: 'curriculum-vitae',
            title: 'Curriculum Vitae',
            documentDate: '2024-01-01',
            confidence: 0.95,
          },
          {
            startPage: 3,
            endPage: 3,
            categoryKey: 'certificates',
            folderKey: 'seminars',
            title: 'Flutter Seminar Certificate',
            documentDate: '2024-05-15',
            confidence: 0.9,
          },
        ],
      }),
    };

    const metadataService = new AiMetadataService(mockAiProvider);
    const service = new CompiledDocumentService(
      disposable.database,
      storage,
      ocrEngine,
      metadataService,
    );

    const result = await service.analyze(ownerId, {
      contents: pdfBytes,
      mimeType: 'application/pdf',
      originalFileName: 'compiled_portfolio.pdf',
    });

    expect(result.documents.length).toBe(2);
    expect(result.documents[0]?.categoryKey).toBe('curriculum-vitae');
    expect(result.documents[0]?.startPage).toBe(1);
    expect(result.documents[0]?.endPage).toBe(2);
    expect(result.documents[1]?.categoryKey).toBe('certificates');
    expect(result.documents[1]?.startPage).toBe(3);
    expect(result.documents[1]?.endPage).toBe(3);
  });

  it('rejects out-of-range, overlapping, or invalid category AI output and falls back safely', async () => {
    const pdfBytes = await createMultiDocPdf();

    const mockAiProvider = {
      model: 'gemini-2.5-flash',
      recommend: async () => ({}),
      separateCompiled: async () => ({
        documents: [
          {
            startPage: 1,
            endPage: 99, // Out of range! (total pages is 3)
            categoryKey: 'non-existent-category',
            folderKey: 'fake-folder',
            title: 'Invalid Doc',
            documentDate: 'bad-date',
            confidence: 0.5,
          },
        ],
      }),
    };

    const metadataService = new AiMetadataService(mockAiProvider);
    const service = new CompiledDocumentService(
      disposable.database,
      storage,
      ocrEngine,
      metadataService,
    );

    const result = await service.analyze(ownerId, {
      contents: pdfBytes,
      mimeType: 'application/pdf',
      originalFileName: 'compiled_portfolio.pdf',
    });

    // Invalid AI proposals should be rejected and heuristic fallback used
    expect(result.documents.length).toBeGreaterThanOrEqual(1);
    expect(result.documents.every((d) => d.endPage <= 3)).toBe(true);
    expect(result.documents.every((d) => ['curriculum-vitae', 'scholastic-record', 'certificates', 'accomplishments'].includes(d.categoryKey))).toBe(true);
  });

  async function createSyntheticPagesPdf(pageTexts: readonly string[]): Promise<Buffer> {
    const doc = await PDFDocument.create();
    const font = await doc.embedFont(StandardFonts.Helvetica);
    for (const text of pageTexts) {
      const page = doc.addPage([600, 800]);
      const lines = text.split('\n');
      lines.forEach((line, index) => {
        if (line.trim().length > 0) {
          page.drawText(line, { x: 40, y: 740 - index * 24, font, size: 11 });
        }
      });
    }
    return Buffer.from(await doc.save());
  }

  it.each(['digital', 'scanned', 'sparse'] as const)('segments a 7-page heterogeneous PDF (%s continuation) into [1,2], [3,4,5], [6,7] with coursework review and name mismatch warning', async (continuation) => {
    const syntheticPages = [
      // Page 1: Headerless CV page 1
      [
        'Maria Elena S. Cruz',
        'Zone 4, Sample Town | 0917-000-1111 | mariacruz@example.edu',
        'CAREER OBJECTIVES',
        'To contribute software engineering skills and build high- fi delity prototypes for web and mobile platforms.',
        'SYSTEM DEVELOPMENT EXPERIENCE',
        'Developed academic tracking portals and inventory applications.',
        'EDUCATION',
        'Bachelor of Science in Information Technology | 2022-Present',
        'Programming & Scripting: Dart, TypeScript, Python',
        'Tools & Platforms: Git, VS Code, Node.js',
      ].join('\n'),
      // Page 2: Headerless CV page 2
      [
        'Certi fi cates',
        'Introduction to Cybersecurity | Networking Academy | 2025',
        'Awards',
        'Perfect Attendance Award | Academic Year 2018-2019',
        'PERSONAL INFORMATION',
        'Date of Birth : January 10, 2004',
        'Place of Birth : Sample Town',
        'Civil Status : Single',
        'Citizenship : Filipino',
      ].join('\n'),
      // Page 3: Coursework / Module 7 start
      [
        'Cruz, Maria Elena S.',
        '3 BSIT-3',
        'MULTIMEDIA SYSTEM',
        'MODULE 7',
        'Exercise 1 and 2 : Click here for the output',
        '1. Canva',
        '2. Clipchamp',
      ].join('\n'),
      // Page 4: Coursework continuation screenshot page
      [
        'Clipchamp video timeline preview and export panel',
        '3. Animaker',
        '4. H5P : Click here',
        'Animaker project workspace and scene editor',
      ].join('\n'),
      // Page 5: Coursework continuation screenshot page
      [
        'H5P Interactive Content Manager',
        'All content | My Content | UntitledInteractiveVideo',
        'Last modified interactive exercise output',
      ].join('\n'),
      // Page 6: Seminar certificate + Topic Outline + Reflection under a different student name
      [
        'Cruz, Andrea Bea S.',
        '3BSIT-2',
        'Seminar Certi fi cates',
        'Topic: Learn Routing and Switching Using Cisco Packet Tracer',
        'I. Topic Outline',
        '1. Network fundamentals and con fi guring routers and switches',
        'II. Re fl ection Paper',
        'The seminar introduced practical network simulation techniques for students.',
      ].join('\n'),
      // Page 7: Reflection continuation mentioning webinar
      [
        'During the hands-on demonstration, I learned how to build a basic network topology',
        'and verify connectivity across interfaces using simulation tools.',
        'Overall, the webinar was a valuable learning experience that strengthened my networking skills.',
      ].join('\n'),
    ];

    let pdfBytes = await createSyntheticPagesPdf(syntheticPages);
    if (continuation !== 'digital') {
      const pdf = await PDFDocument.load(pdfBytes);
      const scans = await PDFDocument.load(await mixedPdf([
        { text: continuation === 'sparse' ? '3. Animaker' : syntheticPages[3]!, scanned: true },
        { text: continuation === 'sparse' ? 'My Content' : syntheticPages[4]!, scanned: true },
      ]));
      const copied = await pdf.copyPages(scans, [0, 1]);
      for (const [index, page] of copied.entries()) {
        pdf.removePage(index + 3);
        pdf.insertPage(index + 3, page);
      }
      pdfBytes = Buffer.from(await pdf.save());
    }
    const extract = vi.spyOn(ocrEngine, 'extract');
    const service = new CompiledDocumentService(disposable.database, storage, ocrEngine);

    const result = await service.analyze(ownerId, {
      contents: pdfBytes,
      mimeType: 'application/pdf',
      originalFileName: 'heterogeneous_7page.pdf',
    });

    expect(result.totalPages).toBe(7);
    expect(extract).toHaveBeenCalledWith(expect.objectContaining({ profile: 'compiled-analysis' }));
    extract.mockRestore();
    expect(hasCompleteCoverage(result.documents, result.totalPages)).toBe(true);
    expect(result.pages.map((page) => page.pageNumber)).toEqual([1, 2, 3, 4, 5, 6, 7]);
    if (continuation !== 'digital') {
      expect(result.pages.slice(3, 5).map((page) => page.source)).toEqual(['ocr', 'ocr']);
    }
    expect(result.documents.map((d) => [d.startPage, d.endPage])).toEqual([
      [1, 2],
      [3, 5],
      [6, 7],
    ]);

    // Segment 1: Headerless CV
    expect(result.documents[0]?.categoryKey).toBe('curriculum-vitae');
    expect(result.documents[0]?.folderKey).toBe('curriculum-vitae');
    expect(result.documents[0]?.warning).toBeUndefined();

    // Segment 2: Coursework/Module (not forced into thesis-capstone; requires folder review)
    expect(result.documents[1]?.categoryKey).toBe('accomplishments');
    expect(result.documents[1]?.folderKey).toBe('');
    expect(result.documents[1]?.folderKey).not.toBe('thesis-capstone');
    expect(result.documents[1]?.title).toContain('MULTIMEDIA SYSTEM');
    expect(result.documents[1]?.title).toContain('MODULE 7');
    expect(result.documents[1]?.confidence).toBeLessThan(0.75);
    expect(result.documents[1]?.warning).toBeUndefined();

    // Segment 3: Seminar certificate + reflection with name mismatch warning
    expect(result.documents[2]?.categoryKey).toBe('certificates');
    expect(result.documents[2]?.folderKey).toBe('seminars');
    expect(result.documents[2]?.title).toBe('Learn Routing and Switching Using Cisco Packet Tracer');
    expect(result.documents[2]?.warning).toContain('Andrea Bea S. Cruz');
    expect(result.documents[2]?.warning).toContain('Maria Elena S. Cruz');
    expect(result.detection).toBe('needs_review');
  });

  it('preserves AI page boundaries when one segment has a null or ambiguous category and requires review', async () => {
    const pdfBytes = await createMultiDocPdf();
    const mockAiProvider = {
      model: 'gemini-2.5-flash',
      recommend: async () => ({}),
      separateCompiled: async () => ({
        documents: [
          {
            startPage: 1,
            endPage: 1,
            categoryKey: 'Curriculum Vitae', // Canonical label normalized via taxonomy helper
            folderKey: 'Curriculum Vitae',
            title: 'Curriculum Vitae',
            documentDate: null,
            confidence: 0.92,
          },
          {
            startPage: 2,
            endPage: 2,
            categoryKey: null, // Uncertain/null category must not discard boundaries!
            folderKey: null,
            title: 'Module 7 Coursework Output',
            documentDate: null,
            confidence: 0.85,
          },
          {
            startPage: 3,
            endPage: 3,
            categoryKey: 'certificates',
            folderKey: 'seminars',
            title: 'Flutter Seminar',
            documentDate: '2024-05-15',
            confidence: 0.9,
          },
        ],
      }),
    };

    const metadataService = new AiMetadataService(mockAiProvider);
    const service = new CompiledDocumentService(
      disposable.database,
      storage,
      ocrEngine,
      metadataService,
    );

    const result = await service.analyze(ownerId, {
      contents: pdfBytes,
      mimeType: 'application/pdf',
      originalFileName: 'mixed_with_ambiguous_segment.pdf',
    });

    expect(result.documents.map((d) => [d.startPage, d.endPage])).toEqual([
      [1, 1],
      [2, 2],
      [3, 3],
    ]);
    expect(result.documents[0]?.categoryKey).toBe('curriculum-vitae');
    expect(result.documents[1]?.categoryKey).toBe('');
    expect(result.documents[1]?.folderKey).toBe('');
    expect(result.documents[1]?.confidence).toBeLessThanOrEqual(0.4);
    expect(result.documents[2]?.categoryKey).toBe('certificates');
    expect(result.detection).toBe('needs_review');
  });

  it('keeps a single 2-page headerless CV as one document with single detection', async () => {
    const pdfBytes = await createSyntheticPagesPdf([
      [
        'Maria Elena S. Cruz',
        'CAREER OBJECTIVES',
        'Seeking a software engineering role.',
        'SYSTEM DEVELOPMENT EXPERIENCE',
        'Built full-stack web applications.',
        'EDUCATION',
        'Bachelor of Science in Information Technology',
      ].join('\n'),
      [
        'PERSONAL INFORMATION',
        'Date of Birth : January 10, 2004',
        'Place of Birth : Sample Town',
        'Civil Status : Single',
        'Citizenship : Filipino',
      ].join('\n'),
    ]);

    const service = new CompiledDocumentService(disposable.database, storage, ocrEngine);
    const result = await service.analyze(ownerId, {
      contents: pdfBytes,
      mimeType: 'application/pdf',
      originalFileName: 'two_page_cv.pdf',
    });

    expect(result.documents).toHaveLength(1);
    expect(result.documents[0]).toMatchObject({
      startPage: 1,
      endPage: 2,
      categoryKey: 'curriculum-vitae',
      folderKey: 'curriculum-vitae',
    });
    expect(result.detection).toBe('single');
  });

  it('preserves segmentation of readable pages when one page is unresolved and blocks unreviewed split', async () => {
    const pdfBytes = await createMultiDocPdf();
    const customOcr = {
      async extract() {
        return {
          rawText: 'CURRICULUM VITAE\nCERTIFICATE OF PARTICIPATION',
          totalPages: 4,
          engine: 'pdfjs' as const,
          pages: [
            {
              pageNumber: 1,
              text: 'CAREER OBJECTIVES\nSYSTEM DEVELOPMENT EXPERIENCE\nEDUCATION\nBachelor of Science in Information Technology',
              source: 'digital' as const,
              status: 'ready' as const,
            },
            {
              pageNumber: 2,
              text: 'PERSONAL INFORMATION\nDate of Birth : Jan 1, 2003\nPlace of Birth : Manila\nCivil Status : Single\nCitizenship : Filipino',
              source: 'digital' as const,
              status: 'ready' as const,
            },
            {
              pageNumber: 3,
              text: '',
              source: 'failed' as const,
              status: 'unresolved' as const,
            },
            {
              pageNumber: 4,
              text: 'CERTIFICATE OF PARTICIPATION\nTopic: Cloud Native Workshop\nIssued on 2024-05-15 by Tech Society',
              source: 'digital' as const,
              status: 'ready' as const,
            },
          ],
        };
      },
    };

    const service = new CompiledDocumentService(disposable.database, storage, customOcr);
    const analysis = await service.analyze(ownerId, {
      contents: pdfBytes,
      mimeType: 'application/pdf',
      originalFileName: 'partial_unresolved.pdf',
    });

    expect(analysis.detection).toBe('needs_review');
    expect(analysis.documents.map((d) => [d.startPage, d.endPage, d.categoryKey])).toEqual([
      [1, 2, 'curriculum-vitae'],
      [3, 3, ''],
      [4, 4, 'certificates'],
    ]);

    // Unreviewed split with standalone unreadable page is blocked
    await expect(
      service.split(ownerId, {
        sessionId: analysis.sessionId,
        idempotencyKey: 'unreviewed_split_1',
        segments: [
          {
            startPage: 1,
            endPage: 2,
            categoryKey: 'curriculum-vitae',
            folderKey: 'curriculum-vitae',
            title: 'Curriculum Vitae',
            documentDate: '2024-05-15',
          },
          {
            startPage: 3,
            endPage: 3,
            categoryKey: 'accomplishments',
            folderKey: 'projects',
            title: 'Unreadable page — retry required',
            documentDate: '2024-05-15',
          },
          {
            startPage: 4,
            endPage: 4,
            categoryKey: 'certificates',
            folderKey: 'seminars',
            title: 'Cloud Native Workshop',
            documentDate: '2024-05-15',
          },
        ],
      }),
    ).rejects.toMatchObject({ code: 'COMPILED_UNRESOLVED_PAGES' });
  });
});
