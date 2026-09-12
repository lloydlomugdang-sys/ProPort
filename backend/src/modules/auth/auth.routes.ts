import fastifyJwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import type { FastifyInstance, FastifyReply } from 'fastify';
import { AppError } from '../../common/errors/app-error.js';
import { successResponse } from '../../common/http/api-response.js';
import type { AppConfig } from '../../config/env.types.js';
import type { AppServices } from '../../infrastructure/create-services.js';
import {
  emailCodeBodySchema,
  emailOnlyBodySchema,
  loginBodySchema,
  refreshTokenBodySchema,
  registerBodySchema,
  registerResponseSchema,
  resetGrantResponseSchema,
  resetPasswordBodySchema,
  sessionResponseSchema,
  statusResponseSchema,
  userResponseSchema,
} from './auth.schemas.js';
import { AuthService } from './auth.service.js';

interface RegisterBody {
  readonly firstName: string;
  readonly lastName: string;
  readonly email: string;
  readonly password: string;
}

interface EmailCodeBody {
  readonly email: string;
  readonly code: string;
}

interface EmailOnlyBody {
  readonly email: string;
}

interface LoginBody {
  readonly email: string;
  readonly password: string;
}

interface ResetPasswordBody {
  readonly resetToken: string;
  readonly newPassword: string;
}

interface RefreshTokenBody {
  readonly refreshToken: string;
}

export interface AuthRoutesOptions {
  readonly config: AppConfig;
  readonly services: AppServices;
}

interface RateLimitBucket {
  count: number;
  resetAt: number;
}

class FixedWindowLimiter {
  private readonly buckets = new Map<string, RateLimitBucket>();

  check(key: string, maximum: number): { allowed: boolean; retryAfter: number } {
    const now = Date.now();
    const existing = this.buckets.get(key);
    if (existing === undefined || existing.resetAt <= now) {
      return { allowed: true, retryAfter: 0 };
    }
    return {
      allowed: existing.count < maximum,
      retryAfter: Math.max(1, Math.ceil((existing.resetAt - now) / 1000)),
    };
  }

  consume(key: string, maximum: number, windowMs: number): { allowed: boolean; retryAfter: number } {
    const now = Date.now();
    const existing = this.buckets.get(key);
    const bucket =
      existing === undefined || existing.resetAt <= now
        ? { count: 0, resetAt: now + windowMs }
        : existing;
    bucket.count += 1;
    this.buckets.set(key, bucket);
    this.prune(now);
    return {
      allowed: bucket.count <= maximum,
      retryAfter: Math.max(1, Math.ceil((bucket.resetAt - now) / 1000)),
    };
  }

  clear(key: string): void {
    this.buckets.delete(key);
  }

  private prune(now: number): void {
    if (this.buckets.size <= 10_000) {
      return;
    }
    for (const [key, bucket] of this.buckets) {
      if (bucket.resetAt <= now) {
        this.buckets.delete(key);
      }
    }
  }
}

function normalizedEmail(email: string): string {
  return email.trim().toLowerCase();
}

function throwAccountRateLimit(reply: FastifyReply, retryAfter: number): never {
  void reply.header('retry-after', String(retryAfter));
  throw new AppError(429, 'RATE_LIMITED', 'Too many requests. Please try again later.');
}

