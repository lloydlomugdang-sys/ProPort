import { PDFDocument, PDFName, PDFString, StandardFonts, degrees } from 'pdf-lib';
import { getDocument, OPS, Util } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import sharp from 'sharp';
import { describe, expect, it, vi } from 'vitest';
import { PortfolioGeneratorService, planPortfolioSections } from '../../src/modules/portfolios/portfolio-generator.service.js';
import {
  PORTFOLIO_LAYOUT, fitPortfolioArtifact, wrapPortfolioText,
} from '../../src/modules/portfolios/portfolio-layout.js';
import { portfolioDocument as doc, portfolioMemoryStorage, PORTFOLIO_TEST_INFO as info } from '../helpers/portfolio-fixtures.js';
import type { DocumentRecord } from '../../src/database/repositories/document.repository.js';
import { PROFILE_OPTIONS } from '../../src/modules/users/profile-options.js';

async function inspect(bytes: Buffer) {
  const task = getDocument({ data: new Uint8Array(bytes), useSystemFonts: true });
  try {
    const pdf = await task.promise;
    const pages = [];
    for (let n = 1; n <= pdf.numPages; n++) {
      const page = await pdf.getPage(n);
      const items = (await page.getTextContent()).items.filter((item) => 'str' in item);
      const ops = await page.getOperatorList();
      pages.push({ text: items.map((item) => item.str).join(' '), items, view: page.view,
        images: ops.fnArray.filter(op => op === OPS.paintImageXObject).length });
    }
    return pages;
  } finally { await task.destroy(); }
}

async function png(width = 400, height = 700) {
  return sharp({ create: { width, height, channels: 3, background: '#dae5ef' } }).png().toBuffer();
}

async function generate(documents: DocumentRecord[]) {
  return new PortfolioGeneratorService(undefined, portfolioMemoryStorage(new Map([
    ['test/image.png', await png()],
  ]))).generateFromDocuments(documents, info);
}

function tocTarget(pages: Awaited<ReturnType<typeof inspect>>, prefix: string) {
  for (const page of pages.filter((page) => page.text.includes('TABLE OF CONTENTS'))) {
    const item = page.items.find((item) => item.str.startsWith(prefix));
    if (!item) continue;
    const number = page.items.find((value) => /^\d+$/.test(value.str) &&
      value.transform[4] > 500 && Math.abs(value.transform[5] - item.transform[5]) < 0.01);
    if (number) return Number(number.str);
  }
  throw new Error(`Missing TOC target: ${prefix}`);
}

