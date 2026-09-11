import type { FastifyInstance } from 'fastify';
import { afterEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { ConfigurationError, loadConfig } from '../../src/config/env.js';
import { createTestServices } from '../helpers/build-test-app.js';

describe('trusted reverse proxy boundaries', () => {
  let app: FastifyInstance | undefined;

  afterEach(async () => {
    if (app !== undefined) {
      await app.close();
      app = undefined;
    }
  });

  async function requestIp(trustProxy: string | undefined, remoteAddress: string) {
    app = await buildApp({
      config: loadConfig({
        NODE_ENV: 'test',
        LOG_LEVEL: 'silent',
        ...(trustProxy === undefined ? {} : { TRUST_PROXY: trustProxy }),
      }),
      services: createTestServices(),
      connectDatabase: false,
    });
    app.get('/__test/request-ip', (request) => ({ ip: request.ip, ips: request.ips }));

    const response = await app.inject({
      method: 'GET',
      url: '/__test/request-ip',
      remoteAddress,
      headers: { 'x-forwarded-for': '203.0.113.40' },
    });
    expect(response.statusCode).toBe(200);
    return response.json<{ readonly ip: string; readonly ips?: readonly string[] }>();
  }

  it('ignores spoofed forwarding headers when proxy trust is disabled', async () => {
    const result = await requestIp(undefined, '127.0.0.1');
    expect(result.ip).toBe('127.0.0.1');
    expect(result.ips).toBeUndefined();
  });

  it('uses forwarding headers only when the immediate proxy is explicitly trusted', async () => {
    const trusted = await requestIp('127.0.0.1', '127.0.0.1');
    expect(trusted.ip).toBe('203.0.113.40');
    expect(trusted.ips).toEqual(['127.0.0.1', '203.0.113.40']);
  });

  it('ignores forwarding headers received from an untrusted peer', async () => {
    const result = await requestIp('127.0.0.1', '192.0.2.25');
    expect(result.ip).toBe('192.0.2.25');
    expect(result.ips).toEqual(['192.0.2.25']);
  });

  it.each(['true', '*'])('rejects unconditional TRUST_PROXY=%s', (trustProxy) => {
    expect(() =>
      loadConfig({ NODE_ENV: 'test', LOG_LEVEL: 'silent', TRUST_PROXY: trustProxy }),
    ).toThrowError(ConfigurationError);
  });
});
