import type { ServiceHealth } from '../../common/types/service-health.js';
import type { DatabaseConnection, DatabaseStatus } from './database-connection.js';

export class MockDatabaseConnection implements DatabaseConnection {
  private currentStatus: DatabaseStatus = 'disconnected';

  get status(): DatabaseStatus {
    return this.currentStatus;
  }

  async connect(): Promise<void> {
    this.currentStatus = 'connected';
  }

  async disconnect(): Promise<void> {
    this.currentStatus = 'disconnected';
  }

  async ping(): Promise<ServiceHealth> {
    if (this.currentStatus !== 'connected') {
      return { status: 'down', detail: 'Mock database is disconnected.' };
    }
    return { status: 'mock', detail: 'No persistent database is configured.' };
  }
}
