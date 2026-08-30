import type { Db } from 'mongodb';

export interface DatabaseMigration {
  readonly version: number;
  readonly name: string;
  readonly description: string;
  readonly checksum: string;
  up(db: Db): Promise<void>;
}

export interface AppliedMigrationRecord {
  readonly _id: number;
  readonly name: string;
  readonly checksum: string;
  readonly appliedAt: Date;
  readonly executionMs: number;
}
