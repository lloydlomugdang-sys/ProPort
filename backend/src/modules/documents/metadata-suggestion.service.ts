import type { PublicDocumentCategory } from './document.service.js';

export const CANONICAL_SECTION_KEYS = [
  'creative-title',
  'curriculum-vitae',
  'scholastic-record',
  'certificates',
  'accomplishments',
  'other-achievements',
  'college-report',
] as const;

export type CanonicalSectionKey = typeof CANONICAL_SECTION_KEYS[number];

export const CANONICAL_SECTION_NAMES: Readonly<Record<CanonicalSectionKey, string>> = {
  'creative-title': 'Creative Title',
  'curriculum-vitae': 'Curriculum Vitae',
  'scholastic-record': 'Scholastic Record',
  'certificates': 'Certificates',
  'accomplishments': 'Accomplishments',
  'other-achievements': 'Other Achievements',
  'college-report': 'College Report',
} as const;

export interface TaxonomyMapping {
  readonly categoryKey: string;
  readonly defaultFolderKey: string;
  readonly sectionKey: CanonicalSectionKey;
}

export const DOCUMENT_TYPE_TAXONOMY: Readonly<Record<string, TaxonomyMapping>> = {
  // 1. Curriculum Vitae (resume / CV / personal_info / bio-data)
  'curriculum-vitae': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'curriculum-vitae', sectionKey: 'curriculum-vitae' },
  'curriculum_vitae': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'curriculum-vitae', sectionKey: 'curriculum-vitae' },
  'curriculum vitae': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'curriculum-vitae', sectionKey: 'curriculum-vitae' },
  'cv': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'curriculum-vitae', sectionKey: 'curriculum-vitae' },
  'resume': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'curriculum-vitae', sectionKey: 'curriculum-vitae' },
  'resumes': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'curriculum-vitae', sectionKey: 'curriculum-vitae' },
  'biodata': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'curriculum-vitae', sectionKey: 'curriculum-vitae' },
  'bio-data': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'curriculum-vitae', sectionKey: 'curriculum-vitae' },
  'personal_info': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'curriculum-vitae', sectionKey: 'curriculum-vitae' },
  'personal info': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'curriculum-vitae', sectionKey: 'curriculum-vitae' },
  'personal information': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'curriculum-vitae', sectionKey: 'curriculum-vitae' },

  // 2. Scholastic Record (transcripts / grades / credentials / TOR)
  'scholastic-record': { categoryKey: 'scholastic-record', defaultFolderKey: 'unofficial-tor-with-reflections', sectionKey: 'scholastic-record' },
  'scholastic_record': { categoryKey: 'scholastic-record', defaultFolderKey: 'unofficial-tor-with-reflections', sectionKey: 'scholastic-record' },
  'scholastic record': { categoryKey: 'scholastic-record', defaultFolderKey: 'unofficial-tor-with-reflections', sectionKey: 'scholastic-record' },
  'transcript': { categoryKey: 'scholastic-record', defaultFolderKey: 'unofficial-tor-with-reflections', sectionKey: 'scholastic-record' },
  'transcripts': { categoryKey: 'scholastic-record', defaultFolderKey: 'unofficial-tor-with-reflections', sectionKey: 'scholastic-record' },
  'transcript of records': { categoryKey: 'scholastic-record', defaultFolderKey: 'unofficial-tor-with-reflections', sectionKey: 'scholastic-record' },
  'tor': { categoryKey: 'scholastic-record', defaultFolderKey: 'unofficial-tor-with-reflections', sectionKey: 'scholastic-record' },
  'grades': { categoryKey: 'scholastic-record', defaultFolderKey: 'unofficial-tor-with-reflections', sectionKey: 'scholastic-record' },
  'grade report': { categoryKey: 'scholastic-record', defaultFolderKey: 'unofficial-tor-with-reflections', sectionKey: 'scholastic-record' },
  'certificate of grades': { categoryKey: 'scholastic-record', defaultFolderKey: 'unofficial-tor-with-reflections', sectionKey: 'scholastic-record' },
  'credentials': { categoryKey: 'scholastic-record', defaultFolderKey: 'unofficial-tor-with-reflections', sectionKey: 'scholastic-record' },

  // 3. Certificates (certificates / certifications / seminars / trainings / workshops)
  'certificates': { categoryKey: 'certificates', defaultFolderKey: 'trainings', sectionKey: 'certificates' },
  'certificate': { categoryKey: 'certificates', defaultFolderKey: 'trainings', sectionKey: 'certificates' },
  'certifications': { categoryKey: 'certificates', defaultFolderKey: 'trainings', sectionKey: 'certificates' },
  'certification': { categoryKey: 'certificates', defaultFolderKey: 'trainings', sectionKey: 'certificates' },
  'seminar': { categoryKey: 'certificates', defaultFolderKey: 'seminars', sectionKey: 'certificates' },
  'seminars': { categoryKey: 'certificates', defaultFolderKey: 'seminars', sectionKey: 'certificates' },
  'other-seminars': { categoryKey: 'certificates', defaultFolderKey: 'other-seminars', sectionKey: 'certificates' },
  'other seminars': { categoryKey: 'certificates', defaultFolderKey: 'other-seminars', sectionKey: 'certificates' },
  'trainings': { categoryKey: 'certificates', defaultFolderKey: 'trainings', sectionKey: 'certificates' },
  'training': { categoryKey: 'certificates', defaultFolderKey: 'trainings', sectionKey: 'certificates' },
  'webinar': { categoryKey: 'certificates', defaultFolderKey: 'seminars', sectionKey: 'certificates' },
  'workshop': { categoryKey: 'certificates', defaultFolderKey: 'trainings', sectionKey: 'certificates' },

  // 4. Accomplishments (project / thesis / capstone / case study / assessment)
  'accomplishments': { categoryKey: 'accomplishments', defaultFolderKey: 'projects', sectionKey: 'accomplishments' },
  'accomplishment': { categoryKey: 'accomplishments', defaultFolderKey: 'projects', sectionKey: 'accomplishments' },
  'thesis': { categoryKey: 'accomplishments', defaultFolderKey: 'thesis-capstone', sectionKey: 'accomplishments' },
  'capstone': { categoryKey: 'accomplishments', defaultFolderKey: 'thesis-capstone', sectionKey: 'accomplishments' },
  'thesis-capstone': { categoryKey: 'accomplishments', defaultFolderKey: 'thesis-capstone', sectionKey: 'accomplishments' },
  'thesis/capstone': { categoryKey: 'accomplishments', defaultFolderKey: 'thesis-capstone', sectionKey: 'accomplishments' },
  'case study': { categoryKey: 'accomplishments', defaultFolderKey: 'case-studies', sectionKey: 'accomplishments' },
  'case studies': { categoryKey: 'accomplishments', defaultFolderKey: 'case-studies', sectionKey: 'accomplishments' },
  'case-studies': { categoryKey: 'accomplishments', defaultFolderKey: 'case-studies', sectionKey: 'accomplishments' },
  'project': { categoryKey: 'accomplishments', defaultFolderKey: 'projects', sectionKey: 'accomplishments' },
  'projects': { categoryKey: 'accomplishments', defaultFolderKey: 'projects', sectionKey: 'accomplishments' },
  'assessment': { categoryKey: 'accomplishments', defaultFolderKey: 'assessments', sectionKey: 'accomplishments' },
  'assessments': { categoryKey: 'accomplishments', defaultFolderKey: 'assessments', sectionKey: 'accomplishments' },

  // 5. Other Achievements (award / recognition / competition / hackathon / extracurricular / clearances / other)
  'other-achievements': { categoryKey: 'other-achievements', defaultFolderKey: 'projects', sectionKey: 'other-achievements' },
  'other_achievements': { categoryKey: 'other-achievements', defaultFolderKey: 'projects', sectionKey: 'other-achievements' },
  'other achievements': { categoryKey: 'other-achievements', defaultFolderKey: 'projects', sectionKey: 'other-achievements' },
  'award': { categoryKey: 'other-achievements', defaultFolderKey: 'projects', sectionKey: 'other-achievements' },
  'awards': { categoryKey: 'other-achievements', defaultFolderKey: 'projects', sectionKey: 'other-achievements' },
  'recognition': { categoryKey: 'other-achievements', defaultFolderKey: 'projects', sectionKey: 'other-achievements' },
  'competition': { categoryKey: 'other-achievements', defaultFolderKey: 'projects', sectionKey: 'other-achievements' },
  'competitions': { categoryKey: 'other-achievements', defaultFolderKey: 'projects', sectionKey: 'other-achievements' },
  'hackathon': { categoryKey: 'other-achievements', defaultFolderKey: 'projects', sectionKey: 'other-achievements' },
  'hackathons': { categoryKey: 'other-achievements', defaultFolderKey: 'projects', sectionKey: 'other-achievements' },
  'extracurricular': { categoryKey: 'other-achievements', defaultFolderKey: 'projects', sectionKey: 'other-achievements' },
  'extracurriculars': { categoryKey: 'other-achievements', defaultFolderKey: 'projects', sectionKey: 'other-achievements' },
  'clearance': { categoryKey: 'other-achievements', defaultFolderKey: 'projects', sectionKey: 'other-achievements' },
  'clearances': { categoryKey: 'other-achievements', defaultFolderKey: 'projects', sectionKey: 'other-achievements' },
  'other': { categoryKey: 'other-achievements', defaultFolderKey: 'projects', sectionKey: 'other-achievements' },

  // 6. College Report (OJT / practicum / internship / narrative report)
  'college-report': { categoryKey: 'college-report', defaultFolderKey: 'college-report', sectionKey: 'college-report' },
  'college_report': { categoryKey: 'college-report', defaultFolderKey: 'college-report', sectionKey: 'college-report' },
  'college report': { categoryKey: 'college-report', defaultFolderKey: 'college-report', sectionKey: 'college-report' },
  'ojt': { categoryKey: 'college-report', defaultFolderKey: 'college-report', sectionKey: 'college-report' },
  'on-the-job training': { categoryKey: 'college-report', defaultFolderKey: 'college-report', sectionKey: 'college-report' },
  'on-the-job-training': { categoryKey: 'college-report', defaultFolderKey: 'college-report', sectionKey: 'college-report' },
  'practicum': { categoryKey: 'college-report', defaultFolderKey: 'college-report', sectionKey: 'college-report' },
  'practicum report': { categoryKey: 'college-report', defaultFolderKey: 'college-report', sectionKey: 'college-report' },
  'internship': { categoryKey: 'college-report', defaultFolderKey: 'college-report', sectionKey: 'college-report' },
  'internship report': { categoryKey: 'college-report', defaultFolderKey: 'college-report', sectionKey: 'college-report' },
  'narrative report': { categoryKey: 'college-report', defaultFolderKey: 'college-report', sectionKey: 'college-report' },
  'terminal report': { categoryKey: 'college-report', defaultFolderKey: 'college-report', sectionKey: 'college-report' },

  // 7. Creative Title (creative-title / section divider / creative title artifact)
  'creative-title': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'creative-title', sectionKey: 'creative-title' },
  'creative_title': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'creative-title', sectionKey: 'creative-title' },
  'creative title': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'creative-title', sectionKey: 'creative-title' },
  'creative title artifact': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'creative-title', sectionKey: 'creative-title' },
  'section divider': { categoryKey: 'curriculum-vitae', defaultFolderKey: 'creative-title', sectionKey: 'creative-title' },
};

