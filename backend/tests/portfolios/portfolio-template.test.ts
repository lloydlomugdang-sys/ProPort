import { describe, expect, it } from 'vitest';
import { PDFDocument, StandardFonts } from 'pdf-lib';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';
import catalog from '../../src/config/portfolio-templates.json' with { type: 'json' };
import { EFFECTIVE_PORTFOLIO_TEMPLATE as defaultTemplate, resolvePortfolioTemplate, normalizeCreativeTitles } from '../../src/modules/portfolios/portfolio-template.js';
import { PortfolioGeneratorService, planPortfolioSections } from '../../src/modules/portfolios/portfolio-generator.service.js';
import { generatePortfolioDocx } from '../../src/modules/portfolios/portfolio-docx.js';
import { portfolioDocument as doc, portfolioMemoryStorage, PORTFOLIO_TEST_INFO as info } from '../helpers/portfolio-fixtures.js';
import { docxParts } from '../helpers/docx-parts.js';
import { OFFICIAL_QUESTIONS } from '../../src/modules/college-report/college-report.template.js';

const config = () => structuredClone(catalog);
async function pages(bytes: Buffer) {
  const task = getDocument({ data: new Uint8Array(bytes), verbosity: 0 });
  try {
    const pdf = await task.promise, output = [];
    for (let i = 1; i <= pdf.numPages; i++) {
      const page = await pdf.getPage(i);
      const items = (await page.getTextContent()).items.filter(i => 'str' in i);
      output.push({ text: items.map(i => i.str).join(' '), items });
    }
    return output;
  } finally { await task.destroy(); }
}

