import type { PublicDocumentCategory } from './document.service.js';

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
  const certificate = CERTIFICATE.exec(text);
  const isCertificate = certificate !== null || (
    /\b(?:presented to|awarded to)\b/i.test(text) &&
    /\b(?:successfully completing|participated in)\b/i.test(text)
  );
  const category = isCertificate ? categories.find((value) => value.key === 'certificates') : undefined;
  const folderKey = /\b(?:training|trainings|course|workshop)\b/i.test(text) ? 'trainings'
    : /\b(?:seminar|seminars|webinar)\b/i.test(text) ? 'seminars' : undefined;
  const folder = category?.folders.find((value) => value.key === folderKey);
  const title = subjectOf(lines);
  const documentDate = dateOf(lines);
  const kind = certificate === null ? (isCertificate ? 'Certificate' : undefined)
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