export function resolveCanonicalSection(
  target: string | { readonly categoryKey?: string; readonly folderKey?: string },
): { readonly sectionKey: CanonicalSectionKey; readonly sectionName: string } {
  if (typeof target === 'object' && target !== null) {
    if (target.folderKey === 'creative-title') {
      return { sectionKey: 'creative-title', sectionName: 'Creative Title' };
    }
    const catKey = target.categoryKey?.toLowerCase();
    const mapping = catKey ? (DOCUMENT_TYPE_TAXONOMY[catKey] ?? DOCUMENT_TYPE_TAXONOMY[catKey.replace(/[_-]+/g, ' ')]) : undefined;
    if (mapping) {
      return {
        sectionKey: mapping.sectionKey,
        sectionName: CANONICAL_SECTION_NAMES[mapping.sectionKey],
      };
    }
    return { sectionKey: 'other-achievements', sectionName: 'Other Achievements' };
  }

  const str = String(target || '').trim().toLowerCase();
  const norm = str.replace(/[_-]+/g, ' ');
  const mapping = DOCUMENT_TYPE_TAXONOMY[str] ?? DOCUMENT_TYPE_TAXONOMY[norm];
  if (mapping) {
    return {
      sectionKey: mapping.sectionKey,
      sectionName: CANONICAL_SECTION_NAMES[mapping.sectionKey],
    };
  }
  return { sectionKey: 'other-achievements', sectionName: 'Other Achievements' };
}