describe('one effective supported portfolio template', () => {
  it('preserves the current default and exposes advisory required flags', () => {
    expect(defaultTemplate.sections.map(s => s.key)).toEqual(['curriculum-vitae', 'scholastic-record', 'certificates', 'accomplishments', 'other-achievements', 'college-report']);
    expect(defaultTemplate.sections.every(s => s.enabled && !s.required && s.generateCreativeTitle)).toBe(true);
    expect(defaultTemplate.includeTableOfContents).toBe(true);
    expect(Object.isFrozen(defaultTemplate.sections)).toBe(true);
    const c = config(); c.templates[0]!.sections[0]!.required = true;
    const effective = resolvePortfolioTemplate(c);
    expect(effective.sections[0]!.required).toBe(true);
    expect(planPortfolioSections([], effective)).toEqual([]); // no speculative export blocking
    expect(planPortfolioSections([doc({categoryKey:'curriculum-vitae'})], effective)[0]!.rule.required).toBe(true);
  });

  for (const [name, mutate] of [
    ['duplicate keys', (c: ReturnType<typeof config>) => { c.templates[0]!.sections[1]!.key = c.templates[0]!.sections[0]!.key; }],
    ['unsupported key', (c: ReturnType<typeof config>) => { c.templates[0]!.sections[0]!.key = 'invented'; }],
    ['duplicate order', (c: ReturnType<typeof config>) => { c.templates[0]!.sections[1]!.order = c.templates[0]!.sections[0]!.order; }],
    ['missing section', (c: ReturnType<typeof config>) => { c.templates[0]!.sections.pop(); }],
    ['invalid version', (c: ReturnType<typeof config>) => { c.templates[0]!.version = 0; }],
    ['fractional version', (c: ReturnType<typeof config>) => { c.templates[0]!.version = 1.5; }],
    ['invalid status', (c: ReturnType<typeof config>) => { c.templates[0]!.status = 'anything'; }],
    ['no active version', (c: ReturnType<typeof config>) => { c.templates[0]!.status = 'inactive'; }],
    ['multiple active versions', (c: ReturnType<typeof config>) => { c.templates.push({...c.templates[0]!, version:2}); }],
    ['duplicate version', (c: ReturnType<typeof config>) => { c.templates.push({...c.templates[0]!, status:'inactive'}); }],
    ['executable label', (c: ReturnType<typeof config>) => { c.templates[0]!.sections[0]!.label = '<script>alert(1)</script>'; }],
  ] as const) it(`rejects ${name}`, () => { const c = config(); mutate(c); expect(() => resolvePortfolioTemplate(c)).toThrow('Invalid portfolio-template configuration'); });
  for (const field of ['enabled', 'required', 'generateCreativeTitle']) it(`rejects non-boolean ${field}`, () => {
    const c = config(); Object.assign(c.templates[0]!.sections[0]!, {[field]:'true'});
    expect(() => resolvePortfolioTemplate(c)).toThrow();
  });
  it('rejects malformed/extra configuration, including inactive versions', () => {
    for (const bad of [null, [], {}, {templates:[]}, {...catalog, html:'bad'}, {templates:[{...catalog.templates[0], includeTableOfContents:'yes'}]}]) {
      expect(() => resolvePortfolioTemplate(bad)).toThrow();
    }
    const c = config(); c.templates.push({...c.templates[0]!, version:2, status:'inactive', sections:[]});
    expect(() => resolvePortfolioTemplate(c)).toThrow();
  });
  it('activates exactly one immutable version without generator changes', () => {
    const c = config(); c.templates[0]!.status='inactive';
    c.templates.push({...structuredClone(c.templates[0]!),version:2,status:'active',name:'Approved revision'});
    const t=resolvePortfolioTemplate(c); c.templates[1]!.name='Changed later';
    expect(t.version).toBe(2); expect(t.name).toBe('Approved revision');
  });
  it('validates saved plain-text Creative Titles independently of student/template ownership', () => {
    expect(normalizeCreativeTitles({'certificates':' My work ', 'college-report':''})).toEqual({certificates:'My work'});
    for (const bad of [{other:'Unknown'}, {certificates:'x'.repeat(201)}, {certificates:'<script>'}, {certificates:42}, []]) {
      expect(() => normalizeCreativeTitles(bad)).toThrow(expect.objectContaining({code:'VALIDATION_ERROR'}));
    }
  });

  it('same artifacts + A/B yield matching PDF/DOCX order, accurate TOC targets and unchanged within-section pages', async () => {
    const files = new Map<string, Buffer>();
    const records = [];
    for (const [i, rule] of defaultTemplate.sections.entries()) {
      const source = await PDFDocument.create(); const font = await source.embedFont(StandardFonts.Helvetica);
      for (let n=1;n<=2;n++) source.addPage().drawText(`SOURCE_${i}_PAGE_${n}`,{x:60,y:700,font,size:12});
      files.set(rule.key,Buffer.from(await source.save()));
      records.push(doc({categoryKey:rule.key,folderKey:rule.key==='certificates'?'trainings':rule.key,
        title:`Artifact ${i}`,objectKey:rule.key,fileKind:'pdf'}));
    }
    const b = config(); const order = ['curriculum-vitae','certificates','accomplishments','scholastic-record','other-achievements','college-report'];
    for (const s of b.templates[0]!.sections) { s.order=order.indexOf(s.key); if(s.key==='certificates') s.label='Approved Certificates'; }
    const report = {questionnaireVersion:2, updatedAt:new Date(0).toISOString(),essay:'Saved objectives',answers:OFFICIAL_QUESTIONS.map(q=>({questionKey:q.key,value:q.section.responseType==='text'?'Saved response':q.section.options[0]!.value}))};
    for (const t of [defaultTemplate,resolvePortfolioTemplate(b)]) {
      const storage=portfolioMemoryStorage(files), reads:string[]=[]; const get=storage.get.bind(storage);
      storage.get=async key=>{reads.push(key);return get(key);};
      const output=await pages(await new PortfolioGeneratorService(undefined,storage,undefined,undefined,t).generateFromDocuments(records,info,report));
      const word=docxParts(await generatePortfolioDocx(records,info,report,'',async key=>files.get(key)!,undefined,t)).get('word/document.xml')!.toString();
      let pdfAt=0,wordAt=word.indexOf('<w:bookmarkStart');
      for (const s of t.sections) {
        const original=defaultTemplate.sections.findIndex(x=>x.key===s.key);
        const first=output.findIndex(p=>p.text.includes(`SOURCE_${original}_PAGE_1`));
        expect(first).toBeGreaterThan(pdfAt);pdfAt=first;
        expect(output[first+1]!.text).toContain(`SOURCE_${original}_PAGE_2`);
        const item=word.indexOf(`Artifact ${original}, PDF page 1 of 2`,wordAt);
        expect(item).toBeGreaterThan(wordAt);wordAt=item;
        expect(word.indexOf(`Artifact ${original}, PDF page 2 of 2`,item)).toBeGreaterThan(item);
        const toc=output.find(p=>p.items.some(i=>i.str===s.label))!;
        const label=toc.items.find(i=>i.str===s.label)!;
        const target=toc.items.find(i=>/^\d+$/.test(i.str)&&i.transform[4]>500&&i.transform[5]===label.transform[5])!;
        expect(Number(target.str)).toBe(first+1);
        expect(word.replaceAll('&apos;', "'").split(`<w:t>${s.label}</w:t>`)).toHaveLength(2);
      }
      expect(reads).toEqual(t.sections.map(s=>s.key));
      expect(output.map(p=>p.text).join(' ')).toContain('Saved response');
      expect(word).toContain('Saved response');
    }
  }, 30_000);

  it('disables/re-enables sections and section titles, omits TOC cleanly, never fetches excluded evidence', async () => {
    const source=await PDFDocument.create();source.addPage().drawText('VISIBLE_SOURCE',{x:50,y:700});
    const bytes=Buffer.from(await source.save());
    const documents=[doc({objectKey:'first',fileKind:'pdf'}),doc({objectKey:'second',fileKind:'pdf'})];
    const titleInfo={...info,creativeTitles:{certificates:'My single saved section title'}};
    for (const [enabled, creative, toc] of [[true,true,true],[false,true,true],[true,false,true],[true,true,false]]) {
      const c=config(); const rule=c.templates[0]!.sections.find(s=>s.key==='certificates')!;
      rule.enabled=enabled!; rule.generateCreativeTitle=creative!; c.templates[0]!.includeTableOfContents=toc!;
      const t=resolvePortfolioTemplate(c), reads:string[]=[];
      const storage=portfolioMemoryStorage(new Map([['first',bytes],['second',bytes]]));
      const get=storage.get.bind(storage);storage.get=async key=>{reads.push(key);return get(key);};
      const pdf=await pages(await new PortfolioGeneratorService(undefined,storage,undefined,undefined,t).generateFromDocuments(documents,titleInfo));
      const parts=docxParts(await generatePortfolioDocx(documents,titleInfo,null,'',async key=>{reads.push(key);return bytes;},undefined,t));
      const word=parts.get('word/document.xml')!.toString(); const text=pdf.map(p=>p.text).join(' ');
      expect(text.includes('TABLE OF CONTENTS')).toBe(toc);
      expect(word.includes('TABLE OF CONTENTS')).toBe(toc);
      for(const output of [text,word]) expect(output.split('My single saved section title')).toHaveLength(enabled&&creative?2:1);
      expect(reads).toEqual(enabled?['first','second','first','second']:[]);
      expect(pdf.filter(p=>p.text.includes('VISIBLE_SOURCE'))).toHaveLength(enabled?2:0);
      expect(pdf).toHaveLength(1+Number(toc)+(enabled?2+Number(creative):0));
      expect([...parts.keys()].filter(k=>k.startsWith('word/media/'))).toHaveLength(enabled?3:1);
      if(!enabled) { expect(text).not.toContain('Certificates');expect(word).not.toContain('Certificates'); }
    }
    expect(documents).toHaveLength(2); // pure generation, no storage writes/deletes
  },30_000);

  it('disabled College Report suppresses saved responses; disabled legacy title skips only that artifact', async () => {
    const c=config();c.templates[0]!.sections.find(s=>s.key==='college-report')!.enabled=false;
    c.templates[0]!.sections.find(s=>s.key==='certificates')!.generateCreativeTitle=false;
    const t=resolvePortfolioTemplate(c);
    const docs=[doc({folderKey:'creative-title'}),doc({title:'Actual evidence'})];
    const plan=planPortfolioSections(docs,t,{},true);
    expect(plan).toHaveLength(1);expect(plan[0]!.subsections.flatMap(s=>s.items).map(i=>i.document.title)).toEqual(['Actual evidence']);
    expect(planPortfolioSections([],t,{},true)).toEqual([]);
    const report={questionnaireVersion:2,updatedAt:new Date(0).toISOString(),answers:[],essay:'MY_SAVED_ESSAY'};
    const pdf=await pages(await new PortfolioGeneratorService(undefined,portfolioMemoryStorage(),undefined,undefined,t).generateFromDocuments([],info,report));
    const word=docxParts(await generatePortfolioDocx([],info,report,'',async()=>{throw new Error('No reads expected');},undefined,t)).get('word/document.xml')!.toString();
    for(const text of [pdf.map(p=>p.text).join(' '),word]) { expect(text).not.toContain('MY_SAVED_ESSAY');expect(text).not.toContain('College Report'); }
  });
});
