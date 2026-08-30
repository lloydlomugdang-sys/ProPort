export type ServiceHealthStatus = 'up' | 'down' | 'mock' | 'local' | 'console';

export interface ServiceHealth {
  readonly status: ServiceHealthStatus;
  readonly detail?: string;
}

export interface ReadinessChecks {
  readonly database: ServiceHealthStatus;
  readonly storage: ServiceHealthStatus;
  readonly email: ServiceHealthStatus;
}
