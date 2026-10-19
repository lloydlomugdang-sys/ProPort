import { describe, expect, it } from 'vitest';
import { PDFDocument, rgb, StandardFonts } from 'pdf-lib';
import sharp from 'sharp';
import { readFile } from 'node:fs/promises';
import { generatePortfolioDocx } from '../../src/modules/portfolios/portfolio-docx.js';
import { officialNeuSealPng, standardTitlePage } from '../../src/modules/portfolios/portfolio-title-page.js';
import { OFFICIAL_COLLEGE_REPORT, OFFICIAL_QUESTIONS } from '../../src/modules/college-report/college-report.template.js';
import type { OfficialReportView } from '../../src/modules/college-report/college-report.service.js';
import { xml } from '../../src/modules/portfolios/docx-package.js';
import { portfolioDocument, PORTFOLIO_TEST_INFO } from '../helpers/portfolio-fixtures.js';
import { docxParts } from '../helpers/docx-parts.js';

const report: OfficialReportView = { questionnaireVersion: 2, updatedAt: new Date().toISOString(),
  essay: 'My saved objectives & reflection.', answers: OFFICIAL_QUESTIONS.map((q) => ({ questionKey: q.key,
    value: q.key === 's01-q01' ? 'often' : q.key === 's09-q01' ? 'My own written answer.' : null })) };

