import { isDeepStrictEqual } from 'node:util';
import type { Db, IndexDescriptionInfo } from 'mongodb';
import { APPLICATION_INDEXES } from './index-definitions.js';

export interface IndexVerificationResult {
  readonly expectedCount: number;
  readonly verifiedCount: number;
  readonly missing: readonly string[];
  readonly mismatched: readonly string[];
  readonly unexpected: readonly string[];
  readonly ok: boolean;
}

function isNamespaceMissing(error: unknown): boolean {
  return typeof error === 'object' && error !== null && 'code' in error && error.code === 26;
}

function keysMatch(actual: IndexDescriptionInfo, expected: Readonly<Record<string, 1 | -1>>): boolean {
  return isDeepStrictEqual(Object.fromEntries(Object.entries(actual.key)), { ...expected });
}

export async function verifyApplicationIndexes(db: Db): Promise<IndexVerificationResult> {
  const missing: string[] = [];
  const mismatched: string[] = [];
  const unexpected: string[] = [];
  let verifiedCount = 0;
  const collections = new Set(APPLICATION_INDEXES.map((definition) => definition.collection));

  for (const collectionName of collections) {
    const expected = APPLICATION_INDEXES.filter(
      (definition) => definition.collection === collectionName,
    );
    let actual: IndexDescriptionInfo[];
    try {
      actual = await db.collection(collectionName).listIndexes().toArray();
    } catch (error) {
      if (!isNamespaceMissing(error)) {
        throw error;
      }
      missing.push(...expected.map((definition) => definition.name));
      continue;
    }

    for (const definition of expected) {
      const found = actual.find((index) => index.name === definition.name);
      if (found === undefined) {
        missing.push(definition.name);
        continue;
      }
      const optionsMatch =
        Boolean(found.unique) === Boolean(definition.unique) &&
        (found.expireAfterSeconds ?? undefined) === definition.expireAfterSeconds;
      if (!keysMatch(found, definition.key) || !optionsMatch) {
        mismatched.push(definition.name);
        continue;
      }
      verifiedCount += 1;
    }

    const expectedNames = new Set(expected.map((definition) => definition.name));
    unexpected.push(
      ...actual
        .filter((index) => index.name !== '_id_' && !expectedNames.has(index.name ?? ''))
        .map((index) => `${collectionName}.${index.name ?? 'unnamed'}`),
    );
  }

  return {
    expectedCount: APPLICATION_INDEXES.length,
    verifiedCount,
    missing,
    mismatched,
    unexpected,
    ok: missing.length === 0 && mismatched.length === 0,
  };
}
