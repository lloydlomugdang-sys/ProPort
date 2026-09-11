import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildTestApp } from '../helpers/build-test-app.js';

const apps: FastifyInstance[] = [];

afterEach(async () => {
  await Promise.all(apps.splice(0).map(async (app) => app.close()));
});

describe('health routes', () => {
  it('returns process health without checking dependencies', async () => {
    const app = await buildTestApp({ database: { status: 'down' } });
    apps.push(app);

    const response = await app.inject({ method: 'GET', url: '/health' });
    const body = response.json();

    expect(response.statusCode).toBe(200);
    expect(body.data).toMatchObject({ status: 'ok', service: 'gradport-api' });
    expect(body.meta.requestId).toBe(response.headers['x-request-id']);
    expect(body.data.timestamp).toEqual(expect.any(String));
  });

  it('generates a unique UUID request ID for every request', async () => {
    const app = await buildTestApp();
    apps.push(app);

    const first = await app.inject({ method: 'GET', url: '/health' });
    const second = await app.inject({ method: 'GET', url: '/health' });
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

    expect(first.headers['x-request-id']).toMatch(uuid);
    expect(second.headers['x-request-id']).toMatch(uuid);
    expect(first.headers['x-request-id']).not.toBe(second.headers['x-request-id']);
  });

  it('reports explicit mock/local adapters as ready', async () => {
    const app = await buildTestApp();
    apps.push(app);

    const response = await app.inject({ method: 'GET', url: '/ready' });
    const body = response.json();

    expect(response.statusCode).toBe(200);
    expect(body.data).toMatchObject({
      status: 'ready',
      service: 'gradport-api',
      checks: { database: 'mock', storage: 'local', email: 'console' },
    });
  });

  it('reports a healthy SMTP adapter as ready without changing the response shape', async () => {
    const app = await buildTestApp({ email: { status: 'up' } });
    apps.push(app);

    const response = await app.inject({ method: 'GET', url: '/ready' });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({
      data: {
        status: 'ready',
        checks: { database: 'mock', storage: 'local', email: 'up' },
      },
    });
  });

  it('returns the standard 503 response when a dependency is down', async () => {
    const app = await buildTestApp({ database: { status: 'down', detail: 'test failure' } });
    apps.push(app);

    const response = await app.inject({ method: 'GET', url: '/ready' });
    const body = response.json();

    expect(response.statusCode).toBe(503);
    expect(body).toEqual({
      error: {
        code: 'SERVICE_NOT_READY',
        message: 'One or more required services are unavailable.',
        requestId: response.headers['x-request-id'],
        details: { database: 'down', storage: 'local', email: 'console' },
      },
    });
  });

  it('sanitizes unexpected errors', async () => {
    const app = await buildTestApp();
    apps.push(app);
    app.get('/explode', async () => {
      throw new Error('sensitive implementation detail');
    });

    const response = await app.inject({ method: 'GET', url: '/explode' });
    const bodyText = response.body;

    expect(response.statusCode).toBe(500);
    expect(response.json()).toEqual({
      error: {
        code: 'INTERNAL_ERROR',
        message: 'An unexpected error occurred.',
        requestId: response.headers['x-request-id'],
      },
    });
    expect(bodyText).not.toContain('sensitive implementation detail');
  });
});