export function resolveCanonicalTaxonomy(
  rawCategoryOrType: string | undefined,
  rawFolder: string | undefined,
  categories: readonly PublicDocumentCategory[],
): {
  readonly category?: PublicDocumentCategory | undefined;
  readonly folderKey?: string | undefined;
  readonly sectionKey?: CanonicalSectionKey | undefined;
} {
  if (!rawCategoryOrType || rawCategoryOrType.trim().length === 0) return {};

  const cleanInput = rawCategoryOrType.normalize('NFKC').trim().toLowerCase();
  const cleanInputSpaced = cleanInput.replace(/[_-]+/g, ' ');

  // 1. Direct match in database categories list by key or name
  let matchedCat = categories.find((item) =>
    item.key.toLowerCase() === cleanInput ||
    item.name.toLowerCase() === cleanInput ||
    item.key.replace(/[_-]+/g, ' ').toLowerCase() === cleanInputSpaced ||
    item.name.replace(/[_-]+/g, ' ').toLowerCase() === cleanInputSpaced,
  );

  // 2. Lookup in taxonomy dictionary
  const mapping = DOCUMENT_TYPE_TAXONOMY[cleanInput] ?? DOCUMENT_TYPE_TAXONOMY[cleanInputSpaced];
  if (!matchedCat && mapping) {
    matchedCat = categories.find((item) => item.key === mapping.categoryKey);
  }

  const sectionKey = mapping?.sectionKey ?? (matchedCat?.key as CanonicalSectionKey | undefined);

  if (!matchedCat) {
    return { sectionKey };
  }

  // Resolve folder
  let matchedFolderKey: string | undefined;
  if (rawFolder !== undefined && rawFolder.trim().length > 0) {
    const cleanFolder = rawFolder.normalize('NFKC').trim().toLowerCase();
    const cleanFolderSpaced = cleanFolder.replace(/[_-]+/g, ' ');
    const foundFolder = matchedCat.folders.find((item) =>
      item.key.toLowerCase() === cleanFolder ||
      item.name.toLowerCase() === cleanFolder ||
      item.key.replace(/[_-]+/g, ' ').toLowerCase() === cleanFolderSpaced ||
      item.name.replace(/[_-]+/g, ' ').toLowerCase() === cleanFolderSpaced,
    );
    matchedFolderKey = foundFolder?.key;
  } else if (cleanInput === 'creative-title' || cleanInputSpaced === 'creative title' || cleanInputSpaced.includes('creative title')) {
    const creativeFolder = matchedCat.folders.find((f) => f.key === 'creative-title');
    matchedFolderKey = creativeFolder?.key ?? 'creative-title';
  } else if (mapping?.defaultFolderKey) {
    const hasDefault = matchedCat.folders.some((f) => f.key === mapping.defaultFolderKey);
    if (hasDefault) {
      matchedFolderKey = mapping.defaultFolderKey;
    }
  }

  return {
    category: matchedCat,
    folderKey: matchedFolderKey,
    sectionKey: matchedFolderKey === 'creative-title' ? 'creative-title' : sectionKey,
  };
}

