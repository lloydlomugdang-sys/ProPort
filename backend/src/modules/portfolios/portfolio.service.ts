import { Types } from 'mongoose';
import { AppError } from '../../common/errors/app-error.js';
import type { PortfolioRecord } from '../../database/repositories/portfolio.repository.js';
import { createRepositories } from '../../database/repositories/index.js';
import type { DatabaseConnection } from '../../infrastructure/database/database-connection.js';

export interface PortfolioInput {
  readonly fullName: string;
  readonly yearAndSection: string;
  readonly schedule: string;
  readonly instructorName: string;
  readonly course: string;
  readonly courseCode: string;
  readonly semesterAndYear: string;
}

export type PortfolioPatch = Readonly<Partial<PortfolioInput>>;

export interface PublicPortfolio extends PortfolioInput {
  readonly id: string;
  readonly createdAt: string;
  readonly updatedAt: string;
}

const FIELD_LIMITS = {
  fullName: 200,
  yearAndSection: 100,
  schedule: 200,
  instructorName: 200,
  course: 200,
  courseCode: 100,
  semesterAndYear: 100,
} as const;

const REQUIRED_FIELDS = new Set<keyof PortfolioInput>([
  'fullName',
  'yearAndSection',
  'schedule',
  'instructorName',
]);

const NOT_FOUND = new AppError(
  404,
  'PORTFOLIO_NOT_FOUND',
  'The requested portfolio was not found.',
);

function normalizeField<Key extends keyof PortfolioInput>(key: Key, value: string): string {
  const normalized = value.trim();
  if (REQUIRED_FIELDS.has(key) && normalized.length === 0) {
    throw new AppError(400, 'VALIDATION_ERROR', 'The request is invalid.', {
      [key]: ['must contain at least one non-whitespace character'],
    });
  }
  if (normalized.length > FIELD_LIMITS[key]) {
    throw new AppError(400, 'VALIDATION_ERROR', 'The request is invalid.', {
      [key]: [`must contain at most ${FIELD_LIMITS[key]} characters`],
    });
  }
  return normalized;
}

function normalizeInput(input: PortfolioInput): PortfolioInput {
  return {
    fullName: normalizeField('fullName', input.fullName),
    yearAndSection: normalizeField('yearAndSection', input.yearAndSection),
    schedule: normalizeField('schedule', input.schedule),
    instructorName: normalizeField('instructorName', input.instructorName),
    course: normalizeField('course', input.course),
    courseCode: normalizeField('courseCode', input.courseCode),
    semesterAndYear: normalizeField('semesterAndYear', input.semesterAndYear),
  };
}

function normalizePatch(input: PortfolioPatch): PortfolioPatch {
  const normalized: Partial<Record<keyof PortfolioInput, string>> = {};
  for (const [key, value] of Object.entries(input) as [keyof PortfolioInput, string][]) {
    normalized[key] = normalizeField(key, value);
  }
  return normalized as PortfolioPatch;
}

function publicPortfolio(portfolio: PortfolioRecord): PublicPortfolio {
  return {
    id: portfolio._id.toString(),
    fullName: portfolio.fullName,
    yearAndSection: portfolio.yearAndSection,
    schedule: portfolio.schedule,
    instructorName: portfolio.instructorName,
    course: portfolio.course,
    courseCode: portfolio.courseCode,
    semesterAndYear: portfolio.semesterAndYear,
    createdAt: portfolio.createdAt.toISOString(),
    updatedAt: portfolio.updatedAt.toISOString(),
  };
}

export class PortfolioService {
  constructor(private readonly database: DatabaseConnection) {}

  async create(ownerId: Types.ObjectId, input: PortfolioInput): Promise<PublicPortfolio> {
    const created = await this.repositories().portfolios.create({
      ownerId,
      ...normalizeInput(input),
    });
    return publicPortfolio(created);
  }

  async list(ownerId: Types.ObjectId): Promise<readonly PublicPortfolio[]> {
    const portfolios = await this.repositories().portfolios.listForOwner(ownerId);
    return portfolios.map(publicPortfolio);
  }

  async get(ownerId: Types.ObjectId, portfolioId: string): Promise<PublicPortfolio> {
    const portfolio = await this.repositories().portfolios.findByIdForOwner(
      ownerId,
      new Types.ObjectId(portfolioId),
    );
    if (portfolio === null) throw NOT_FOUND;
    return publicPortfolio(portfolio);
  }

  async update(
    ownerId: Types.ObjectId,
    portfolioId: string,
    input: PortfolioPatch,
  ): Promise<PublicPortfolio> {
    const portfolio = await this.repositories().portfolios.updateByIdForOwner(
      ownerId,
      new Types.ObjectId(portfolioId),
      normalizePatch(input),
    );
    if (portfolio === null) throw NOT_FOUND;
    return publicPortfolio(portfolio);
  }

  async delete(ownerId: Types.ObjectId, portfolioId: string): Promise<void> {
    const deleted = await this.repositories().portfolios.deleteByIdForOwner(
      ownerId,
      new Types.ObjectId(portfolioId),
    );
    if (!deleted) throw NOT_FOUND;
  }

  private repositories() {
    const connection = this.database.mongooseConnection;
    if (this.database.status !== 'connected' || connection === undefined) {
      throw new AppError(
        503,
        'PORTFOLIO_UNAVAILABLE',
        'Portfolios are temporarily unavailable. Please try again.',
      );
    }
    return createRepositories(connection);
  }
}
