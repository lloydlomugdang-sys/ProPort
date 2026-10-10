import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { Types } from 'mongoose';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config/env.js';
import { runMigrations } from '../../src/database/migrations/migration-runner.js';
import { seedReportTemplate } from '../../src/database/seeds/report-template.seed.js';
import { registerModels } from '../../src/infrastructure/database/model-registry.js';
import { CollegeReportService } from '../../src/modules/college-report/college-report.service.js';
import { PortfolioGeneratorService } from '../../src/modules/portfolios/portfolio-generator.service.js';
import { createTestServices } from '../helpers/build-test-app.js';
import { createDisposableMongoDatabase, type DisposableMongoDatabase } from '../helpers/disposable-mongodb.js';
import { portfolioMemoryStorage, PORTFOLIO_TEST_INFO } from '../helpers/portfolio-fixtures.js';

let disposable: DisposableMongoDatabase;
let app: FastifyInstance;
let owner: Types.ObjectId;
let other: Types.ObjectId;
let headers: { authorization: string };
let otherHeaders: { authorization: string };
const path = '/api/v1/college-report';

describe('College Report authenticated persistence (disposable local database only)', () => {
  beforeAll(async () => {
    disposable = await createDisposableMongoDatabase();
    await runMigrations(disposable.connection.db!);
    await seedReportTemplate(disposable.connection);
    app = await buildApp({ config: loadConfig({ NODE_ENV: 'test', LOG_LEVEL: 'silent' }),
      services: { ...createTestServices(), database: disposable.database }, connectDatabase: false });
    const models = registerModels(disposable.connection);
    async function account() {
      const user = await models.User.create({ email: `${randomUUID()}@example.edu`, firstName: 'Student', lastName: 'Fixture', passwordHash: 'test-hash-only', status: 'active', emailVerifiedAt: new Date() });
      const session = await models.Session.create({ userId: user._id, familyId: randomUUID(), refreshTokenHash: randomUUID(), expiresAt: new Date(Date.now() + 3600000) });
      return { id: user._id, headers: { authorization: `Bearer ${app.jwt.sign({ sub: user._id.toString(), sid: session._id.toString() })}` } };
    }
    const first = await account(); const second = await account();
    owner = first.id; headers = first.headers;
    other = second.id; otherHeaders = second.headers;
  }, 120000);

  afterAll(async () => {
    if (disposable) await disposable.stop();
    if (app) await app.close();
  }, 120000);

  it('rejects unauthenticated template, read and write routes', async () => {
    for (const [method, url] of [['GET', `${path}/template`], ['GET', `${path}/me`], ['POST', `${path}/me`], ['PATCH', `${path}/me`]] as const) {
      const response = await app.inject({ method, url });
      expect(response.statusCode).toBe(401);
      expect(response.json().error.code).toBe('UNAUTHORIZED');
    }
  });

  it('serves complete versioned template and empty current response without internal IDs', async () => {
    const response = await app.inject({ method: 'GET', url: `${path}/template`, headers });
    expect(response.statusCode).toBe(200);
    expect(response.headers['cache-control']).toBe('no-store');
    expect(response.json().data.template.sections.map((s: { questions: unknown[] }) => s.questions.length)).toEqual([19, 5, 5, 1, 7, 4, 14, 5, 1, 1]);
    const current = await app.inject({ method: 'GET', url: `${path}/me`, headers });
    expect(current.json().data).toEqual({ report: null, templateReady: true, hasLegacyReport: false });
  });

  it('saves partial typed answers, persists 62 including nulls and fetches exact student essay', async () => {
    const response = await app.inject({ method: 'POST', url: `${path}/me`, headers, payload: {
      questionnaireVersion: 2, answers: [{ questionKey: 's04-q01', value: 7 }, { questionKey: 's01-q01', value: 'often' }], essay: 'Private student essay.',
    } });
    expect(response.statusCode, response.body).toBe(200);
    const read = await app.inject({ method: 'GET', url: `${path}/me`, headers });
    expect(read.json().data.report).toEqual(response.json().data.report);
    const report = read.json().data.report;
    expect(Object.keys(report).sort()).toEqual(['answers', 'essay', 'questionnaireVersion', 'updatedAt']);
    expect(report.answers).toHaveLength(62);
    expect(report.answers.filter((a: { value: unknown }) => a.value === null)).toHaveLength(60);
    const raw = await registerModels(disposable.connection).CollegeReport.findOne({ ownerId: owner }).lean();
    expect(raw!.answers.find((a) => a.questionKey === 's04-q01')!.value).toBe(7);
    expect(raw!.academicYear).toBe('current');
    expect(raw!.questionnaireVersion).toBe(2);
  });

  it('patches and clears answers without mapping unrelated items or discarding essay', async () => {
    const response = await app.inject({ method: 'PATCH', url: `${path}/me`, headers, payload: { questionnaireVersion: 2, answers: [{ questionKey: 's04-q01', value: null }, { questionKey: 's02-q01', value: 'once' }] } });
    expect(response.statusCode).toBe(200);
    const report = response.json().data.report;
    expect(report.answers.find((a: { questionKey: string }) => a.questionKey === 's04-q01').value).toBeNull();
    expect(report.answers.find((a: { questionKey: string }) => a.questionKey === 's01-q01').value).toBe('often');
    expect(report.essay).toBe('Private student essay.');
  });

  it('isolates other accounts, rejects client ownership fields and exports only the authenticated owner report', async () => {
    const response = await app.inject({ method: 'GET', url: `${path}/me`, headers: otherHeaders });
    expect(response.json().data.report).toBeNull();
    for (const query of [`?ownerId=${owner}`, `?userId=${owner}`, `?templateId=${owner}`]) {
      expect((await app.inject({ method: 'GET', url: `${path}/me${query}`, headers: otherHeaders })).statusCode).toBe(400);
    }
    const saved = await app.inject({ method: 'POST', url: `${path}/me`, headers: otherHeaders, payload: { questionnaireVersion: 2, answers: [], essay: 'Other account private reflection.' } });
    expect(saved.statusCode).toBe(200);
    const generator = new PortfolioGeneratorService(disposable.database, portfolioMemoryStorage());
    const bytes = await generator.generate(owner, PORTFOLIO_TEST_INFO);
    const task = getDocument({ data: new Uint8Array(bytes), useSystemFonts: true });
    try {
      const pdf = await task.promise;
      const text = [];
      for (let i = 1; i <= pdf.numPages; i++) text.push((await (await pdf.getPage(i)).getTextContent()).items.filter((i) => 'str' in i).map((i) => i.str).join(' '));
      expect(text.join(' ')).toContain('Private student essay.');
      expect(text.join(' ')).not.toContain('Other account private reflection.');
    } finally { await task.destroy(); }
    expect(await registerModels(disposable.connection).CollegeReport.countDocuments({ ownerId: other })).toBe(1);
  });

  it.each([
    { questionnaireVersion: 1, answers: [] }, { questionnaireVersion: '2', answers: [] },
    { questionnaireVersion: 2, answers: [], ownerId: 'someone' },
    { questionnaireVersion: 2, answers: [], essay: 7 },
    { questionnaireVersion: 2, answers: [], essay: 'x'.repeat(10001) },
    { questionnaireVersion: 2, answers: [{ questionKey: 'unknown', value: null }] },
    { questionnaireVersion: 2, answers: [{ questionKey: 's04-q01', value: '7' }] },
    { questionnaireVersion: 2, answers: [{ questionKey: 's09-q01', value: 7 }] },
    { questionnaireVersion: 2, answers: [{ questionKey: 's01-q01', value: false }] },
    { questionnaireVersion: 2, answers: [{ questionKey: 's01-q01', value: 'often' }, { questionKey: 's01-q01', value: 'never' }] },
    { questionnaireVersion: 2, answers: [null] },
    { questionnaireVersion: 2, answers: [{ questionKey: 's01-q01' }] },
    { questionnaireVersion: 2, answers: [{ questionKey: 's01-q01', value: { unexpected: 'data' } }] },
    { questionnaireVersion: 2, answers: Array.from({ length: 63 }, () => ({ questionKey: 's01-q01', value: null })) },
  ])('rejects invalid payload without echoing personal values (%#)', async (payload) => {
    const response = await app.inject({ method: 'POST', url: `${path}/me`, headers, payload });
    expect(response.statusCode).toBe(400);
    expect(response.json().error.code).toBe('VALIDATION_ERROR');
    expect(response.json().error.requestId).toEqual(response.headers['x-request-id']);
  });

  it('retains six-question legacy data separately and detects it without reinterpreting answers', async () => {
    const { CollegeReport, ReportTemplate } = registerModels(disposable.connection);
    const legacy = await ReportTemplate.findOne({ key: 'college-engagement-v1', version: 1 });
    const input = { ownerId: owner, templateId: legacy!._id, academicYear: '2025-2026', answers: [{ questionKey: 'contributed-to-class-discussions', value: 'never' }] };
    const record = await CollegeReport.create(input);
    const current = await new CollegeReportService(disposable.database).current(owner);
    expect(current.hasLegacyReport).toBe(true);
    expect(current.report!.answers.find((a) => a.questionKey === 's01-q01')!.value).toBe('often');
    expect((await CollegeReport.findById(record._id))!.answers[0]!.value).toBe('never');
    expect((await new CollegeReportService(disposable.database).current(other)).hasLegacyReport).toBe(false);
  });

  it('replaces a snapshot without defaults and keeps concurrent saves on one owner/template record', async () => {
    const payload = { questionnaireVersion: 2, answers: [] };
    const response = await app.inject({ method: 'POST', url: `${path}/me`, headers, payload });
    expect(response.statusCode).toBe(200);
    expect(response.json().data.report.answers.every((a: { value: unknown }) => a.value === null)).toBe(true);
    expect(response.json().data.report.essay).toBe('');
    const concurrent = await Promise.all(['First explicit draft', 'Second explicit draft'].map((essay) => app.inject({ method: 'POST', url: `${path}/me`, headers, payload: { ...payload, essay } })));
    expect(concurrent.map((r) => r.statusCode)).toEqual([200, 200]);
    const records = await registerModels(disposable.connection).CollegeReport.find({ ownerId: owner, academicYear: 'current' }).lean();
    expect(records).toHaveLength(1);
    expect(['First explicit draft', 'Second explicit draft']).toContain(records[0]!.essay);
  });

  it('rejects a revoked session even with a valid signed access token', async () => {
    await registerModels(disposable.connection).Session.updateMany({ userId: other }, { $set: { revokedAt: new Date() } });
    for (const url of [`${path}/template`, `${path}/me`]) {
      const response = await app.inject({ method: 'GET', url, headers: otherHeaders });
      expect(response.statusCode).toBe(401);
      expect(response.json().error.code).toBe('UNAUTHORIZED');
    }
  });

  it('sanitizes database errors and refuses missing-template saves rather than inventing success', async () => {
    const models = registerModels(disposable.connection);
    const find = vi.spyOn(models.ReportTemplate, 'findOne').mockImplementationOnce(() => { throw new Error('provider detail private response'); });
    const response = await app.inject({ method: 'GET', url: `${path}/me`, headers });
    expect(response.statusCode).toBe(503);
    expect(response.body).not.toMatch(/provider detail|private response/);
    find.mockRestore();
    // Disposable database only: simulate a deployment before its additive seed.
    await models.ReportTemplate.deleteOne({ key: 'college-report', version: 2 });
    const missing = await app.inject({ method: 'POST', url: `${path}/me`, headers, payload: { questionnaireVersion: 2, answers: [] } });
    expect(missing.statusCode).toBe(503);
    expect(missing.json().error.code).toBe('COLLEGE_REPORT_UNAVAILABLE');
  });
});
