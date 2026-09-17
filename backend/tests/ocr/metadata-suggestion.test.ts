import { describe, expect, it } from 'vitest';
import { CATEGORY_SEEDS } from '../../src/database/seeds/categories.seed.js';
import {
  resolveCanonicalSection,
  resolveCanonicalTaxonomy,
  suggestDocumentMetadata,
} from '../../src/modules/documents/metadata-suggestion.service.js';

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

  describe('canonical GradPort category suggestions', () => {
    it('recognizes Curriculum Vitae from explicit CV heading and never suggests reflection', () => {
      const cvText = `Curriculum Vitae
John Lloyd Lomugdang
Email: john@example.com
Education: Bachelor of Science in Information Technology
Work Experience: Software Developer Intern at Tech Corp
Skills: TypeScript, Dart, Flutter, Node.js`;
      const result = suggest(cvText);
      expect(result).toMatchObject({
        categoryKey: 'curriculum-vitae',
        folderKey: 'curriculum-vitae',
        title: 'Curriculum Vitae',
      });
      expect(result.description).toContain('Curriculum Vitae');
      expect(result).not.toHaveProperty('reflection');
    });

    it('recognizes resume without explicit CV heading through resume sections', () => {
      const resumeText = `RESUME OF QUALIFICATIONS
Jane Doe
Professional Experience: Frontend Engineer (2024 - 2026)
Educational Background: BS Computer Science, University of Cebu
Technical Skills: React, Flutter, State Management`;
      const result = suggest(resumeText);
      expect(result).toMatchObject({
        categoryKey: 'curriculum-vitae',
        folderKey: 'curriculum-vitae',
      });
      expect(result.title).toBe('RESUME OF QUALIFICATIONS');
      expect(result).not.toHaveProperty('reflection');
    });

    it('recognizes Scholastic Record / Transcript of Records', () => {
      const torText = `OFFICIAL TRANSCRIPT OF RECORDS
Student ID: 2022-00123
Course: BSIT
Semestral Grades:
IT101 - Programming 1: 1.25
IT102 - Data Structures: 1.50
Total Units Earned: 24.0
Issued on September 14, 2026`;
      const result = suggest(torText);
      expect(result).toMatchObject({
        categoryKey: 'scholastic-record',
        folderKey: 'unofficial-tor-with-reflections',
        title: 'OFFICIAL TRANSCRIPT OF RECORDS',
        documentDate: '2026-09-14',
      });
      expect(result.description).toContain('Scholastic Record');
      expect(result).not.toHaveProperty('reflection');
    });

    it('recognizes College Report from internship and practicum narrative', () => {
      const reportText = `Internship Narrative Report
GradPort On-The-Job Training Practicum
Company: Innovate Solutions Inc.
Period: June 2026 - August 2026
Dated August 30, 2026`;
      const result = suggest(reportText);
      expect(result).toMatchObject({
        categoryKey: 'college-report',
        folderKey: 'college-report',
        title: 'Internship Narrative Report',
        documentDate: '2026-08-30',
      });
      expect(result).not.toHaveProperty('reflection');
    });

    it('recognizes Accomplishments (thesis, capstone, case studies)', () => {
      const thesisText = `Undergraduate Thesis Project
Title: Automated Academic Portfolio System
Presented by Senior IT Students
Dated May 20, 2026`;
      const result = suggest(thesisText);
      expect(result).toMatchObject({
        categoryKey: 'accomplishments',
        folderKey: 'thesis-capstone',
        documentDate: '2026-05-20',
      });
      expect(result).not.toHaveProperty('reflection');
    });

    it('recognizes Other Achievements from hackathons or competitions', () => {
      const hackathonText = `Hackathon Project: Campus Safety Emergency App
Award: First Place Innovation Challenge
Conducted on October 10, 2026`;
      const result = suggest(hackathonText);
      expect(result).toMatchObject({
        categoryKey: 'other-achievements',
        folderKey: 'projects',
        documentDate: '2026-10-10',
      });
      expect(result).not.toHaveProperty('reflection');
    });

    it('recognizes standalone awards and recognitions as Other Achievements', () => {
      const awardText = `Leadership Excellence Award
Awarded to Juan Dela Cruz for outstanding student leadership
Dated October 15, 2026`;
      const result = suggest(awardText);
      expect(result).toMatchObject({
        categoryKey: 'other-achievements',
        folderKey: 'projects',
        documentDate: '2026-10-15',
      });
      expect(result).not.toHaveProperty('reflection');
    });

    it('recognizes Creative Title section divider artifact', () => {
      const creativeTitleText = `CREATIVE TITLE
GradPort Academic Portfolio
Section: Curriculum Vitae
Compiled by Juan Dela Cruz
Dated September 1, 2026`;
      const result = suggest(creativeTitleText);
      expect(result).toMatchObject({
        categoryKey: 'curriculum-vitae',
        folderKey: 'creative-title',
        title: 'CREATIVE TITLE',
        documentDate: '2026-09-01',
      });
      expect(result.description).toContain('Creative Title');
      expect(result).not.toHaveProperty('reflection');
    });
  });

  describe('canonical GradPort portfolio taxonomy and section mapping', () => {
    it.each([
      // resume/CV → curriculum-vitae
      { input: 'resume', expectedCat: 'curriculum-vitae', expectedFolder: 'curriculum-vitae', expectedSection: 'curriculum-vitae' },
      { input: 'CV', expectedCat: 'curriculum-vitae', expectedFolder: 'curriculum-vitae', expectedSection: 'curriculum-vitae' },
      { input: 'curriculum_vitae', expectedCat: 'curriculum-vitae', expectedFolder: 'curriculum-vitae', expectedSection: 'curriculum-vitae' },
      { input: 'personal_info', expectedCat: 'curriculum-vitae', expectedFolder: 'curriculum-vitae', expectedSection: 'curriculum-vitae' },

      // transcript/grades → scholastic-record
      { input: 'transcript', expectedCat: 'scholastic-record', expectedFolder: 'unofficial-tor-with-reflections', expectedSection: 'scholastic-record' },
      { input: 'transcripts', expectedCat: 'scholastic-record', expectedFolder: 'unofficial-tor-with-reflections', expectedSection: 'scholastic-record' },
      { input: 'grades', expectedCat: 'scholastic-record', expectedFolder: 'unofficial-tor-with-reflections', expectedSection: 'scholastic-record' },
      { input: 'scholastic_record', expectedCat: 'scholastic-record', expectedFolder: 'unofficial-tor-with-reflections', expectedSection: 'scholastic-record' },
      { input: 'credentials', expectedCat: 'scholastic-record', expectedFolder: 'unofficial-tor-with-reflections', expectedSection: 'scholastic-record' },

      // certificate → certificates
      { input: 'certificate', expectedCat: 'certificates', expectedFolder: 'trainings', expectedSection: 'certificates' },
      { input: 'certifications', expectedCat: 'certificates', expectedFolder: 'trainings', expectedSection: 'certificates' },
      { input: 'seminar', expectedCat: 'certificates', expectedFolder: 'seminars', expectedSection: 'certificates' },

      // project/thesis → accomplishments
      { input: 'project', expectedCat: 'accomplishments', expectedFolder: 'projects', expectedSection: 'accomplishments' },
      { input: 'thesis', expectedCat: 'accomplishments', expectedFolder: 'thesis-capstone', expectedSection: 'accomplishments' },
      { input: 'capstone', expectedCat: 'accomplishments', expectedFolder: 'thesis-capstone', expectedSection: 'accomplishments' },
      { input: 'case study', expectedCat: 'accomplishments', expectedFolder: 'case-studies', expectedSection: 'accomplishments' },

      // award/recognition → other-achievements
      { input: 'award', expectedCat: 'other-achievements', expectedFolder: 'projects', expectedSection: 'other-achievements' },
      { input: 'recognition', expectedCat: 'other-achievements', expectedFolder: 'projects', expectedSection: 'other-achievements' },
      { input: 'hackathon', expectedCat: 'other-achievements', expectedFolder: 'projects', expectedSection: 'other-achievements' },
      { input: 'clearances', expectedCat: 'other-achievements', expectedFolder: 'projects', expectedSection: 'other-achievements' },

      // OJT/practicum/college report → college-report
      { input: 'OJT', expectedCat: 'college-report', expectedFolder: 'college-report', expectedSection: 'college-report' },
      { input: 'practicum', expectedCat: 'college-report', expectedFolder: 'college-report', expectedSection: 'college-report' },
      { input: 'college report', expectedCat: 'college-report', expectedFolder: 'college-report', expectedSection: 'college-report' },
      { input: 'internship report', expectedCat: 'college-report', expectedFolder: 'college-report', expectedSection: 'college-report' },

      // creative title artifact → creative-title
      { input: 'creative title artifact', expectedCat: 'curriculum-vitae', expectedFolder: 'creative-title', expectedSection: 'creative-title' },
      { input: 'creative-title', expectedCat: 'curriculum-vitae', expectedFolder: 'creative-title', expectedSection: 'creative-title' },
      { input: 'section divider', expectedCat: 'curriculum-vitae', expectedFolder: 'creative-title', expectedSection: 'creative-title' },
    ])('maps $input → category $expectedCat / section $expectedSection', ({ input, expectedCat, expectedFolder, expectedSection }) => {
      const resolved = resolveCanonicalTaxonomy(input, undefined, CATEGORY_SEEDS);
      expect(resolved.category?.key).toBe(expectedCat);
      expect(resolved.folderKey).toBe(expectedFolder);
      expect(resolved.sectionKey).toBe(expectedSection);

      const sectionResult = resolveCanonicalSection(input);
      expect(sectionResult.sectionKey).toBe(expectedSection);
    });

    it('resolves canonical section from document records', () => {
      // Document in creative-title folder always maps to creative-title section
      expect(resolveCanonicalSection({ categoryKey: 'certificates', folderKey: 'creative-title' })).toEqual({
        sectionKey: 'creative-title',
        sectionName: 'Creative Title',
      });

      // Regular document maps to its category section
      expect(resolveCanonicalSection({ categoryKey: 'curriculum-vitae', folderKey: 'curriculum-vitae' })).toEqual({
        sectionKey: 'curriculum-vitae',
        sectionName: 'Curriculum Vitae',
      });
      expect(resolveCanonicalSection({ categoryKey: 'scholastic-record', folderKey: 'unofficial-tor-with-reflections' })).toEqual({
        sectionKey: 'scholastic-record',
        sectionName: 'Scholastic Record',
      });
      expect(resolveCanonicalSection({ categoryKey: 'certificates', folderKey: 'trainings' })).toEqual({
        sectionKey: 'certificates',
        sectionName: 'Certificates',
      });
      expect(resolveCanonicalSection({ categoryKey: 'accomplishments', folderKey: 'thesis-capstone' })).toEqual({
        sectionKey: 'accomplishments',
        sectionName: 'Accomplishments',
      });
      expect(resolveCanonicalSection({ categoryKey: 'other-achievements', folderKey: 'projects' })).toEqual({
        sectionKey: 'other-achievements',
        sectionName: 'Other Achievements',
      });
      expect(resolveCanonicalSection({ categoryKey: 'college-report', folderKey: 'college-report' })).toEqual({
        sectionKey: 'college-report',
        sectionName: 'College Report',
      });
    });
  });
});
