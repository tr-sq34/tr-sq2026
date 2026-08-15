import { delegation } from './gatework';
import { getSession } from './session';
import {
  PROBE_TIMEOUT_MS, SLOW_MS, assessRisk,
  type AppStability, type ServiceHealth, type SystemHealthSnapshot,
} from './health-labels';
import type { GateworkRole } from './types';

/**
 * Is the system healthy, and how sure are we?
 *
 * This file answers one question with two independent measurements, because
 * neither one alone is the truth. The service probes say whether the backend is
 * answering; the app's own crash telemetry says whether the thing members hold
 * is surviving. A backend that is green while every phone is crashing on the
 * feed screen is not a healthy system, and the console used to have no way to
 * know the difference.
 *
 * The probes are deliberately shallow and unauthenticated: each service's own
 * `/health` already proves the one thing this card claims - the process is up
 * and its database answers `SELECT 1`. Anything deeper would need a delegation
 * token, and a status page that cannot render while identity is down is the
 * opposite of a status page.
 *
 * The rule the whole file is built on: a measurement that could not be taken is
 * never reported as a good one. `null` travels all the way to the screen.
 *
 * Types, thresholds and the scoring itself live in `health-labels.ts` so the
 * board can import them in the browser; this half reads cookies and mints
 * tokens and must never reach a client bundle.
 */
export * from './health-labels';

const base = (value: string | undefined, fallback: string) => (value ?? fallback).replace(/\/$/, '');
const communityBase = () => base(process.env.COMMUNITY_API_BASE_URL, 'http://localhost:8081');

const services = () => [
  { key: 'identity', name: 'Kimlik', url: base(process.env.IDENTITY_API_BASE_URL, 'http://localhost:8080') },
  { key: 'community', name: 'Topluluk', url: communityBase() },
  { key: 'messaging', name: 'Mesajlaşma', url: base(process.env.MESSAGING_API_BASE_URL, 'http://localhost:8082') },
  { key: 'verification', name: 'Doğrulama', url: base(process.env.VERIFICATION_API_BASE_URL, 'http://localhost:8083') },
];

// Infrastructure state, not member data: the same roles that may read the audit
// trail or answer an emergency may see whether a service is answering. A
// content editor gets no card rather than a card they cannot interpret.
export const canSeeServiceHealth = (roles: GateworkRole[]) =>
  roles.some((role) => ['owner', 'security_admin', 'operations_admin', 'auditor'].includes(role));

export async function serviceHealth(): Promise<ServiceHealth[]> {
  return Promise.all(
    services().map(async ({ key, name, url }) => {
      const startedAt = Date.now();
      try {
        const response = await fetch(`${url}/health`, { cache: 'no-store', signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) });
        const latencyMs = Date.now() - startedAt;
        if (!response.ok) return { key, name, state: 'down' as const, latencyMs, detail: `HTTP ${response.status}` };
        if (latencyMs > SLOW_MS) return { key, name, state: 'slow' as const, latencyMs, detail: 'Yavaş yanıt veriyor' };
        return { key, name, state: 'up' as const, latencyMs, detail: 'Çalışıyor' };
      } catch (error) {
        // A slow service is a down service here. Without the timeout the whole
        // page would hang on the one thing it is reporting as broken.
        const timedOut = error instanceof Error && error.name === 'TimeoutError';
        return {
          key, name, state: 'down' as const, latencyMs: null,
          detail: timedOut ? `Yanıt vermedi (${PROBE_TIMEOUT_MS / 1000} sn)` : 'Bağlanılamadı',
        };
      }
    }),
  );
}

/// One line for the card. Naming the services that are down matters more than
/// the count: "3/4" tells an operator to go looking, "Mesajlaşma yanıt vermiyor"
/// tells them where.
export function healthSummary(checks: ServiceHealth[]) {
  const down = checks.filter((check) => check.state === 'down');
  const slow = checks.filter((check) => check.state === 'slow');
  if (down.length === 0 && slow.length === 0) return `${checks.length} servisin ${checks.length}'i ayakta`;
  const parts: string[] = [];
  if (down.length) parts.push(`${down.map((check) => check.name).join(', ')} yanıt vermiyor`);
  if (slow.length) parts.push(`${slow.map((check) => check.name).join(', ')} yavaş`);
  return parts.join(' · ');
}

/// The app's own crash telemetry, read through a delegation token like every
/// other Community read the console does.
export async function appStability(hours = 24): Promise<{ stability: AppStability | null; failure: string | null }> {
  const session = await getSession();
  if (!session) return { stability: null, failure: 'Oturum: yeniden giriş yapılmalı.' };
  try {
    const token = await delegation(session.accessToken);
    const response = await fetch(`${communityBase()}/v1/internal/gatework/system/stability?hours=${hours}`, {
      headers: { authorization: `Bearer ${token}` },
      cache: 'no-store',
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error(`TOPLULUK_${response.status}`);
    const body = await response.json() as { data: AppStability };
    return { stability: body.data, failure: null };
  } catch (error) {
    return { stability: null, failure: error instanceof Error ? error.message : 'okunamadı' };
  }
}

export async function systemHealthSnapshot(hours = 24): Promise<SystemHealthSnapshot> {
  const [services, stability] = await Promise.all([
    serviceHealth().then((checks) => ({ checks, failure: null as string | null }))
      .catch((error: Error) => ({ checks: null, failure: error.message })),
    appStability(hours),
  ]);

  return {
    checkedAt: new Date().toISOString(),
    windowHours: hours,
    services: services.checks,
    servicesFailure: services.failure,
    stability: stability.stability,
    stabilityFailure: stability.failure,
    risk: assessRisk(services.checks, stability.stability),
    alerting: { configured: Boolean(process.env.OPS_ALERT_WEBHOOK_URL) },
  };
}