export async function registerAuthRoutes(
  app: FastifyInstance,
  options: AuthRoutesOptions,
): Promise<void> {
  await app.register(fastifyJwt, {
    secret: options.config.authJwtSecret,
    sign: {
      algorithm: 'HS256',
      expiresIn: options.config.authAccessTokenTtlSeconds,
      iss: options.config.authJwtIssuer,
      aud: options.config.authJwtAudience,
    },
    verify: {
      algorithms: ['HS256'],
      allowedIss: options.config.authJwtIssuer,
      allowedAud: options.config.authJwtAudience,
      requiredClaims: ['sub', 'sid', 'iat', 'exp'],
    },
  });
  await app.register(rateLimit, {
    global: false,
    hook: 'preHandler',
    cache: 10_000,
    errorResponseBuilder: () =>
      new AppError(429, 'RATE_LIMITED', 'Too many requests. Please try again later.'),
  });

  const auth = new AuthService(
    options.config,
    options.services.database,
    options.services.email,
    { sign: (payload) => app.jwt.sign(payload) },
    app.log,
  );
  const accountLimiter = new FixedWindowLimiter();
  const acceptedResponseSchema = statusResponseSchema('accepted');
  const passwordResetResponseSchema = statusResponseSchema('passwordReset');
  const loggedOutResponseSchema = statusResponseSchema('loggedOut');

  app.post<{ Body: RegisterBody }>(
    '/api/v1/auth/register',
    {
      schema: { body: registerBodySchema, response: { 201: registerResponseSchema } },
      config: {
        rateLimit: { max: 5, timeWindow: '1 hour', groupId: 'auth-register-ip' },
      },
    },
    async (request, reply) => {
      const result = await auth.register(request.body);
      return reply.status(201).send(successResponse(result, request.id));
    },
  );

  app.post<{ Body: EmailCodeBody }>(
    '/api/v1/auth/email-verification/verify',
    {
      schema: { body: emailCodeBodySchema, response: { 200: userResponseSchema } },
    },
    async (request) =>
      successResponse(
        { user: await auth.verifyEmail(request.body.email, request.body.code) },
        request.id,
      ),
  );

  app.post<{ Body: EmailOnlyBody }>(
    '/api/v1/auth/email-verification/resend',
    {
      schema: { body: emailOnlyBodySchema, response: { 202: acceptedResponseSchema } },
      config: {
        rateLimit: { max: 10, timeWindow: '1 hour', groupId: 'auth-delivery-ip' },
      },
    },
    async (request, reply) => {
      const key = `verification:${normalizedEmail(request.body.email)}`;
      const account = accountLimiter.consume(key, 3, 60 * 60 * 1000);
      if (!account.allowed) {
        throwAccountRateLimit(reply, account.retryAfter);
      }
      await auth.resendEmailVerification(request.body.email);
      return reply.status(202).send(successResponse({ status: 'accepted' as const }, request.id));
    },
  );

  app.post<{ Body: LoginBody }>(
    '/api/v1/auth/login',
    {
      schema: { body: loginBodySchema, response: { 200: sessionResponseSchema } },
      config: {
        rateLimit: { max: 10, timeWindow: '15 minutes', groupId: 'auth-login-ip' },
      },
    },
    async (request, reply) => {
      const key = `login:${normalizedEmail(request.body.email)}`;
      const current = accountLimiter.check(key, 5);
      if (!current.allowed) {
        throwAccountRateLimit(reply, current.retryAfter);
      }
      try {
        const result = await auth.login(request.body.email, request.body.password);
        accountLimiter.clear(key);
        return successResponse(result, request.id);
      } catch (error) {
        if (error instanceof AppError && error.code === 'INVALID_CREDENTIALS') {
          const failed = accountLimiter.consume(key, 5, 15 * 60 * 1000);
          if (!failed.allowed) {
            throwAccountRateLimit(reply, failed.retryAfter);
          }
        }
        throw error;
      }
    },
  );

  app.post<{ Body: EmailOnlyBody }>(
    '/api/v1/auth/password-reset/request',
    {
      schema: { body: emailOnlyBodySchema, response: { 202: acceptedResponseSchema } },
      config: {
        rateLimit: { max: 10, timeWindow: '1 hour', groupId: 'auth-delivery-ip' },
      },
    },
    async (request, reply) => {
      const key = `reset:${normalizedEmail(request.body.email)}`;
      const account = accountLimiter.consume(key, 3, 60 * 60 * 1000);
      if (!account.allowed) {
        throwAccountRateLimit(reply, account.retryAfter);
      }
      await auth.requestPasswordReset(request.body.email);
      return reply.status(202).send(successResponse({ status: 'accepted' as const }, request.id));
    },
  );

  app.post<{ Body: EmailCodeBody }>(
    '/api/v1/auth/password-reset/verify',
    {
      schema: { body: emailCodeBodySchema, response: { 200: resetGrantResponseSchema } },
    },
    async (request) =>
      successResponse(
        await auth.verifyPasswordReset(request.body.email, request.body.code),
        request.id,
      ),
  );

  app.post<{ Body: ResetPasswordBody }>(
    '/api/v1/auth/password-reset/complete',
    {
      schema: { body: resetPasswordBodySchema, response: { 200: passwordResetResponseSchema } },
    },
    async (request) => {
      await auth.completePasswordReset(request.body.resetToken, request.body.newPassword);
      return successResponse({ status: 'passwordReset' as const }, request.id);
    },
  );

  app.post<{ Body: RefreshTokenBody }>(
    '/api/v1/auth/refresh',
    {
      schema: { body: refreshTokenBodySchema, response: { 200: sessionResponseSchema } },
      config: {
        rateLimit: { max: 30, timeWindow: '1 minute', groupId: 'auth-refresh-ip' },
      },
    },
    async (request) => successResponse(await auth.refresh(request.body.refreshToken), request.id),
  );

  app.post<{ Body: RefreshTokenBody }>(
    '/api/v1/auth/logout',
    {
      schema: { body: refreshTokenBodySchema, response: { 200: loggedOutResponseSchema } },
    },
    async (request) => {
      await auth.logout(request.body.refreshToken);
      return successResponse({ status: 'loggedOut' as const }, request.id);
    },
  );
}