describe('editable evidence portfolio DOCX', () => {
  it('has matching NEU seals, dynamic program, all title details, Letter margins and editable questionnaire wording/answers', async () => {
    const bytes = await generatePortfolioDocx([], PORTFOLIO_TEST_INFO, report, 'BS Information Technology', async () => Buffer.alloc(0));
    const parts = docxParts(bytes), body = parts.get('word/document.xml')!.toString();
    expect(parts.get('word/media/image1.png')).toEqual(await officialNeuSealPng());
    expect(body.match(/r:embed="image1"/g)).toHaveLength(2);
    expect(body.match(/wp:extent cx="762000" cy="762000"/g)).toHaveLength(2);
    expect(body).toContain('NEW ERA UNIVERSITY');
    expect(body).toContain('BS Information Technology');
    expect(body).not.toMatch(/Architecture|metadata outline|ownerId|objectKey|accessToken/);
    expect(body).toContain('<w:bottom w:val="single"');
    for (const field of standardTitlePage(PORTFOLIO_TEST_INFO).filter(Boolean)) expect(body).toContain(xml(field));
    expect(body).toContain('<w:pgSz w:w="12240" w:h="15840"/>');
    expect(body).toContain('w:left="2160"');
    expect(parts.get('word/styles.xml')!.toString()).toContain('Noto Sans');
    const fontTable = parts.get('word/fontTable.xml')!.toString();
    for (const weight of ['Regular', 'Bold']) {
      const key = new RegExp(`<w:embed${weight}[^>]+w:fontKey="\\{([^}]+)\\}"`).exec(fontTable)![1]!;
      const mask = Buffer.from(key.replaceAll('-', ''), 'hex').reverse();
      const data = Buffer.from(parts.get(`word/fonts/${weight.toLowerCase()}.odttf`)!);
      for (let i = 0; i < 32; i++) data[i] = data[i]! ^ mask[i % 16]!;
      expect(data).toEqual(await readFile(new URL(`../../../assets/fonts/NotoSans-${weight}.ttf`, import.meta.url)));
    }
    expect(body).toContain('TABLE OF CONTENTS');
    expect(body).toContain('w:anchor="section0"');
    expect(OFFICIAL_COLLEGE_REPORT.sections).toHaveLength(10);
    expect(OFFICIAL_QUESTIONS).toHaveLength(62);
    let previous = -1;
    for (const s of OFFICIAL_COLLEGE_REPORT.sections) {
      const pos = body.indexOf(xml(`${s.label} ${s.prompt}`));
      expect(pos).toBeGreaterThan(previous); previous = pos;
      for (const q of s.questions) expect(body).toContain(xml(q.text));
      for (const o of s.options) expect(body).toContain(xml(o.label));
    }
    expect(body.match(/<w:tblHeader\/>/g)).toHaveLength(8);
    expect(body.match(/<w:t xml:space="preserve">X<\/w:t>/g)).toHaveLength(1);
    const firstRow = body.split('Asked questions in class')[1]!.split('</w:tr>')[0]!;
    const cells = firstRow.split('</w:tc>');
    expect(cells[1]).not.toContain('>X<'); // Very Often unselected
    expect(cells[2]).toContain('>X<'); // saved Often, aligned to its column
    expect(cells[3]).not.toContain('>X<');
    expect(body.match(/Response: Unanswered/g)).toHaveLength(1); // only written response 10
    expect(body).toContain('My own written answer.');
    expect(body).toContain('My saved objectives &amp; reflection.');
  });

  it('embeds real uploaded images and PDF pages in order, with editable reflections and official section order', async () => {
    const png = await sharp({ create: { width: 100, height: 80, channels: 3, background: 'green' } }).png().toBuffer();
    const pdf = await PDFDocument.create();
    for (const color of [rgb(1, 0, 0), rgb(0, 0, 1)]) {
      pdf.addPage([120, 160]).drawRectangle({ x: 0, y: 0, width: 120, height: 160, color });
    }
    const docs = [
      portfolioDocument({ title: 'Creative Art', folderKey: 'creative-title', objectKey: 'green' }),
      portfolioDocument({ title: 'CV Source', categoryKey: 'curriculum-vitae', folderKey: 'curriculum-vitae', objectKey: 'green' }),
      portfolioDocument({ title: 'TOR Source', categoryKey: 'scholastic-record', folderKey: 'unofficial-tor-with-reflections', objectKey: 'pdf', fileKind: 'pdf', reflection: 'My editable TOR reflection.' }),
      portfolioDocument({ title: 'Certificate Source', objectKey: 'green' }),
      portfolioDocument({ title: 'Accomplishment Source', categoryKey: 'accomplishments', folderKey: 'research', objectKey: 'green' }),
      portfolioDocument({ title: 'Achievement Source', categoryKey: 'other-achievements', folderKey: 'other-achievements', objectKey: 'green' }),
    ];
    const source = Buffer.from(await pdf.save());
    const parts = docxParts(await generatePortfolioDocx(docs.reverse(), PORTFOLIO_TEST_INFO, report, '', async (key) => key === 'pdf' ? source : png));
    const body = parts.get('word/document.xml')!.toString();
    const headings = [...body.matchAll(/<w:pStyle w:val="Heading1"\/>.*?<w:t[^>]*>(.*?)<\/w:t>/gs)].map((m) => m[1]);
    expect(headings).toEqual(['TABLE OF CONTENTS']); // no generic heading-only cover pages
    const order = [...body.matchAll(/<w:hyperlink[^>]+>.*?<w:t>(.*?)<\/w:t>/gs)].map(m => m[1]);
    expect(order).toEqual(['Curriculum Vitae', 'Unofficial TOR - Bachelor&apos;s Degree with Reflection', 'Certificates', 'Accomplishments', 'Other Achievements', 'College Report']);
    expect(body.indexOf('Creative Art')).toBeGreaterThan(body.indexOf('TOR Source, PDF page 2 of 2'));
    expect(body.indexOf('Creative Art')).toBeLessThan(body.indexOf('Certificate Source, image 1'));
    expect(body).toContain('My editable TOR reflection.');
    expect(body.indexOf('TOR Source, PDF page 1 of 2')).toBeLessThan(body.indexOf('TOR Source, PDF page 2 of 2'));
    const media = [...parts].filter(([name]) => name.startsWith('word/media/'));
    expect(media).toHaveLength(8); // seal + five uploaded images + two PDF pages
    const green = await sharp(parts.get('word/media/image2.png')).stats();
    expect(green.channels[1]!.mean).toBeGreaterThan(100);
    expect(green.channels[0]!.mean).toBe(0);
    const red = await sharp(parts.get('word/media/image3.png')).stats();
    const blue = await sharp(parts.get('word/media/image4.png')).stats();
    expect(red.channels[0]!.mean).toBeGreaterThan(250);
    expect(red.channels[2]!.mean).toBeLessThan(1);
    expect(blue.channels[2]!.mean).toBeGreaterThan(250);
    expect(blue.channels[0]!.mean).toBeLessThan(1);
    expect(body).toContain('evidence is embedded as images');
  });

  it('renders visible entered form content instead of silently losing it', async () => {
    const source = await PDFDocument.create();
    const page = source.addPage([300, 200]);
    const field = source.getForm().createTextField('student');
    field.addToPage(page, { x: 20, y: 60, width: 260, height: 50, borderWidth: 0 });
    field.setText('SAVED FORM VALUE');
    source.getForm().updateFieldAppearances(await source.embedFont(StandardFonts.Helvetica));
    const bytes = Buffer.from(await source.save());
    const parts = docxParts(await generatePortfolioDocx([portfolioDocument({ fileKind: 'pdf' })], PORTFOLIO_TEST_INFO, null, '', async () => bytes));
    const pixels = await sharp(parts.get('word/media/image2.png')).removeAlpha().raw().toBuffer();
    expect([...pixels].filter((p) => p < 100).length).toBeGreaterThan(100);
  });

  it('rejects corrupt and unsupported evidence rather than returning a successful partial export', async () => {
    for (const fileKind of ['pdf', 'image', 'docx'] as const) {
      await expect(generatePortfolioDocx([portfolioDocument({ fileKind })], PORTFOLIO_TEST_INFO, null, '',
        async () => Buffer.from('broken evidence'))).rejects.toMatchObject({ statusCode: 422 });
    }
  });
});
