import type { FastifyInstance, FastifyRequest } from 'fastify';
import { Types } from 'mongoose';
import { AppError } from '../../common/errors/app-error.js';
import { successResponse } from '../../common/http/api-response.js';
import type { AppServices } from '../../infrastructure/create-services.js';
import { CurrentUserService } from '../users/user.service.js';
import { CollegeReportService, type SaveCollegeReport } from './college-report.service.js';
import { OFFICIAL_COLLEGE_REPORT } from './college-report.template.js';

const emptyQuery = { type: 'object', additionalProperties: false, properties: {} };
const saveSchema = {
  type: 'object', additionalProperties: false, required: ['questionnaireVersion', 'answers'],
  properties: {
    questionnaireVersion: { const: 2 },
    answers: { type: 'array', maxItems: 62, items: {
      type: 'object', additionalProperties: false, required: ['questionKey', 'value'],
      properties: {
        questionKey: { type: 'string', maxLength: 100 },
        // No type coercion: a quoted rating is NOT a numeric answer.
        value: {}, // Validated against the question's exact type/choices in the service.
      },
    } },
    essay: {}, // Service enforces string/length without AJV converting numbers to text.
  },
};

export async function registerCollegeReportRoutes(app: FastifyInstance, services: AppServices): Promise<void> {
  const users = new CurrentUserService(services.database);
  const reports = new CollegeReportService(services.database);
  const owners = new WeakMap<FastifyRequest, Types.ObjectId>();
  async function authenticate(request: FastifyRequest) {
    let claims: { sub: string; sid: string };
    const unauthorized = () => new AppError(401, 'UNAUTHORIZED', 'Authentication is required to access this resource.');
    try { claims = await request.jwtVerify(); } catch { throw unauthorized(); }
    if (typeof claims.sub !== 'string' || typeof claims.sid !== 'string' ||
        !Types.ObjectId.isValid(claims.sub) || !Types.ObjectId.isValid(claims.sid)) throw unauthorized();
    const identity = await users.authenticate(new Types.ObjectId(claims.sub), new Types.ObjectId(claims.sid));
    owners.set(request, identity.userId);
  }
  app.get('/api/v1/college-report/template', { onRequest: authenticate, schema: { querystring: emptyQuery } },
    async (request, reply) => {
      reply.header('cache-control', 'no-store');
      return successResponse({ template: OFFICIAL_COLLEGE_REPORT }, request.id);
    });
  app.get('/api/v1/college-report/me', { onRequest: authenticate, schema: { querystring: emptyQuery } },
    async (request, reply) => {
      reply.header('cache-control', 'no-store');
      return successResponse(await reports.current(owners.get(request)!), request.id);
    });
  for (const method of ['POST', 'PATCH'] as const) {
    app.route<{ Body: SaveCollegeReport }>({
      method, url: '/api/v1/college-report/me', onRequest: authenticate,
      schema: { body: saveSchema, querystring: emptyQuery },
      handler: async (request, reply) => {
        reply.header('cache-control', 'no-store');
        return successResponse({ report: await reports.save(owners.get(request)!, request.body, method === 'PATCH') }, request.id);
      },
    });
  }
}
