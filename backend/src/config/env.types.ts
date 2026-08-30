export type NodeEnvironment = 'development' | 'test';
export type LogLevel = 'fatal' | 'error' | 'warn' | 'info' | 'debug' | 'trace' | 'silent';
export type DatabaseDriver = 'mock' | 'mongodb';
export type StorageDriver = 'local';
export type EmailDriver = 'console';

export interface AppConfig {
  readonly nodeEnv: NodeEnvironment;
  readonly host: string;
  readonly port: number;
  readonly logLevel: LogLevel;
  readonly databaseDriver: DatabaseDriver;
  readonly mongodbUri?: string;
  readonly mongodbDbName: string;
  readonly storageDriver: StorageDriver;
  readonly localStoragePath: string;
  readonly emailDriver: EmailDriver;
  readonly readyCheckTimeoutMs: number;
}
