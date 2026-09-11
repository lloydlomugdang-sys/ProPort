export type NodeEnvironment = 'development' | 'test' | 'production';
export type LogLevel = 'fatal' | 'error' | 'warn' | 'info' | 'debug' | 'trace' | 'silent';
export type DatabaseDriver = 'mock' | 'mongodb';
export type DatabaseEnvironment = 'development' | 'test';
export type DatabaseAccessMode = 'runtime' | 'maintenance';
export type StorageDriver = 'local';
export type EmailDriver = 'console' | 'smtp';

export interface SmtpConfig {
  readonly host: string;
  readonly port: number;
  readonly secure: boolean;
  readonly user: string;
  readonly pass: string;
  readonly from: string;
}

export interface DatabaseConfig {
  readonly nodeEnv: NodeEnvironment;
  readonly databaseDriver: DatabaseDriver;
  readonly databaseEnvironment: DatabaseEnvironment;
  readonly databaseAccessMode: DatabaseAccessMode;
  readonly mongodbUri?: string;
  readonly mongodbDbName: string;
  readonly mongodbServerSelectionTimeoutMs: number;
  readonly mongodbConnectTimeoutMs: number;
  readonly mongodbMaxPoolSize: number;
}

export interface AppConfig extends DatabaseConfig {
  readonly host: string;
  readonly port: number;
  readonly logLevel: LogLevel;
  readonly storageDriver: StorageDriver;
  readonly localStoragePath: string;
  readonly emailDriver: EmailDriver;
  readonly consoleEmailPreview: boolean;
  readonly smtp?: SmtpConfig;
  readonly authJwtSecret: string;
  readonly authJwtIssuer: string;
  readonly authJwtAudience: string;
  readonly authCodePepper: string;
  readonly authAccessTokenTtlSeconds: number;
  readonly authRefreshTokenTtlSeconds: number;
  readonly authCodeTtlSeconds: number;
  readonly authResetGrantTtlSeconds: number;
  readonly authCodeResendCooldownSeconds: number;
  readonly authCodeMaxAttempts: number;
  readonly trustProxy: false | number | string[];
  readonly readyCheckTimeoutMs: number;
}
