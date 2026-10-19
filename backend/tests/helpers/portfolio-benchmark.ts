/** Repeatable local-only export benchmark. No database, network, or user data.
 * Run: node --import tsx tests/helpers/portfolio-benchmark.ts
 * Optional QA renders: --output .local-data/qa-consolidation/after
 */
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { performance } from 'node:perf_hooks';
import { PDFDocument, StandardFonts, rgb } from 'pdf-lib';
import sharp from 'sharp';
import { PortfolioGeneratorService } from '../../src/modules/portfolios/portfolio-generator.service.js';
import { generatePortfolioDocx } from '../../src/modules/portfolios/portfolio-docx.js';
import { loadPortfolioFallbackFonts } from '../../src/modules/portfolios/portfolio-layout.js';
import { OFFICIAL_QUESTIONS } from '../../src/modules/college-report/college-report.template.js';
import { PORTFOLIO_TEST_INFO, portfolioDocument, portfolioMemoryStorage } from './portfolio-fixtures.js';

const files = new Map<string, Buffer>();
for (const [key, count] of [['cv', 2], ['project', 8]] as const) {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  for (let n = 1; n <= count; n++) {
    const page = pdf.addPage([612, 792]);
    page.drawRectangle({ x: 20, y: 20, width: 572, height: 752, borderColor: rgb(0, .3, .5) });
    for (let row = 0; row < 25; row++) page.drawText(`${key} original evidence page ${n} / row ${row}`, { x: 40, y: 740 - row * 25, font, size: 12 });
  }
  files.set(key, Buffer.from(await pdf.save()));
}
files.set('image', await sharp({ create: { width: 1600, height: 1100, channels: 3, background: '#226688' } }).png().toBuffer());
const documents = [
  portfolioDocument({ categoryKey: 'curriculum-vitae', folderKey: 'curriculum-vitae', title: 'CV', objectKey: 'cv', fileKind: 'pdf', description: 'Automatic CV summary' }),
  portfolioDocument({ title: 'Certificate', objectKey: 'image', description: 'Automatic certificate summary' }),
  portfolioDocument({ categoryKey: 'accomplishments', folderKey: 'projects', title: 'Project', objectKey: 'project', fileKind: 'pdf', description: 'Automatic project summary' }),
];
const report = { questionnaireVersion: 2, updatedAt: new Date(0).toISOString(), essay: 'My saved objectives.', answers: OFFICIAL_QUESTIONS.map(q => ({ questionKey: q.key, value: q.section.responseType === 'text' ? 'My written response.' : q.section.options[1]!.value })) };
const output = process.argv.indexOf('--output');
for (const format of ['pdf', 'docx'] as const) {
  const times: number[] = [];
  for (let run = 0; run < 3; run++) {
    const stages: Record<string, number> = {};
    const observe = (stage: string, ms: number) => { stages[stage] = (stages[stage] ?? 0) + ms; };
    let fontMs = 0, reads = 0;
    const storage = portfolioMemoryStorage(files), get = storage.get.bind(storage);
    storage.get = async key => { reads++; return get(key); };
    const generator = new PortfolioGeneratorService(undefined, storage, async pdf => {
      const at = performance.now(); const fonts = await loadPortfolioFallbackFonts(pdf); fontMs += performance.now() - at; return fonts;
    }, observe);
    const start = performance.now();
    const bytes = format === 'pdf' ? await generator.generateFromDocuments(documents, PORTFOLIO_TEST_INFO, report, 'Bachelor of Science in Information Technology') :
      await generatePortfolioDocx(documents, PORTFOLIO_TEST_INFO, report, 'Bachelor of Science in Information Technology', async key => { reads++; return files.get(key)!; }, observe);
    const ms = performance.now() - start; times.push(ms);
    console.log(JSON.stringify({ format, run, ms: Math.round(ms), fontMs: Math.round(fontMs), storageReads: reads, outputBytes: bytes.length,
      peakRssMiB: Math.round(process.resourceUsage().maxRSS / 1024), stagesMs: Object.fromEntries(Object.entries(stages).map(([k,v])=>[k,Math.round(v)])) }));
    if (output >= 0 && run === 2) { const dir = process.argv[output + 1]!; await mkdir(dir, { recursive: true }); await writeFile(join(dir, `synthetic.${format}`), bytes); }
  }
  console.log(JSON.stringify({ format, medianMs: Math.round(times.sort((a,b)=>a-b)[1]!), workload: '2-page CV + 8-page project + 1600x1100 image + all 62 saved responses; memory storage' }));
}
