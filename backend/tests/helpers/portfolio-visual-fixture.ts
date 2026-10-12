import { PDFDocument, StandardFonts, rgb } from 'pdf-lib';
import sharp from 'sharp';
import { PortfolioGeneratorService } from '../../src/modules/portfolios/portfolio-generator.service.js';
import { OFFICIAL_QUESTIONS } from '../../src/modules/college-report/college-report.template.js';
import { portfolioDocument, portfolioMemoryStorage, PORTFOLIO_TEST_INFO } from './portfolio-fixtures.js';

/** Synthetic only. Exercises the production generator without a DB or network. */
export async function createPortfolioVisualFixture(): Promise<Buffer> {
  const source = await PDFDocument.create();
  const font = await source.embedFont(StandardFonts.Helvetica);
  for (const [width, height] of [[595, 842], [1000, 600], [612, 792]]) {
    const page = source.addPage([width!, height!]);
    page.drawRectangle({ x: 1, y: 1, width: width! - 2, height: height! - 2,
      borderWidth: 1, borderColor: rgb(0, 0, 0) });
    page.drawText('SYNTHETIC SOURCE - NOT A STUDENT RECORD', { x: 12, y: height! - 30, size: 12, font });
    page.drawText('BOTTOM LEFT', { x: 5, y: 10, size: 10, font });
    page.drawText('BOTTOM RIGHT', { x: width! - 100, y: 10, size: 10, font });
    page.drawText(`${width} x ${height} - preserve aspect ratio`, { x: 30, y: height! / 2, size: 18, font });
  }
  const image = await sharp(Buffer.from('<svg width="800" height="600" xmlns="http://www.w3.org/2000/svg"><rect x="2" y="2" width="796" height="596" fill="#edf4f7" stroke="#16475c" stroke-width="4"/><circle cx="400" cy="300" r="150" fill="none" stroke="#16475c" stroke-width="5"/><text x="50" y="80" font-size="24">SYNTHETIC IMAGE - KEEP CIRCLE ROUND</text></svg>')).png().toBuffer();
  const files = new Map([['fixture.pdf', Buffer.from(await source.save())], ['fixture.png', image]]);
  const pairs = [
    ['certificates', 'creative-title'], ['curriculum-vitae', 'curriculum-vitae'],
    ['scholastic-record', 'unofficial-tor-with-reflections'],
    ['certificates', 'seminars'], ['certificates', 'other-seminars'], ['certificates', 'trainings'],
    ['accomplishments', 'thesis-capstone'], ['accomplishments', 'case-studies'],
    ['accomplishments', 'projects'], ['accomplishments', 'assessments'],
    ['other-achievements', 'projects'], ['college-report', 'college-report'],
  ];
  const documents = pairs.map(([categoryKey, folderKey], index) => portfolioDocument({
    categoryKey: categoryKey!, folderKey: folderKey!,
    title: `Fixture ${index + 1}: ${folderKey} - ${'a deliberately long academic evidence title '.repeat(index === 3 ? 3 : 1)}`,
    objectKey: index === 1 ? 'fixture.pdf' : 'fixture.png',
    fileKind: index === 1 ? 'pdf' : 'image',
    description: index === 2 ? Array.from({ length: 22 }, (_, n) => `Synthetic description line ${n + 1}.`).join('\n') : 'Synthetic evidence for formatting QA only.',
    ...(index === 2 ? { reflection: Array.from({ length: 55 }, (_, n) => `Reflection ${n + 1}: my own example learning evidence continues in full.`).join('\n') } : {}),
  }));
  return new PortfolioGeneratorService(undefined, portfolioMemoryStorage(files)).generateFromDocuments(
    documents, PORTFOLIO_TEST_INFO, {
      questionnaireVersion: 2, updatedAt: '2026-10-12T00:00:00.000Z',
      answers: OFFICIAL_QUESTIONS.map((question, index) => ({
        questionKey: question.key,
        value: index % 4 === 0 ? null : question.section.responseType === 'text'
          ? 'Synthetic written response for visual QA only.'
          : question.section.options[0]!.value,
      })),
      essay: Array.from({ length: 65 }, (_, n) => `Synthetic student-written essay line ${n + 1}: learning outcomes and objectives.`).join('\n'),
    },
  );
}
