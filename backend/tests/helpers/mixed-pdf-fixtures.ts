import { PDFDocument, StandardFonts } from 'pdf-lib';
import sharp from 'sharp';

export const certificateText = 'CERTIFICATE OF PARTICIPATION\nAdvanced Software Seminar\nPresented for attending the academic development seminar\nIssued on May 15, 2024 by University Computing Society';
export const cvText = 'CURRICULUM VITAE\nAlex Student - Software Developer\nEducation and professional experience in software engineering\nTechnical skills include databases, mobile apps and testing';
export const cvContinuationText = 'CURRICULUM VITAE\nProfessional experience continued\nDeveloped mobile applications and tested database integrations\nReferences and academic project details are available on request';

/** Synthetic fixtures only: no personal data, network, or checked-in binaries. */
export async function mixedPdf(pages: readonly { text: string; scanned?: boolean; digitalFragment?: string }[]): Promise<Buffer> {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  for (const input of pages) {
    const page = pdf.addPage([600, 400]);
    if (input.scanned) {
      const escape = (value: string) => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
      const svg = `<svg width="1200" height="800" xmlns="http://www.w3.org/2000/svg"><rect width="1200" height="800" fill="white"/>${input.text.split('\n').map((line, i) => `<text x="60" y="${110 + i * 65}" font-family="Arial" font-size="28" fill="black">${escape(line)}</text>`).join('')}</svg>`;
      const png = await sharp(Buffer.from(svg)).png().toBuffer();
      const image = await pdf.embedPng(png);
      page.drawImage(image, { x: 0, y: 0, width: 600, height: 400 });
      if (input.digitalFragment) page.drawText(input.digitalFragment, { x: 30, y: 15, font, size: 10 });
    } else {
      input.text.split('\n').forEach((line, i) => page.drawText(line, { x: 30, y: 350 - i * 35, font, size: 14 }));
    }
  }
  return Buffer.from(await pdf.save());
}
