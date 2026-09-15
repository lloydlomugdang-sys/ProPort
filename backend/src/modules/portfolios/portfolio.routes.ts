import type { FastifyInstance, FastifyRequest } from 'fastify';
import { Types } from 'mongoose';
import { AppError } from '../../common/errors/app-error.js';
import { successResponse } from '../../common/http/api-response.js';
import type { AppServices } from '../../infrastructure/create-services.js';
import { CurrentUserService, type CurrentUserIdentity } from '../users/user.service.js';
import {
  portfolioCreateBodySchema,
  portfolioDeleteResponseSchema,
  portfolioListResponseSchema,
  portfolioPatchBodySchema,
  portfolioPathParamsSchema,
  portfolioQuerySchema,
  portfolioResponseSchema,
} from './portfolio.schemas.js';
import { PortfolioService, type PortfolioInput, type PortfolioPatch } from './portfolio.service.js';

interface AccessTokenClaims {
  readonly sub: string;
  readonly sid: string;
}

interface PortfolioParams {
  readonly portfolioId: string;
}

const UNAUTHORIZED = new AppError(
  401,
  'UNAUTHORIZED',
  'Authentication is required to access this resource.',
);

function objectId(value: unknown): Types.ObjectId {
  if (typeof value !== 'string' || !Types.ObjectId.isValid(value)) {
    throw UNAUTHORIZED;
  }
  return new Types.ObjectId(value);
}

export async function registerPortfolioRoutes(
  app: FastifyInstance,
  services: AppServices,
): Promise<void> {
  const currentUsers = new CurrentUserService(services.database);
  const portfolios = new PortfolioService(services.database, services.storage);
  const identities = new WeakMap<FastifyRequest, CurrentUserIdentity>();

  async function requireCurrentUser(request: FastifyRequest): Promise<void> {
    let claims: AccessTokenClaims;
    try {
      claims = await request.jwtVerify<AccessTokenClaims>();
    } catch {
      throw UNAUTHORIZED;
    }
    const identity = await currentUsers.authenticate(objectId(claims.sub), objectId(claims.sid));
    identities.set(request, identity);
  }

  function ownerIdFor(request: FastifyRequest): Types.ObjectId {
    const identity = identities.get(request);
    if (identity === undefined) throw UNAUTHORIZED;
    return identity.userId;
  }

  app.get(
    '/api/v1/portfolios',
    {
      onRequest: requireCurrentUser,
      schema: {
        querystring: portfolioQuerySchema,
        response: { 200: portfolioListResponseSchema },
      },
    },
    async (request) =>
      successResponse({ portfolios: await portfolios.list(ownerIdFor(request)) }, request.id),
  );

  app.post<{ Body: PortfolioInput }>(
    '/api/v1/portfolios',
    {
      onRequest: requireCurrentUser,
      schema: {
        body: portfolioCreateBodySchema,
        querystring: portfolioQuerySchema,
        response: { 201: portfolioResponseSchema },
      },
    },
    async (request, reply) => {
      const portfolio = await portfolios.create(ownerIdFor(request), request.body);
      return reply.status(201).send(successResponse({ portfolio }, request.id));
    },
  );

  app.get<{ Params: PortfolioParams }>(
    '/api/v1/portfolios/:portfolioId',
    {
      onRequest: requireCurrentUser,
      schema: {
        params: portfolioPathParamsSchema,
        querystring: portfolioQuerySchema,
        response: { 200: portfolioResponseSchema },
      },
    },
    async (request) =>
      successResponse(
        { portfolio: await portfolios.get(ownerIdFor(request), request.params.portfolioId) },
        request.id,
      ),
  );

  app.patch<{ Params: PortfolioParams; Body: PortfolioPatch }>(
    '/api/v1/portfolios/:portfolioId',
    {
      onRequest: requireCurrentUser,
      schema: {
        params: portfolioPathParamsSchema,
        body: portfolioPatchBodySchema,
        querystring: portfolioQuerySchema,
        response: { 200: portfolioResponseSchema },
      },
    },
    async (request) =>
      successResponse(
        {
          portfolio: await portfolios.update(
            ownerIdFor(request),
            request.params.portfolioId,
            request.body,
          ),
        },
        request.id,
      ),
  );

  app.delete<{ Params: PortfolioParams }>(
    '/api/v1/portfolios/:portfolioId',
    {
      onRequest: requireCurrentUser,
      schema: {
        params: portfolioPathParamsSchema,
        querystring: portfolioQuerySchema,
        response: { 200: portfolioDeleteResponseSchema },
      },
    },
    async (request) => {
      await portfolios.delete(ownerIdFor(request), request.params.portfolioId);
      return successResponse(
        { status: 'deleted' as const, portfolioId: request.params.portfolioId },
        request.id,
      );
    },
  );

  app.get<{ Params: PortfolioParams }>(
    '/api/v1/portfolios/:portfolioId/export/pdf',
    {
      onRequest: requireCurrentUser,
      schema: {
        params: portfolioPathParamsSchema,
        querystring: portfolioQuerySchema,
      },
    },
    async (request, reply) => {
      const { fileName, pdfBytes } = await portfolios.exportPdf(ownerIdFor(request), {
        portfolioId: request.params.portfolioId,
      });
      return reply
        .type('application/pdf')
        .header('content-length', pdfBytes.length)
        .header('content-disposition', `attachment; filename="${fileName}"`)
        .send(pdfBytes);
    },
  );

  app.post<{ Body: PortfolioInput }>(
    '/api/v1/portfolios/export/pdf',
    {
      onRequest: requireCurrentUser,
      schema: {
        body: portfolioCreateBodySchema,
        querystring: portfolioQuerySchema,
      },
    },
    async (request, reply) => {
      const { fileName, pdfBytes } = await portfolios.exportPdf(ownerIdFor(request), request.body);
      return reply
        .type('application/pdf')
        .header('content-length', pdfBytes.length)
        .header('content-disposition', `attachment; filename="${fileName}"`)
        .send(pdfBytes);
    },
  );
}
