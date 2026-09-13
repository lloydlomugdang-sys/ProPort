import { describe, expect, it } from 'vitest';
import { CATEGORY_SEEDS } from '../../src/database/seeds/categories.seed.js';
import { suggestDocumentMetadata } from '../../src/modules/documents/metadata-suggestion.service.js';

export const certificateText = `CERTIFICATE OF COMPLETION
This certificate is proudly presented to
JUAN DELA CRUZ
for successfully completing the course
Introduction to Digital Documentation and OCR Systems
conducted by
GradPort Learning and Development Center
on September 14, 2026
Maria Santos
Program Director
John Lloyd Lomugdang
Project Lead
Certificate No.: GP-2026-0914-001`;

const suggest = (rawText: string) => suggestDocumentMetadata({ rawText }, CATEGORY_SEEDS);

describe('deterministic OCR metadata suggestions', () => {
  it('extracts the supplied certificate subject, date and grounded description, never its recipient or reflection', () => {
    expect(suggest(certificateText)).toEqual({
      categoryKey: 'certificates',
      folderKey: 'trainings',
      title: 'Introduction to Digital Documentation and OCR Systems',
      documentDate: '2026-09-14',
      description: 'Certificate of Completion for Introduction to Digital Documentation and OCR Systems, conducted by GradPort Learning and Development Center.',
    });
    expect(suggest(certificateText)).not.toHaveProperty('reflection');
  });

  it.each(['completion', 'participation', 'attendance', 'recognition'])('recognizes a certificate of %s without inventing a title or folder', (kind) => {
    expect(suggest(`Certificate of ${kind}\nPresented to\nJUAN DELA CRUZ`)).toEqual({ categoryKey: 'certificates' });
  });

  it('recognizes presentation plus completion phrases when the heading is missing', () => {
    expect(suggest('Awarded to\nJUAN DELA CRUZ\nfor successfully completing the course\nDigital Records Management')).toMatchObject({
      categoryKey: 'certificates', folderKey: 'trainings', title: 'Digital Records Management',
    });
  });

  it('maps a seminar only to its existing active category and folder', () => {
    expect(suggest('Certificate of Participation\nparticipated in the seminar: Digital Records Management')).toMatchObject({
      categoryKey: 'certificates', folderKey: 'seminars',
    });
    expect(suggestDocumentMetadata({ rawText: certificateText }, [])).not.toHaveProperty('categoryKey');
    expect(suggestDocumentMetadata({ rawText: certificateText }, [{ key: 'certificates', name: 'Certificates', folders: [] }])).not.toHaveProperty('folderKey');
  });

  it('prioritizes reviewed text and respects an intentionally empty review without changing input', () => {
    const input = Object.freeze({ rawText: certificateText, reviewedText: 'Title: Reviewed Document Title\nDated Sep 15, 2026' });
    expect(suggestDocumentMetadata(input, CATEGORY_SEEDS)).toEqual({ title: 'Reviewed Document Title', documentDate: '2026-09-15' });
    expect(input.rawText).toBe(certificateText);
    expect(suggestDocumentMetadata({ rawText: certificateText, reviewedText: '' }, CATEGORY_SEEDS)).toEqual({});
  });

  it('handles case, excess spaces, decoration, CRLF and a wrapped subject', () => {
    const noisy = certificateText.toLowerCase().replaceAll(' ', '   ').replaceAll('\n', '\r\n***\r\n')
      .replace('documentation   and   ocr', 'documentation   and\r\nocr');
    expect(suggest(noisy)).toMatchObject({
      categoryKey: 'certificates', folderKey: 'trainings',
      title: 'introduction to digital documentation and ocr systems', documentDate: '2026-09-14',
    });
  });

  it.each(['September 14, 2026', 'Sep 14, 2026', 'Sept. 14, 2026', '09/14/2026', '14/09/2026', '2026-09-14'])('parses %s to the upload date format', (date) => {
    expect(suggest(`Issued on ${date}`)).toEqual({ documentDate: '2026-09-14' });
  });

  it.each(['February 30, 2026', 'Feb 29, 2025', '31/04/2026', '13/14/2026', '00/14/2026', '2026-02-30', '09/10/2026'])('omits invalid or ambiguous date %s', (date) => {
    expect(suggest(`Issued on ${date}`)).toEqual({});
  });

  it('validates leap years and prioritizes issue context over unrelated dates', () => {
    expect(suggest('Feb 29, 2024')).toEqual({ documentDate: '2024-02-29' });
    expect(suggest('September 13, 2026\nAwarded on September 14, 2026')).toEqual({ documentDate: '2026-09-14' });
    expect(suggest('Born September 13, 2000\nExpires September 14, 2027')).toEqual({});
    expect(suggest('Issued September 13, 2026\nIssued September 14, 2026')).toEqual({});
  });

  it.each(['', '*** ___ |||', 'JUAN DELA CRUZ\nProgram Director', 'x7 @@ qqqqqqqq', 'Presented to JUAN DELA CRUZ'])('does not fabricate metadata for %j', (text) => {
    expect(suggest(text)).toEqual({});
  });

  it('returns partial labeled metadata without inventing category, issuer or date', () => {
    expect(suggest('Title: Community Records Project')).toEqual({ title: 'Community Records Project' });
    expect(suggest('Certificate of Completion\nCourse: Digital Records Management')).toEqual({
      categoryKey: 'certificates', folderKey: 'trainings', title: 'Digital Records Management',
      description: 'Certificate of Completion for Digital Records Management.',
    });
    expect(suggest('Certificate of Completion\nCourse: @@@@ 888')).toEqual({ categoryKey: 'certificates', folderKey: 'trainings' });
  });
});