export interface MetadataSuggestions {
  readonly categoryKey?: string;
  readonly folderKey?: string;
  readonly title?: string;
  readonly documentDate?: string;
  readonly description?: string;
}

interface OcrText {
  readonly reviewedText?: string;
  readonly rawText?: string;
}

const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
const MONTH_PATTERN = '(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept?|Oct|Nov|Dec)';
const CERTIFICATE = /\bcertificate\s+of\s+(completion|participation|attendance|recognition)\b/i;
const SUBJECT = /(?:\b(?:successfully\s+)?completing\s+(?:the\s+)?(?:course|training|seminar|workshop)?\s*|\bparticipated\s+in\s+(?:the\s+)?(?:(?:course|training|seminar|webinar|workshop)\b\s*)?|\b(?:course|event|activity|seminar|training|workshop|title|subject)\s*:\s*)/i;
const BOUNDARY = /\b(?:conducted\s+(?:by|on)|organized\s+by|issued\s+(?:by|on)|awarded\s+on|dated|presented\s+to|awarded\s+to|certificate\s+(?:no|number))\b|\bon\s+(?=\d|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)/i;

function linesOf(text: string): string[] {
  return text.normalize('NFKC').replace(/\r\n?/g, '\n').split('\n')
    .map((line) => line.replace(/[^\S\n]+/g, ' ').replace(/^[\s|*_=~•-]+|[\s|*_=~•-]+$/g, '').trim())
    .filter((line) => /[\p{L}\d]/u.test(line));
}

