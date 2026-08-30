import mongoose, { type Connection } from 'mongoose';
import type { ServiceHealth } from '../../common/types/service-health.js';
import { registerModels } from './model-registry.js';
import type { DatabaseConnection, DatabaseStatus } from './database-connection.js';

export interface MongooseDatabaseOptions {
  readonly uri: string;
  readonly databaseName: string;
  readonly serverSelectionTimeoutMs: number;
  readonly connectTimeoutMs: number;
  readonly maxPoolSize: number;
}

export class MongooseDatabaseConnection implements DatabaseConnection {
  private readonly connection: Connection;
  private currentStatus: DatabaseStatus = 'disconnected';

  constructor(private readonly options: MongooseDatabaseOptions) {
    this.connection = mongoose.createConnection();
  }

  get status(): DatabaseStatus {
    return this.currentStatus;
  }

  get mongooseConnection(): Connection {
    return this.connection;
  }

  async connect(): Promise<void> {
    if (this.currentStatus === 'connected') {
      return;
    }

    this.currentStatus = 'connecting';
    try {
      await this.connection.openUri(this.options.uri, {
        dbName: this.options.databaseName,
        autoIndex: false,
        serverApi: { version: '1', strict: true, deprecationErrors: true },
        serverSelectionTimeoutMS: this.options.serverSelectionTimeoutMs,
        connectTimeoutMS: this.options.connectTimeoutMs,
        maxPoolSize: this.options.maxPoolSize,
        minPoolSize: 0,
      });
      registerModels(this.connection);
      this.currentStatus = 'connected';
    } catch (error) {
      this.currentStatus = 'error';
      throw error;
    }
  }

  async disconnect(): Promise<void> {
    if (this.currentStatus === 'disconnected') {
      return;
    }
    this.currentStatus = 'disconnecting';
    try {
      await this.connection.close();
    } finally {
      this.currentStatus = 'disconnected';
    }
  }

  async ping(): Promise<ServiceHealth> {
    if (this.currentStatus !== 'connected' || this.connection.db === undefined) {
      return { status: 'down', detail: `MongoDB connection is ${this.currentStatus}.` };
    }

    try {
      await this.connection.db.admin().ping();
      return { status: 'up' };
    } catch {
      return { status: 'down', detail: 'MongoDB ping failed.' };
    }
  }
}
