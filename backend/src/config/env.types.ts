export type NodeEnvironment = 'development' | 'test';
export type LogLevel = 'fatal' | 'error' | 'warn' | 'info' | 'debug' | 'trace' | 'silent';
export type DatabaseDriver = 'mock' | 'mongodb';
export type DatabaseEnvironment = 'development' | 'test';
export type DatabaseAccessMode = 'runtime' | 'maintenance';
export type StorageDriver = 'local';
export type EmailDriver = 'console';

export interface AppConfig {
  readonly nodeEnv: NodeEnvironment;
  readonly host: string;
  readonly port: number;
  readonly logLevel: LogLevel;
  readonly databaseDriver: DatabaseDriver;
  readonly databaseEnvironment: DatabaseEnvironment;
  readonly databaseAccessMode: DatabaseAccessMode;
  readonly mongodbUri?: string;
  readonly mongodbDbName: string;
  readonly mongodbServerSelectionTimeoutMs: number;
  readonly mongodbConnectTimeoutMs: number;
  readonly mongodbMaxPoolSize: number;
  readonly storageDriver: StorageDriver;
  readonly localStoragePath: string;
  readonly emailDriver: EmailDriver;
  readonly readyCheckTimeoutMs: number;
}