function meaningful(value: string): boolean {
  const letters = value.match(/\p{L}/gu)?.length ?? 0;
  return value.length >= 6 && value.length <= 250 && letters / value.length >= 0.6 &&
    value.split(' ').filter((word) => /\p{L}{2}/u.test(word)).length >= 2 &&
    !/(.)\1{4}/.test(value) && !CERTIFICATE.test(value) &&
    !/^(?:this certificate|presented to|awarded to|for |on |conducted|issued|program director|project lead|certificate no)/i.test(value);
}

function subjectOf(lines: readonly string[]): string | undefined {
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index]!;
    const marker = SUBJECT.exec(line);
    if (marker === null) continue;
    const parts: string[] = [];
    const tail = line.slice(marker.index + marker[0].length);
    // Only read text immediately following an explicit subject marker; never guess
    // from the recipient line or from arbitrary capitalized OCR lines.
    for (const candidate of [tail, ...lines.slice(index + 1, index + 4)]) {
      const boundary = BOUNDARY.exec(candidate);
      const segment = (boundary === null ? candidate : candidate.slice(0, boundary.index))
        .replace(/^[\s:;,"“”]+|[\s:;,"“”]+$/g, '').trim();
      if (/^(?:the )?(?:course|seminar|training|workshop)$/i.test(segment)) continue;
      if (segment && /^(?:this certificate|presented to|awarded to|program director|project lead|\d|on\b)/i.test(segment)) break;
      if (segment) parts.push(segment);
      if (boundary !== null) break;
      // A single title line is safest when there is no continuation marker.
      if (parts.length && !/(?:and|of|to|in|for|&)$/i.test(segment)) break;
    }
    const subject = parts.join(' ');
    if (meaningful(subject)) return subject;
  }
  return undefined;
}

function organizationOf(lines: readonly string[]): string | undefined {
  for (let index = 0; index < lines.length; index++) {
    const match = /\b(issued|conducted|organized)\s+by\s*(.*)$/i.exec(lines[index]!);
    if (match === null) continue;
    const text = match[2]?.trim() || lines[index + 1] || '';
    const name = text.split(BOUNDARY)[0]!.replace(/[.,;]+$/, '').trim();
    if (meaningful(name)) return `${match[1]!.toLowerCase()} by ${name}`;
  }
  return undefined;
}

function calendarDate(year: number, month: number, day: number): string | undefined {
  if (year < 1000 || year > 9999 || month < 1 || month > 12 || day < 1 || day > 31) return undefined;
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return undefined;
  return date.toISOString().slice(0, 10);
}

