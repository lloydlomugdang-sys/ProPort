import catalog from '../../config/portfolio-templates.json' with { type: 'json' };
import { CATEGORY_SEEDS } from '../../database/seeds/categories.seed.js';
import { AppError } from '../../common/errors/app-error.js';

export interface PortfolioSectionRule {
  readonly key: string;
  readonly label: string;
  readonly order: number;
  readonly enabled: boolean;
  readonly required: boolean;
  readonly generateCreativeTitle: boolean;
}
export interface PortfolioTemplate {
  readonly id: string;
  readonly name: string;
  readonly version: number;
  readonly status: 'active' | 'inactive';
  readonly includeTableOfContents: boolean;
  readonly sections: readonly PortfolioSectionRule[];
}
export type CreativeTitles = Readonly<Record<string, string>>;
const keys = new Set(CATEGORY_SEEDS.map(c => c.key));
function invalid(): never { throw new Error('Invalid portfolio-template configuration. Review the supported template schema.'); }
function object(value: unknown, fields: readonly string[]): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return invalid();
  const record = value as Record<string, unknown>;
  if (Object.keys(record).length !== fields.length || fields.some(k => !Object.hasOwn(record, k))) return invalid();
  return record;
}
function text(value: unknown, max = 120): string {
  if (typeof value !== 'string' || !value.trim() || value.length > max || unsafeText(value)) return invalid();
  return value.trim();
}
function unsafeText(value: string): boolean { return /[<>]/.test(value) || [...value].some(c => c.charCodeAt(0) < 32); }
function bool(value: unknown): boolean { if (typeof value !== 'boolean') return invalid(); return value; }
function integer(value: unknown, min: number): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < min || value > 1_000_000) return invalid();
  return value;
}

/** Trusted operator data, never executable templates. Validate every version,
 * including inactive ones, then return a frozen, sorted snapshot. */
export function resolvePortfolioTemplate(value: unknown): PortfolioTemplate {
  const { templates } = object(value, ['templates']);
  if (!Array.isArray(templates) || !templates.length || templates.length > 100) return invalid();
  const versions = new Set<string>();
  const normalized = templates.map((entry): PortfolioTemplate => {
    const t = object(entry, ['id', 'name', 'version', 'status', 'includeTableOfContents', 'sections']);
    const id = text(t.id, 80), version = integer(t.version, 1);
    if (!/^[a-z0-9][a-z0-9-]*$/.test(id) || versions.has(`${id}:${version}`)) return invalid();
    versions.add(`${id}:${version}`);
    if (t.status !== 'active' && t.status !== 'inactive') return invalid();
    // Every supported key must be explicit: omission is not an accidental disable.
    if (!Array.isArray(t.sections) || t.sections.length !== keys.size) return invalid();
    const usedKeys = new Set<string>(), orders = new Set<number>();
    const sections = t.sections.map((entry): PortfolioSectionRule => {
      const s = object(entry, ['key', 'label', 'order', 'enabled', 'required', 'generateCreativeTitle']);
      const key = text(s.key), order = integer(s.order, 0);
      if (!keys.has(key) || usedKeys.has(key) || orders.has(order)) return invalid();
      usedKeys.add(key); orders.add(order);
      return Object.freeze({ key, label: text(s.label), order, enabled: bool(s.enabled), required: bool(s.required), generateCreativeTitle: bool(s.generateCreativeTitle) });
    }).sort((a, b) => a.order - b.order);
    return Object.freeze({ id, name: text(t.name), version, status: t.status, includeTableOfContents: bool(t.includeTableOfContents), sections: Object.freeze(sections) });
  });
  const active = normalized.filter(t => t.status === 'active');
  if (active.length !== 1) return invalid();
  return active[0]!;
}

// One institutional scope, resolved once per process. Operators edit the JSON
// catalog and restart; students have read access only. No per-export DB reads.
export const EFFECTIVE_PORTFOLIO_TEMPLATE = resolvePortfolioTemplate(catalog);

export function normalizeCreativeTitles(value: unknown): CreativeTitles {
  const fail = (): never => { throw new AppError(400, 'VALIDATION_ERROR', 'Creative Titles must use supported section keys and plain text of at most 200 characters.'); };
  if (value === undefined) return {};
  if (!value || typeof value !== 'object' || Array.isArray(value)) return fail();
  const entries = Object.entries(value);
  if (entries.some(([key, title]) => !keys.has(key) || typeof title !== 'string' || title.length > 200 || unsafeText(title))) return fail();
  return Object.fromEntries(entries.map(([key, title]) => [key, (title as string).trim()]).filter(([, title]) => title));
}

export const creativeTitlesSchema = {
  type: 'object', additionalProperties: false,
  properties: Object.fromEntries([...keys].map(key => [key, { type: 'string', maxLength: 200 }])),
} as const;
