import type { Connection } from 'mongoose';
import type { ServiceHealth } from '../../common/types/service-health.js';

export type DatabaseStatus = 'disconnected' | 'connecting' | 'connected' | 'disconnecting' | 'error';

export interface DatabaseConnection {
  readonly status: DatabaseStatus;
  readonly mongooseConnection?: Connection;
  connect(): Promise<void>;
  disconnect(): Promise<void>;
  ping(): Promise<ServiceHealth>;
}