describe('official Phase B portfolio formatting', () => {
  it('renders the identical official seal twice, a centered profile header and solid black divider inside Letter margins', async () => {
    const asset = await readFile(new URL('../../../assets/images/neu_seal.webp', import.meta.url));
    expect(createHash('sha256').update(asset).digest('hex')).toBe('e3606fcd9814af99d29187bb60fd8a2d4b00e99a724eee0867cad9022554406d');
    const source = await sharp(asset).metadata();
    const bytes = await new PortfolioGeneratorService(undefined, portfolioMemoryStorage())
      .generateFromDocuments([], info, null, PROFILE_OPTIONS.programs[0]!);
    const pages = await inspect(bytes);
    const first = pages[0]!;
    expect(first.view).toEqual([0, 0, 612, 792]);
    const university = first.items.find((item) => item.str === 'NEW ERA UNIVERSITY')!;
    expect(university).toBeDefined();
    expect(university.transform[4] + university.width / 2).toBeCloseTo(306, 1);
    const task = getDocument({ data: new Uint8Array(bytes), useSystemFonts: true });
    try {
      const pdf = await task.promise;
      const page = await pdf.getPage(1);
      const operators = await page.getOperatorList();
      let matrix = [1, 0, 0, 1, 0, 0];
      const stack: number[][] = [];
      const images: { id: string; matrix: number[]; width: number; height: number }[] = [];
      let strokeColor: string | undefined;
      let strokeWidth: number | undefined;
      let divider: number[] | undefined;
      for (const [i, op] of operators.fnArray.entries()) {
        const args = operators.argsArray[i];
        if (op === OPS.save) stack.push([...matrix]);
        if (op === OPS.restore) matrix = stack.pop()!;
        if (op === OPS.transform) matrix = Util.transform(matrix, args);
        if (op === OPS.paintImageXObject) images.push({ id: args[0], matrix: [...matrix], width: args[1], height: args[2] });
        if (op === OPS.setStrokeRGBColor) strokeColor = args[0];
        if (op === OPS.setLineWidth) strokeWidth = args[0];
        if (op === OPS.constructPath && args[0] === OPS.stroke) {
          expect(strokeColor).toBe('#000000');
          expect(strokeWidth).toBe(2);
          divider = Array.from(args[2] as Float32Array);
        }
      }
      expect(images).toHaveLength(2);
      expect(images[0]!.id).toBe(images[1]!.id); // One embedded asset, painted twice.
      for (const image of images) {
        expect(image.width).toBe(source.width);
        expect(image.height).toBe(source.height);
        expect(image.matrix.slice(0, 4)).toEqual([60, 0, 0, 60]);
        expect(image.matrix[4]).toBeGreaterThanOrEqual(108);
        expect(image.matrix[4]! + 60).toBeLessThanOrEqual(540);
        expect(image.matrix[5]).toBeGreaterThanOrEqual(72);
        expect(image.matrix[5]! + 60).toBeLessThanOrEqual(720);
      }
      expect(images[0]!.matrix[5]).toBe(images[1]!.matrix[5]);
      expect((images[0]!.matrix[4]! + images[1]!.matrix[4]! + 60) / 2).toBe(306);
      expect(divider).toEqual([108, 630, 504, 630]);
      const title = first.items.find((item) => item.str === 'ACADEMIC PORTFOLIO')!;
      expect(title.transform[5] + title.height).toBeLessThan(630);
      for (const value of Object.values(info)) {
        expect(first.text).toContain(value);
        const field = first.items.find((item) => item.str === value)!;
        expect(field.transform[5] + field.height).toBeLessThan(630);
      }
      for (const item of first.items.filter((item) => item.str.trim())) {
        expect(item.transform[4]).toBeGreaterThanOrEqual(108);
        expect(item.transform[4] + item.width).toBeLessThanOrEqual(504.01);
      }
    } finally { await task.destroy(); }
  });

  it.each([...PROFILE_OPTIONS.programs, '', 'A long stored program '.repeat(9).trim()])('uses only dynamic profile program text (%s)', async (program) => {
    const bytes = await new PortfolioGeneratorService(undefined, portfolioMemoryStorage())
      .generateFromDocuments([], info, null, program);
    const pages = await inspect(bytes);
    const first = pages[0]!;
    expect(first.text).toContain('NEW ERA UNIVERSITY');
    if (program) expect(first.text).toContain(program);
    else expect(first.text).not.toMatch(/Bachelor|Program description/);
    expect(pages.map((page) => page.text).join(' ')).not.toMatch(/Architecture|College of Engineering|Volume no\.|THESIS TITLE/);
    const heading = first.items.find((item) => item.str === 'ACADEMIC PORTFOLIO')!;
    const headerItems = first.items.filter((item) => item.transform[5] > heading.transform[5] && item.str.trim());
    for (const item of headerItems) {
      expect(item.transform[4] + item.width / 2).toBeCloseTo(306, 1);
      expect(item.transform[4]).toBeGreaterThanOrEqual(180);
      expect(item.transform[4] + item.width).toBeLessThanOrEqual(432.01);
    }
    for (const value of Object.values(info)) expect(pages.map((page) => page.text).join(' ')).toContain(value);
  });

  it('measures actual glyph advances so kerning pairs cannot overflow the right margin', async () => {
    const pages = await inspect(await generate([doc({ title: 'AV'.repeat(90) })]));
    for (const page of pages) for (const item of page.items.filter((item) => item.str.trim())) {
      expect(item.transform[4] + item.width).toBeLessThanOrEqual(540.01);
    }
  });

  it('keeps a reflection heading with the first reflection line across metadata page breaks', async () => {
    const pages = await inspect(await generate([doc({
      description: Array.from({ length: 22 }, (_, n) => `Description line ${n}`).join('\n'),
      reflection: 'The first reflection line belongs with its heading.',
    })]));
    const reflectionPage = pages.find((page) => page.text.includes('Student Reflection'))!;
    expect(reflectionPage.text).toContain('The first reflection line');
  });

  it('uses seeded section order, with the saved Creative Title inside its own section after TOC', async () => {
    const pairs = [
      ['college-report', 'college-report'], ['other-achievements', 'projects'],
      ['accomplishments', 'assessments'], ['accomplishments', 'projects'],
      ['accomplishments', 'case-studies'], ['accomplishments', 'thesis-capstone'],
      ['certificates', 'trainings'], ['certificates', 'other-seminars'], ['certificates', 'seminars'],
      ['scholastic-record', 'unofficial-tor-with-reflections'], ['curriculum-vitae', 'curriculum-vitae'],
      ['certificates', 'creative-title'],
    ];
    const documents = pairs.map(([categoryKey, folderKey]) => doc({
      categoryKey: categoryKey!, folderKey: folderKey!, title: `Evidence ${folderKey}`,
      ...(categoryKey === 'scholastic-record' ? { reflection: 'My actual PO and PEO reflection.' } : {}),
    }));
    const sections = planPortfolioSections(documents);
    expect(sections.map((s) => s.key)).toEqual([
      'curriculum-vitae', 'scholastic-record', 'certificates',
      'accomplishments', 'other-achievements', 'college-report',
    ]);
    expect(sections.find((s) => s.key === 'certificates')!.subsections.map((s) => s.key))
      .toEqual(['creative-title', 'seminars', 'other-seminars', 'trainings']);
    expect(sections.find((s) => s.key === 'accomplishments')!.subsections.map((s) => s.key))
      .toEqual(['thesis-capstone', 'case-studies', 'projects', 'assessments']);
    const pages = await inspect(await generate(documents));
    expect(pages[0]!.text).toContain('Standard Title');
    expect(pages[0]!.text).toContain('NEW ERA UNIVERSITY');
    expect(pages[0]!.text).not.toMatch(/verified via|College of Informatics|Architecture/);
    expect(pages[1]!.text).toContain('TABLE OF CONTENTS');
    expect(pages.filter(p => p.images === 1)).toHaveLength(documents.length);
    expect(pages.at(-1)!.images).toBe(1);
    expect(pages.find((p) => p.text.includes('My actual PO'))!.text).toContain('Student Reflection');
    for (const section of sections) {
      const target = tocTarget(pages, section.name);
      expect(pages[target - 1]!.images).toBe(1);
    }
    for (const folder of ['seminars', 'other-seminars', 'trainings', 'thesis-capstone', 'case-studies', 'projects', 'assessments']) {
      const target = tocTarget(pages, `Evidence ${folder}`);
      expect(pages[target - 1]!.images).toBe(1);
    }
  });

  it('renders Letter, exact margins, 12pt normal text, and 24pt baselines through an injected font loader', async () => {
    const loader = vi.fn(async (pdf: PDFDocument) => ({
      regular: await pdf.embedFont(StandardFonts.Courier),
      bold: await pdf.embedFont(StandardFonts.CourierBold),
    }));
    const bytes = await new PortfolioGeneratorService(undefined, portfolioMemoryStorage(), loader)
      .generateFromDocuments([], { ...info, fullName: 'A very long name '.repeat(12) });
    expect(loader).toHaveBeenCalledTimes(1);
    const pages = await inspect(bytes);
    const parsed = await PDFDocument.load(bytes);
    expect(parsed.getPages().every((page) => page.getWidth() === 612 && page.getHeight() === 792)).toBe(true);
    expect(PORTFOLIO_LAYOUT).toEqual({ width: 612, height: 792, left: 108, top: 72, right: 72, bottom: 72, bodySize: 12, lineHeight: 24 });
    for (const page of pages) {
      for (const item of page.items.filter((item) => item.str.trim())) {
        expect(item.transform[4]).toBeGreaterThanOrEqual(108);
        expect(item.transform[4] + item.width).toBeLessThanOrEqual(540.01);
        expect(item.transform[5]).toBeGreaterThanOrEqual(72);
        expect(item.transform[5] + item.height).toBeLessThanOrEqual(720.01);
        expect(item.height).toBeCloseTo(12);
      }
    }
    const title = pages[0]!.items.filter((i) => i.str.trim());
    title.splice(0, title.findIndex((item) => item.str === 'ACADEMIC PORTFOLIO'));
    expect(title[0]!.transform[5] - title[1]!.transform[5]).toBe(24);
    const fontNames = parsed.context.enumerateIndirectObjects().map(([, object]) => object.toString()).join(' ');
    expect(fontNames).toContain('/Courier');
    expect(fontNames).not.toContain('/Helvetica');
  });

  it('paginates complete image descriptions/reflections and updates every affected TOC number', async () => {
    const reflection = Array.from({ length: 65 }, (_, n) => `Student paragraph ${n}: actual reflection.`).join('\n');
    const pages = await inspect(await generate([
      doc({ title: 'Long student reflection', description: 'Description '.repeat(50), descriptionSource: 'user', reflection }),
      doc({ categoryKey: 'college-report', folderKey: 'college-report', title: 'Final report evidence' }),
    ]));
    const content = pages.filter((p) => !p.text.includes('TABLE OF CONTENTS')).map((p) => p.text).join(' ');
    for (let n = 0; n < 65; n++) expect(content).toContain(`Student paragraph ${n}: actual reflection.`);
    expect(pages.length).toBeGreaterThan(5);
    expect(pages[tocTarget(pages, 'Final report evidence') - 1]!.images).toBe(1);
    expect(pages.every((page) => page.items.every((i) => !i.str.trim() || i.transform[5] >= 72))).toBe(true);
  });

  it('wraps long TOC titles across multiple TOC pages without truncation or wrong targets', async () => {
    const documents = Array.from({ length: 20 }, (_, i) => doc({
      title: `Entry${String(i).padStart(2, '0')} ${'Actual long document title '.repeat(4)} END${i}`,
    }));
    const pages = await inspect(await generate(documents));
    expect(pages.filter((p) => p.text.includes('TABLE OF CONTENTS')).length).toBeGreaterThan(1);
    for (let i = 0; i < 20; i++) {
      const prefix = `Entry${String(i).padStart(2, '0')}`;
      expect(pages[tocTarget(pages, prefix) - 1]!.images).toBe(1);
      expect(tocTarget(pages, prefix)).toBe(tocTarget(pages, 'Entry00') + i);
      expect(pages.map((p) => p.text).join(' ')).toContain(`END${i}`);
    }
    for (const page of pages) for (const item of page.items) {
      expect(item.transform[4] + item.width).toBeLessThanOrEqual(540.01);
    }
  });

  it('fits portrait/landscape/rotated vector PDFs to Letter without cropping or distortion', async () => {
    const source = await PDFDocument.create();
    for (const [width, height, rotation] of [[595, 842, 0], [1000, 600, 0], [600, 1000, 90], [600, 1000, 270], [600, 1000, 180]]) {
      const page = source.addPage([width!, height!]);
      page.setRotation(degrees(rotation!));
      for (const [x, y, label] of [[2, 12, 'LOWERLEFT'], [width! - 80, height! - 14, 'UPPERRIGHT']] as const) {
        page.drawText(label, { x, y, size: 10 });
      }
    }
    const bytes = await new PortfolioGeneratorService(undefined, portfolioMemoryStorage(new Map([
      ['source', Buffer.from(await source.save())],
    ]))).generateFromDocuments([doc({ objectKey: 'source', fileKind: 'pdf' })], info);
    const parsed = await PDFDocument.load(bytes);
    const pages = await inspect(bytes);
    expect(parsed.getPages().slice(-5).map((p) => p.getSize())).toEqual([
      { width: 612, height: 792 }, { width: 792, height: 612 },
      { width: 792, height: 612 }, { width: 792, height: 612 }, { width: 612, height: 792 },
    ]);
    for (const page of pages.slice(-5)) {
      expect(page.text).toContain('LOWERLEFT');
      expect(page.text).toContain('UPPERRIGHT');
      for (const item of page.items.filter((i) => i.str.trim())) {
        expect(item.transform[4]).toBeGreaterThanOrEqual(108);
        expect(item.transform[4]).toBeLessThanOrEqual(page.view[2]! - 72);
        expect(item.transform[5]).toBeGreaterThanOrEqual(72);
        expect(item.transform[5]).toBeLessThanOrEqual(page.view[3]! - 72);
      }
    }
  });

  it('fits images and PDFs proportionally inside all four official margins', () => {
    for (const [w, h, pageW, pageH] of [[800, 1200, 612, 792], [1200, 800, 792, 612], [400, 900, 612, 792]]) {
      const fit = fitPortfolioArtifact(w!, h!, pageW!, pageH!);
      expect(fit.width / fit.height).toBeCloseTo(w! / h!);
      expect(fit.x).toBeGreaterThanOrEqual(108);
      expect(fit.y).toBeGreaterThanOrEqual(72);
      expect(fit.x + fit.width).toBeLessThanOrEqual(pageW! - 72);
      expect(fit.y + fit.height).toBeLessThanOrEqual(pageH! - 72);
    }
  });

  it('places the original image before prose, reserving print margins and footer space', async () => {
    const bytes = await generate([doc({ description: 'Actual description', reflection: 'Actual reflection' })]);
    const task = getDocument({ data: new Uint8Array(bytes), useSystemFonts: true });
    try {
      const pdf = await task.promise;
      const page = await pdf.getPage(3);
      const operators = await page.getOperatorList();
      const imageIndex = operators.fnArray.indexOf(OPS.paintImageXObject);
      expect(imageIndex).toBeGreaterThan(0);
      const transforms = operators.fnArray.slice(0, imageIndex).flatMap((op, index) =>
        op === OPS.transform ? [operators.argsArray[index] as number[]] : []);
      const translation = transforms.find((values) => values[4] !== 0 || values[5] !== 0)!;
      const scaling = transforms.find((values) => values[0]! > 1 || values[3]! > 1)!;
      const x = translation[4]!;
      const y = translation[5]!;
      const width = scaling[0]!;
      const height = scaling[3]!;
      expect(width / height).toBeCloseTo(400 / 700);
      expect(x).toBeGreaterThanOrEqual(108);
      expect(x + width).toBeLessThanOrEqual(540);
      expect(y).toBeGreaterThanOrEqual(108);
      expect(y + height).toBeLessThanOrEqual(720);
    } finally { await task.destroy(); }
  });

  it('paginates reflection after intact source pages and honors source CropBox offsets', async () => {
    const source = await PDFDocument.create();
    const page = source.addPage([800, 1000]);
    page.setCropBox(100, 100, 600, 800);
    page.drawText('VISIBLE SOURCE CONTENT', { x: 110, y: 860, size: 12 });
    const bytes = await new PortfolioGeneratorService(undefined, portfolioMemoryStorage(new Map([
      ['source', Buffer.from(await source.save())],
    ]))).generateFromDocuments([doc({
      objectKey: 'source', fileKind: 'pdf', title: 'Original PDF with reflection',
      reflection: Array.from({ length: 60 }, (_, n) => `Reflection line ${n}`).join('\n'),
    })], info);
    const pages = await inspect(bytes);
    expect(pages).toHaveLength(6);
    expect(pages[2]!.text).toContain('VISIBLE SOURCE CONTENT');
    expect(pages.at(-1)!.text).toContain('Reflection line 59');
    const sourceText = pages[2]!.items.find((i) => i.str.includes('VISIBLE SOURCE'))!;
    expect(sourceText.transform[4]).toBeCloseTo(108 + 10 * 0.72);
    expect(sourceText.height).toBeCloseTo(12 * 0.72);
  });

  it('omits absent sections and never invents reflections or institutional information', async () => {
    const pages = await inspect(await generate([]));
    expect(pages).toHaveLength(2);
    expect(pages.map((p) => p.text).join(' ')).not.toMatch(/Student Reflection|Curriculum Vitae|University|Student ID/);
    const single = await inspect(await generate([doc()]));
    expect(single.map((p) => p.text).join(' ')).not.toMatch(/College Report|Student Reflection/);
  });

  it('rejects unknown categories without remapping them to Creative Title or mutating the original', async () => {
    const original = doc({ categoryKey: 'unknown', folderKey: 'creative-title' });
    await expect(generate([original])).rejects.toMatchObject({ code: 'PORTFOLIO_CATEGORY_UNSUPPORTED', statusCode: 422 });
    expect(original.categoryKey).toBe('unknown');
    expect(planPortfolioSections([doc({ folderKey: 'legacy-certificate' })])[0]!.subsections[0]!.name).toBe('Legacy Certificate');
  });

  it('flattens supported form fields on the export copy, preserves visible answers and leaves the original intact', async () => {
    const source = await PDFDocument.create();
    const page = source.addPage();
    const field = source.getForm().createTextField('student-answer');
    field.addToPage(page);
    field.setText('An actual entered student answer');
    const original = Buffer.from(await source.save());
    const files = new Map([['form', original]]);
    const generator = new PortfolioGeneratorService(undefined, portfolioMemoryStorage(files));
    const pages = await inspect(await generator.generateFromDocuments([doc({ objectKey: 'form', fileKind: 'pdf' })], info));
    expect(pages.at(-1)!.text).toContain('An actual entered student answer');
    expect(files.get('form')).toEqual(original);
    expect((await PDFDocument.load(original)).getForm().getFields()).toHaveLength(1);
  });

  it('puts one saved creative artifact directly before section evidence and rejects ambiguous covers', async () => {
    const pages = await inspect(await generate([
      doc({ folderKey: 'creative-title', title: 'Learning through practice' }),
      doc({ title: 'Certificate evidence' }),
    ]));
    expect(pages).toHaveLength(4);
    expect(pages[1]!.text).toContain('TABLE OF CONTENTS');
    expect(tocTarget(pages, 'Learning through practice')).toBe(3);
    expect(tocTarget(pages, 'Certificate evidence')).toBe(4);
    expect(pages.slice(2).map(p => p.images)).toEqual([1, 1]);
    expect(pages.map((page) => page.text).join(' ')).not.toContain('No stored documents');
    await expect(generate([doc({ folderKey: 'creative-title' }), doc({ folderKey: 'creative-title' })]))
      .rejects.toMatchObject({ code: 'PORTFOLIO_CREATIVE_TITLE_AMBIGUOUS' });
  });

  it.each(['annotation', 'xfa'])('fails actionably for unsupported %s without altering uploaded bytes', async (kind) => {
    const source = await PDFDocument.create();
    const page = source.addPage();
    page.drawText('Original evidence stays intact');
    if (kind === 'xfa') {
      source.getForm().acroForm.dict.set(PDFName.of('XFA'), PDFString.of('unsupported form fixture'));
    } else {
      const annotation = source.context.obj({ Type: 'Annot', Subtype: 'Text', Rect: [20, 20, 60, 60], Contents: 'Visible annotation' });
      page.node.set(PDFName.of('Annots'), source.context.obj([source.context.register(annotation)]));
    }
    const original = Buffer.from(await source.save());
    const files = new Map([['unsupported.pdf', original]]);
    const generator = new PortfolioGeneratorService(undefined, portfolioMemoryStorage(files));
    await expect(generator.generateFromDocuments([doc({ objectKey: 'unsupported.pdf', fileKind: 'pdf' })], info))
      .rejects.toMatchObject({ code: 'PORTFOLIO_ARTIFACT_UNSUPPORTED', statusCode: 422, message: expect.stringContaining('print to PDF') });
    expect(files.get('unsupported.pdf')).toEqual(original);
  });

  it('fails explicitly for unsupported font characters instead of losing user text', async () => {
    await expect(generate([doc({ reflection: 'Preserve this: 漢字' })])).rejects.toMatchObject({ code: 'PORTFOLIO_FONT_UNSUPPORTED' });
  });

  it('wraps unbroken words and preserves paragraph boundaries', async () => {
    const pdf = await PDFDocument.create();
    const font = await pdf.embedFont(StandardFonts.Helvetica);
    const lines = wrapPortfolioText(`${'A'.repeat(300)}\n\nEND`, font);
    expect(lines.join('')).toBe(`${'A'.repeat(300)}END`);
    expect(lines).toContain('');
    expect(lines.every((line) => font.widthOfTextAtSize(line, 12) <= 432)).toBe(true);
  });

  it('enforces output pages including wrapped metadata and TOC, with an actionable failure', async () => {
    await expect(generate(Array.from({ length: 149 }, () => doc())))
      .rejects.toMatchObject({ code: 'PORTFOLIO_TOO_LARGE', message: expect.stringContaining('150 pages') });
  });
});
