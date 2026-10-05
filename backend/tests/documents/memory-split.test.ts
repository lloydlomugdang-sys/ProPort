import { describe, expect, it } from 'vitest';
import { PDFDocument, StandardFonts } from 'pdf-lib';

async function createCompiledPdf(pageCount: number): Promise<Buffer> {
  const doc = await PDFDocument.create();
  const font = await doc.embedFont(StandardFonts.Helvetica);

  for (let i = 1; i <= pageCount; i++) {
    const page = doc.addPage([600, 800]);
    page.drawText(`Compiled Portfolio - Document Section Page ${i}`, { x: 50, y: 750, font, size: 16 });
    page.drawText(`This is representative academic text for page ${i} of ${pageCount}.`, { x: 50, y: 700, font, size: 12 });
    page.drawText('Certificates, grades, curriculum vitae, and project descriptions.', { x: 50, y: 650, font, size: 12 });
  }

  return Buffer.from(await doc.save());
}

describe('Bounded Node.js PDF splitting memory measurement', () => {
  it('measures heap and RSS usage for representative 10-page, 20-page, and 30-page compiled PDFs', async () => {
    const benchmarks: Array<{ pages: number; slices: number; heapDeltaMb: number; peakRssMb: number }> = [];

    for (const pageCount of [10, 20, 30]) {
      const initialMem = process.memoryUsage();
      const pdfBytes = await createCompiledPdf(pageCount);

      const srcDoc = await PDFDocument.load(pdfBytes);
      const totalPages = srcDoc.getPageCount();

      const subDocs: Buffer[] = [];
      const segmentSize = 3;
      for (let start = 0; start < totalPages; start += segmentSize) {
        const end = Math.min(start + segmentSize, totalPages);
        const subDoc = await PDFDocument.create();
        const indices: number[] = [];
        for (let p = start; p < end; p++) indices.push(p);
        const copiedPages = await subDoc.copyPages(srcDoc, indices);
        for (const cp of copiedPages) subDoc.addPage(cp);
        subDocs.push(Buffer.from(await subDoc.save()));
      }

      const peakMem = process.memoryUsage();
      const heapDeltaMb = (peakMem.heapUsed - initialMem.heapUsed) / (1024 * 1024);
      const peakRssMb = peakMem.rss / (1024 * 1024);

      benchmarks.push({
        pages: pageCount,
        slices: subDocs.length,
        heapDeltaMb: Math.round(heapDeltaMb * 100) / 100,
        peakRssMb: Math.round(peakRssMb * 100) / 100,
      });

      // Memory must remain well below Render Free's 512 MB ceiling (< 250 MB peak RSS)
      expect(peakRssMb).toBeLessThan(250);
      expect(subDocs.length).toBe(Math.ceil(pageCount / segmentSize));
    }

    console.log('PDF Splitting Memory Benchmarks:', JSON.stringify(benchmarks, null, 2));
  });
});

