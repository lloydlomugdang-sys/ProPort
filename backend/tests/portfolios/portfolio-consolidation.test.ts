import { describe, expect, it } from 'vitest';
import sharp from 'sharp';
import { PDFDocument } from 'pdf-lib';
import { getDocument, OPS } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { PortfolioGeneratorService } from '../../src/modules/portfolios/portfolio-generator.service.js';
import { generatePortfolioDocx } from '../../src/modules/portfolios/portfolio-docx.js';
import { descriptionSource } from '../../src/modules/documents/description-source.js';
import { portfolioDocument as doc, portfolioMemoryStorage, PORTFOLIO_TEST_INFO as info } from '../helpers/portfolio-fixtures.js';
import { docxParts } from '../helpers/docx-parts.js';

async function pdfPages(bytes: Buffer) {
  const task = getDocument({ data: new Uint8Array(bytes), verbosity: 0 });
  try {
    const pdf = await task.promise, pages = [];
    for (let i = 1; i <= pdf.numPages; i++) {
      const page = await pdf.getPage(i), ops = await page.getOperatorList();
      pages.push({ text: (await page.getTextContent()).items.filter(x=>'str' in x).map(x=>x.str).join(' '),
        images: ops.fnArray.filter(x=>x===OPS.paintImageXObject).length });
    }
    return pages;
  } finally { await task.destroy(); }
}

describe('portfolio consolidation and bounded processing', () => {
  it('exports only explicitly user/confirmed descriptions; preserves every reflection including legacy', async () => {
    const image = await sharp({ create: { width: 60, height: 80, channels: 3, background: 'green' } }).png().toBuffer();
    const sources = [undefined, 'unknown', 'suggested', 'user', 'confirmed'] as const;
    const documents = sources.map((source,i)=>doc({ objectKey: `image${i}`, title: `Evidence ${i}`,
      description: `PROSE_${i}_END`, reflection: `REFLECTION_${i}_END`, ...(source ? {descriptionSource:source}:{}),
      documentDate: new Date(2026,0,i+1) }));
    const storage = portfolioMemoryStorage(new Map(documents.map(d=>[d.objectKey,image])));
    const pdf = await pdfPages(await new PortfolioGeneratorService(undefined,storage).generateFromDocuments(documents,info));
    const parts = docxParts(await generatePortfolioDocx(documents,info,null,'',async()=>image));
    const word = parts.get('word/document.xml')!.toString();
    for (const text of [pdf.map(p=>p.text).join(' '), word]) {
      for(let i=0;i<5;i++) {
        if(i<3) expect(text).not.toContain(`PROSE_${i}_END`); else expect(text).toContain(`PROSE_${i}_END`);
        expect(text).toContain(`REFLECTION_${i}_END`);
      }
    }
    expect(pdf[2]!.images).toBe(1); // evidence before description/reflection, not generic cover
    expect(pdf[3]!.text).toContain('REFLECTION_0_END');
    expect([...parts.keys()].filter(k=>k.startsWith('word/media/'))).toHaveLength(6);
    expect(descriptionSource(undefined)).toBe('unknown');
    expect(()=>descriptionSource('guessed')).toThrow();
  });

  it('loads effective attachments only once, sequentially, and preserves page order without a metadata page', async () => {
    const files = new Map<string,Buffer>();
    for(const name of ['ONE','TWO']) {
      const pdf=await PDFDocument.create(); pdf.addPage().drawText(`ORIGINAL_${name}`,{x:50,y:700}); files.set(name,Buffer.from(await pdf.save()));
    }
    const records = ['ONE','TWO'].map((key,i)=>doc({ categoryKey:'curriculum-vitae',folderKey:'curriculum-vitae',objectKey:key,fileKind:'pdf',
      title:`CV ${i}`, description:'Automatic summary',descriptionSource:'suggested',documentDate:new Date(2026,0,i+1) }));
    const storage = portfolioMemoryStorage(files), originalGet=storage.get.bind(storage);
    let active=0,peak=0; const reads:string[]=[]; const stages: string[]=[];
    storage.get=async key=> {active++;peak=Math.max(peak,active);reads.push(key);await Promise.resolve();active--;return originalGet(key);};
    const generator = new PortfolioGeneratorService(undefined,storage,undefined,stage=>stages.push(stage));
    const pdf=await pdfPages(await generator.generateFromDocuments(records,info));
    expect(pdf).toHaveLength(4); expect(pdf[2]!.text).toContain('ORIGINAL_ONE'); expect(pdf[3]!.text).toContain('ORIGINAL_TWO');
    expect(reads).toEqual(['ONE','TWO']); expect(peak).toBe(1); expect(stages).toContain('pdf-save');
    reads.length=0;
    const parts=docxParts(await generatePortfolioDocx(records,info,null,'',async key=>{reads.push(key);return files.get(key)!;},stage=>stages.push(stage)));
    expect(reads).toEqual(['ONE','TWO']); expect(stages.filter(s=>s==='pdf-raster')).toHaveLength(2);
    const body=parts.get('word/document.xml')!.toString();
    expect(body.indexOf('CV 0, PDF page 1 of 1')).toBeLessThan(body.indexOf('CV 1, PDF page 1 of 1'));
    expect(body.match(/w:type="page"/g)).toHaveLength(3); // TOC + two evidence pages only
  });

  it('keeps all seven DOCX fields in compact indivisible label/value blocks before the first explicit break', async () => {
    const fields={...info,semesterAndYear:'2nd Semester, A.Y. 2026-2027'};
    const parts=docxParts(await generatePortfolioDocx([],fields,null,'Bachelor of Science in Information Technology',async()=>Buffer.alloc(0)));
    const body=parts.get('word/document.xml')!.toString(); const cover=body.split('w:type="page"')[0]!;
    expect(cover).toContain('Semester &amp; Academic Year'); expect(cover).toContain(fields.semesterAndYear);
    expect(cover.match(/w:pStyle w:val="TitleField"/g)).toHaveLength(8);
    expect(parts.get('word/styles.xml')!.toString()).toContain('<w:keepLines/><w:spacing w:before="0" w:after="100" w:line="360" w:lineRule="exact"/>');
    await expect(generatePortfolioDocx([],{...fields,fullName:'Long name '.repeat(150)},null,'',async()=>Buffer.alloc(0)))
      .rejects.toMatchObject({code:'PORTFOLIO_TITLE_TOO_LONG'});
  });

  it('rejects multiple/multipage Creative Titles in DOCX rather than dropping source pages', async () => {
    const pdf=await PDFDocument.create();pdf.addPage();pdf.addPage();const bytes=Buffer.from(await pdf.save());
    await expect(generatePortfolioDocx([doc({folderKey:'creative-title',fileKind:'pdf'})],info,null,'',async()=>bytes))
      .rejects.toMatchObject({code:'PORTFOLIO_CREATIVE_TITLE_AMBIGUOUS'});
    await expect(generatePortfolioDocx([doc({folderKey:'creative-title'}),doc({folderKey:'creative-title'})],info,null,'',async()=>bytes))
      .rejects.toMatchObject({code:'PORTFOLIO_CREATIVE_TITLE_AMBIGUOUS'});
  });
});
