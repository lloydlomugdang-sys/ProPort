import { describe, expect, it } from 'vitest';
import {
  LocalOcrEngine,
  OCR_MAX_IMAGE_PIXELS,
} from '../../src/infrastructure/ocr/local-ocr-engine.js';

describe('local OCR engine', () => {
  const engine = new LocalOcrEngine(10_000);

  it('extracts embedded text from a local PDF without rasterization', async () => {
    const result = await engine.extract({
      contents: pdfFixture('GradPort embedded PDF text'),
      mimeType: 'application/pdf',
      fileKind: 'pdf',
    });

    expect(result.engine).toBe('pdfjs');
    expect(result.rawText).toContain('GradPort embedded PDF text');
  });

  it('reports an empty image-only PDF through the explicit scanned-PDF limitation', async () => {
    await expect(
      engine.extract({
        contents: pdfFixture(),
        mimeType: 'application/pdf',
        fileKind: 'pdf',
      }),
    ).rejects.toMatchObject({ reason: 'scanned-pdf-not-supported' });
  });

  it('rejects malformed PDFs and images with bounded safe errors', async () => {
    await expect(
      engine.extract({
        contents: Buffer.from('%PDF-not-valid'),
        mimeType: 'application/pdf',
        fileKind: 'pdf',
      }),
    ).rejects.toMatchObject({ reason: 'invalid-pdf' });

    await expect(
      engine.extract({
        contents: Buffer.from([0xff, 0xd8, 0xff]),
        mimeType: 'image/jpeg',
        fileKind: 'image',
      }),
    ).rejects.toMatchObject({ reason: 'invalid-image' });
  });

  it('rejects decompression-bomb-sized image dimensions before OCR starts', async () => {
    const pngHeader = Buffer.alloc(24);
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).copy(pngHeader);
    const width = Math.floor(Math.sqrt(OCR_MAX_IMAGE_PIXELS)) + 1;
    pngHeader.writeUInt32BE(width, 16);
    pngHeader.writeUInt32BE(width, 20);

    await expect(
      engine.extract({
        contents: pngHeader,
        mimeType: 'image/png',
        fileKind: 'image',
      }),
    ).rejects.toMatchObject({ reason: 'image-too-large' });
  });
});

function pdfFixture(text?: string): Buffer {
  const escaped = text?.replaceAll('\\', '\\\\').replaceAll('(', '\\(').replaceAll(')', '\\)');
  const content = escaped === undefined ? '' : `BT /F1 12 Tf 72 720 Td (${escaped}) Tj ET`;
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    `<< /Length ${Buffer.byteLength(content)} >>\nstream\n${content}\nendstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  let body = '%PDF-1.4\n';
  const offsets = [0];
  for (const [index, object] of objects.entries()) {
    offsets.push(Buffer.byteLength(body));
    body += `${index + 1} 0 obj\n${object}\nendobj\n`;
  }
  const xrefOffset = Buffer.byteLength(body);
  body += `xref\n0 ${objects.length + 1}\n`;
  body += '0000000000 65535 f \n';
  for (const offset of offsets.slice(1)) {
    body += `${offset.toString().padStart(10, '0')} 00000 n \n`;
  }
  body += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n`;
  body += `startxref\n${xrefOffset}\n%%EOF\n`;
  return Buffer.from(body, 'ascii');
}
