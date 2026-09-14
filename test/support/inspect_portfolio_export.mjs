// Optional independent QA: reads only synthetic Flutter-test fixtures.
// Run from the repository root after the EXPORT_FIXTURE_DIR test command.
import { readFile, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { getDocument } from '../../backend/node_modules/pdfjs-dist/legacy/build/pdf.mjs';

const directory = new URL('../../.dart_tool/export_qa/', import.meta.url);
const data = new Uint8Array(await readFile(new URL('portfolio.pdf', directory)));
const loading = getDocument({ data, isEvalSupported: false });
const pdf = await loading.promise;
let text = '';
for (let i = 1; i <= pdf.numPages; i++) {
  const page = await pdf.getPage(i);
  text += (await page.getTextContent()).items.map(item => item.str).join(' ') + '\n';
  if (process.argv.includes('--render') && [1, 5].includes(i)) {
    const { createCanvas } = await import('../../backend/node_modules/@napi-rs/canvas/index.js');
    const viewport = page.getViewport({ scale: 1.2 });
    const canvas = createCanvas(Math.ceil(viewport.width), Math.ceil(viewport.height));
    await page.render({ canvasContext: canvas.getContext('2d'), viewport }).promise;
    await writeFile(new URL(`preview-${i}.png`, directory), canvas.toBuffer('image/png'));
  }
}
for (const expected of [
  'ACADEMIC PORTFOLIO', 'Test José Student', '3BSIT-2',
  'Monday 8:00 AM - 10:00 AM', 'Professor Example', 'Mobile Development',
  'IT 301', 'First Semester 2026-2027', 'Creative Title', 'Curriculum Vitae',
  'Scholastic Record', 'Certificates', 'Accomplishments', 'Other Achievements',
  'College Report', 'Stored Training', '2026-09-14', 'Training / Seminar',
  'A saved description', 'My own reflection',
]) assert(text.includes(expected), `Missing public fixture text: ${expected}`);
console.log(`PDF.js: ${pdf.numPages} pages, all title-page and metadata assertions passed.`);
await loading.destroy();
