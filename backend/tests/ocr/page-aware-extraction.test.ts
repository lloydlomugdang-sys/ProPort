import { describe, expect, it } from 'vitest';
import { PDFDocument, StandardFonts } from 'pdf-lib';
import { LocalOcrEngine } from '../../src/infrastructure/ocr/local-ocr-engine.js';

describe('Page-aware PDF extraction', () => {
  it('extracts per-page text and retains page boundaries and totalPages', async () => {
    const doc = await PDFDocument.create();
    const font = await doc.embedFont(StandardFonts.Helvetica);

    const page1 = doc.addPage([600, 400]);
    page1.drawText('Page 1 Header: Curriculum Vitae of John Lloyd', { x: 50, y: 350, font, size: 14 });
    page1.drawText('Experienced software developer with academic background.', { x: 50, y: 300, font, size: 12 });

    const page2 = doc.addPage([600, 400]);
    page2.drawText('Page 2: Education and Technical Skills', { x: 50, y: 350, font, size: 14 });

    const page3 = doc.addPage([600, 400]);
    page3.drawText('Certificate of Attendance: Advanced Flutter Workshop', { x: 50, y: 350, font, size: 14 });
    page3.drawText('Issued on 2024-05-10 by CICS University', { x: 50, y: 300, font, size: 12 });

    const pdfBuffer = Buffer.from(await doc.save());

    const engine = new LocalOcrEngine();
    const result = await engine.extract({
      contents: pdfBuffer,
      mimeType: 'application/pdf',
      fileKind: 'pdf',
    });

    expect(result.engine).toBe('pdfjs');
    expect(result.totalPages).toBe(3);
    const pages = result.pages;
    expect(pages).toBeDefined();
    if (!pages) throw new Error('pages should be defined');
    expect(pages.length).toBe(3);

    expect(pages[0]?.pageNumber).toBe(1);
    expect(pages[0]?.text).toContain('Curriculum Vitae');
    expect(pages[0]?.text).not.toContain('Certificate of Attendance');

    expect(pages[1]?.pageNumber).toBe(2);
    expect(pages[1]?.text).toContain('Education and Technical Skills');

    expect(pages[2]?.pageNumber).toBe(3);
    expect(pages[2]?.text).toContain('Certificate of Attendance');
    expect(pages[2]?.text).not.toContain('Curriculum Vitae');

    // Combined rawText should still contain all pages
    expect(result.rawText).toContain('Curriculum Vitae');
    expect(result.rawText).toContain('Certificate of Attendance');
  });
});