function dateOf(lines: readonly string[]): string | undefined {
  const candidates: Array<{ value: string; priority: number }> = [];
  for (const line of lines) {
    const matches: Array<{ value: string | undefined; index: number }> = [];
    for (const match of line.matchAll(new RegExp(`\\b${MONTH_PATTERN}\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?[,]?\\s+(\\d{4})\\b`, 'gi'))) {
      matches.push({ value: calendarDate(Number(match[3]), MONTHS.indexOf(match[1]!.slice(0, 3).toLowerCase()) + 1, Number(match[2])), index: match.index });
    }
    for (const match of line.matchAll(/\b(\d{4})-(\d{2})-(\d{2})\b/g)) {
      matches.push({ value: calendarDate(Number(match[1]), Number(match[2]), Number(match[3])), index: match.index });
    }
    for (const match of line.matchAll(/\b(\d{1,2})\/(\d{1,2})\/(\d{4})\b/g)) {
      const first = Number(match[1]);
      const second = Number(match[2]);
      // Do not silently choose MM/DD over DD/MM for ambiguous numeric dates.
      if (first <= 12 && second <= 12 && first !== second) continue;
      matches.push({
        value: calendarDate(Number(match[3]), first > 12 ? second : first, first > 12 ? first : second),
        index: match.index,
      });
    }
    for (const match of matches) {
      if (match.value === undefined) continue;
      const before = line.slice(0, match.index);
      if (/\b(?:birth|born|expires?|expiry|expiration|valid until)\b/i.test(before)) continue;
      const priority = /\b(?:conducted on|awarded on|issued(?: on)?|dated|on)\s*:?\s*$/i.test(before) ? 2 : 1;
      candidates.push({ value: match.value, priority });
    }
  }
  const priority = Math.max(...candidates.map((candidate) => candidate.priority));
  const best = [...new Set(candidates.filter((candidate) => candidate.priority === priority).map((candidate) => candidate.value))];
  return best.length === 1 ? best[0] : undefined;
}

