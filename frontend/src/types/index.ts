/**
 * MarketTwin Core Type Definitions
 * Phase 1: Architectural Foundations & Setup
 */

export type UserRole = 'customer' | 'merchant';

export interface UserProfileSummary {
  id: string;
  email: string;
  role: UserRole;
  fullName?: string;
  createdAt?: string;
}

export interface ServiceStatus {
  status: 'operational' | 'degraded' | 'unavailable' | 'unconfigured';
  message?: string;
  latencyMs?: number;
}

export interface HealthResponse {
  status: 'ok' | 'degraded' | 'error';
  timestamp: string;
  service: string;
  version: string;
  environment: string;
  services?: {
    database?: ServiceStatus;
    storage?: ServiceStatus;
    realtime?: ServiceStatus;
  };
}

export interface ApiResponse<T = unknown> {
  success: boolean;
  message?: string;
  data?: T;
  error?: string;
}

export interface RoleFeature {
  title: string;
  description: string;
  badge: string;
  color: string;
  features: string[];
}