/** Pure, conservative rules. Suggestions never mutate OCR or supply personal reflections. */
export function suggestDocumentMetadata(
  ocr: OcrText,
  categories: readonly PublicDocumentCategory[],
): MetadataSuggestions {
  // An explicitly reviewed empty string is authoritative, too.
  const lines = linesOf(ocr.reviewedText ?? ocr.rawText ?? '');
  const text = lines.join('\n');

  // 1. Creative Title artifact (section divider)
  const isCreativeTitle = /\b(?:creative\s+title|section\s+divider|divider\s+page|title\s+page\s+artifact)\b/i.test(text);
  if (isCreativeTitle) {
    let category = categories.find((c) => text.toLowerCase().includes(c.name.toLowerCase()) || text.toLowerCase().includes(c.key.toLowerCase()));
    if (!category) {
      category = categories.find((c) => c.folders.some((f) => f.key === 'creative-title'));
    }
    const folder = category?.folders.find((f) => f.key === 'creative-title');
    const titleLine = lines.find((l) => /\bcreative\s+title\b/i.test(l));
    const title = titleLine ? titleLine.replace(/^[\s:;,"“”*#=-]+|[\s:;,"“”*#=-]+$/g, '').trim() : 'Creative Title';
    const documentDate = dateOf(lines);
    return {
      ...(category === undefined ? {} : { categoryKey: category.key }),
      ...(folder === undefined ? {} : { folderKey: folder.key }),
      title: title.length > 0 ? title : 'Creative Title',
      ...(documentDate === undefined ? {} : { documentDate }),
      description: 'Creative Title — Section divider page artifact.',
    };
  }

  // 2. Certificates
  const certificate = CERTIFICATE.exec(text);
  const isCertificate = certificate !== null || (
    /\b(?:presented to|awarded to)\b/i.test(text) &&
    /\b(?:successfully completing|participated in)\b/i.test(text)
  );

  if (isCertificate) {
    const category = categories.find((value) => value.key === 'certificates');
    const folderKey = /\b(?:training|trainings|course|workshop)\b/i.test(text) ? 'trainings'
      : /\b(?:seminar|seminars|webinar)\b/i.test(text) ? 'seminars' : undefined;
    const folder = category?.folders.find((value) => value.key === folderKey);
    const title = subjectOf(lines);
    const documentDate = dateOf(lines);
    const kind = certificate === null ? 'Certificate'
      : `Certificate of ${certificate[1]![0]!.toUpperCase()}${certificate[1]!.slice(1).toLowerCase()}`;
    const organization = organizationOf(lines);
    const description = kind !== undefined && title !== undefined
      ? `${kind} for ${title}${organization === undefined ? '' : `, ${organization}`}.`
      : undefined;
    return {
      ...(category === undefined ? {} : { categoryKey: category.key }),
      ...(folder === undefined ? {} : { folderKey: folder.key }),
      ...(title === undefined ? {} : { title }),
      ...(documentDate === undefined ? {} : { documentDate }),
      ...(description === undefined ? {} : { description }),
    };
  }

  // 2. Curriculum Vitae (CV / Resume / Biodata)
  const isCv = /\b(?:curriculum\s+vitae|resume|biodata)\b/i.test(text) || (
    /\b(?:work\s+experience|employment\s+history|professional\s+experience)\b/i.test(text) &&
    /\b(?:education|academic\s+background)\b/i.test(text) &&
    /\b(?:skills|competencies)\b/i.test(text)
  );
  if (isCv) {
    const category = categories.find((value) => value.key === 'curriculum-vitae');
    const folder = category?.folders.find((value) => value.key === 'curriculum-vitae');
    const cvHeader = lines.find((l) => /^\s*(?:curriculum\s+vitae|resume|bio-?data)\b/i.test(l));
    const title = cvHeader ? cvHeader.replace(/^[\s:;,"“”*#=-]+|[\s:;,"“”*#=-]+$/g, '').trim() : 'Curriculum Vitae';
    const documentDate = dateOf(lines);
    return {
      ...(category === undefined ? {} : { categoryKey: category.key }),
      ...(folder === undefined ? {} : { folderKey: folder.key }),
      title: title.length > 0 ? title : 'Curriculum Vitae',
      ...(documentDate === undefined ? {} : { documentDate }),
      description: 'Curriculum Vitae — Professional resume and qualifications.',
    };
  }

  // 3. Scholastic Record (TOR / Grades)
  const isTor = /\b(?:transcript\s+of\s+records|official\s+transcript|certificate\s+of\s+grades|grade\s+report|scholastic\s+record|report\s+of\s+grades)\b/i.test(text) || (
    /\btor\b/i.test(text) && /\b(?:grades?|units?|semester|gpa|gwa)\b/i.test(text)
  );
  if (isTor) {
    const category = categories.find((value) => value.key === 'scholastic-record');
    const folder = category?.folders.find((value) => value.key === 'unofficial-tor-with-reflections');
    const torHeader = lines.find((l) => /\b(?:transcript\s+of\s+records|certificate\s+of\s+grades|grade\s+report|scholastic\s+record)\b/i.test(l));
    const title = torHeader ? torHeader.replace(/^[\s:;,"“”*#=-]+|[\s:;,"“”*#=-]+$/g, '').trim() : 'Transcript of Records';
    const documentDate = dateOf(lines);
    return {
      ...(category === undefined ? {} : { categoryKey: category.key }),
      ...(folder === undefined ? {} : { folderKey: folder.key }),
      title: title.length > 0 ? title : 'Transcript of Records',
      ...(documentDate === undefined ? {} : { documentDate }),
      description: 'Scholastic Record — Academic transcript and grade records.',
    };
  }

  // 4. College Report (OJT / Practicum / Internship / Narrative)
  const isCollegeReport = /\b(?:college\s+report|practicum\s+report|ojt\s+report|on-the-job\s+training\s+report|internship\s+report|narrative\s+report|terminal\s+report)\b/i.test(text);
  if (isCollegeReport) {
    const category = categories.find((value) => value.key === 'college-report');
    const folder = category?.folders.find((value) => value.key === 'college-report');
    const reportHeader = lines.find((l) => /\b(?:college\s+report|practicum\s+report|ojt\s+report|internship\s+report|narrative\s+report|terminal\s+report)\b/i.test(l));
    const title = reportHeader ? reportHeader.replace(/^[\s:;,"“”*#=-]+|[\s:;,"“”*#=-]+$/g, '').trim() : 'College Report';
    const documentDate = dateOf(lines);
    return {
      ...(category === undefined ? {} : { categoryKey: category.key }),
      ...(folder === undefined ? {} : { folderKey: folder.key }),
      title: title.length > 0 ? title : 'College Report',
      ...(documentDate === undefined ? {} : { documentDate }),
      description: 'College Report — Internship, practicum, or training narrative report.',
    };
  }

  // 5. Accomplishments
  const isThesis = /\b(?:capstone\s+project|undergraduate\s+thesis|thesis\s+project|master'?s\s+thesis)\b/i.test(text);
  const isCaseStudy = /\b(?:case\s+study|case\s+analysis)\b/i.test(text);
  const isAssessment = /\b(?:competency\s+assessment|assessment\s+result|certification\s+assessment)\b/i.test(text);
  const isProject = /\b(?:project\s+report|term\s+project|academic\s+project)\b/i.test(text);

  if (isThesis || isCaseStudy || isAssessment || isProject) {
    const category = categories.find((value) => value.key === 'accomplishments');
    const folderKey = isThesis ? 'thesis-capstone'
      : isCaseStudy ? 'case-studies'
      : isAssessment ? 'assessments'
      : 'projects';
    const folder = category?.folders.find((value) => value.key === folderKey);
    const matchedLine = lines.find((l) => /\b(?:thesis|capstone|case\s+study|assessment|project)\b/i.test(l));
    const title = matchedLine ? matchedLine.replace(/^[\s:;,"“”*#=-]+|[\s:;,"“”*#=-]+$/g, '').trim() : (
      isThesis ? 'Thesis/Capstone Project' : isCaseStudy ? 'Case Study' : isAssessment ? 'Competency Assessment' : 'Academic Project'
    );
    const documentDate = dateOf(lines);
    return {
      ...(category === undefined ? {} : { categoryKey: category.key }),
      ...(folder === undefined ? {} : { folderKey: folder.key }),
      title: title.length > 0 ? title : 'Academic Project',
      ...(documentDate === undefined ? {} : { documentDate }),
      description: `Accomplishments — ${folder?.name ?? 'Project document'}.`,
    };
  }

  // 7. Other Achievements (awards, recognitions, hackathons, competitions)
  const isOtherAchievement = /\b(?:hackathon|extracurricular|competition|innovation\s+challenge|special\s+award|academic\s+award|leadership\s+award|award\b|recognition\b)\b/i.test(text);
  if (isOtherAchievement) {
    const category = categories.find((value) => value.key === 'other-achievements');
    const folder = category?.folders.find((value) => value.key === 'projects');
    const achievementLine = lines.find((l) => /\b(?:hackathon|competition|challenge|extracurricular|award|recognition)\b/i.test(l));
    const title = achievementLine ? achievementLine.replace(/^[\s:;,"“”*#=-]+|[\s:;,"“”*#=-]+$/g, '').trim() : 'Achievement Project';
    const documentDate = dateOf(lines);
    return {
      ...(category === undefined ? {} : { categoryKey: category.key }),
      ...(folder === undefined ? {} : { folderKey: folder.key }),
      title: title.length > 0 ? title : 'Achievement Project',
      ...(documentDate === undefined ? {} : { documentDate }),
      description: 'Other Achievements — Extracurricular, competition, or recognition award.',
    };
  }

  // Fallback title and date if detected on any document
  const fallbackTitle = subjectOf(lines);
  const fallbackDate = dateOf(lines);
  return {
    ...(fallbackTitle === undefined ? {} : { title: fallbackTitle }),
    ...(fallbackDate === undefined ? {} : { documentDate: fallbackDate }),
  };
}
