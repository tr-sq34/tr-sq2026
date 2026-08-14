import type { GateworkRole } from './types';

/**
 * Are the services up?
 *
 * The Komuta Merkezi card that asks this question has said "Bağlı servislerden
 * veri bekleniyor" since the console was written, while all four services grew
 * a `/health` route that answers in a few milliseconds. Nobody was asking them.
 *
 * The check is deliberately shallow and unauthenticated: each service's own
 * `/health` already proves the one thing this card claims - the process is up
 * and its database answers `SELECT 1`. Anything deeper would need a delegation
 * token, and a dashboard that cannot render while identity is down is the
 * opposite of a status page.
 *
 * A slow service is a down service here. Without the timeout the whole page
 * would hang on the one thing it is reporting as broken.
 */
const TIMEOUT_MS = 3000;

const base = (value: string | undefined, fallback: string) =>
  (value ?? fallback).replace(/\/$/, '');

const services = () => [
  { name: 'Kimlik', url: base(process.env.IDENTITY_API_BASE_URL, 'http://localhost:8080') },
  { name: 'Topluluk', url: base(process.env.COMMUNITY_API_BASE_URL, 'http://localhost:8081') },
  { name: 'Mesajlaşma', url: base(process.env.MESSAGING_API_BASE_URL, 'http://localhost:8082') },
  { name: 'Doğrulama', url: base(process.env.VERIFICATION_API_BASE_URL, 'http://localhost:8083') },
];

export type ServiceHealth = { name: string; healthy: boolean };

// Infrastructure state, not member data: the same roles that may read the audit
// trail or answer an emergency may see whether a service is answering. A
// content editor gets no card rather than a card they cannot interpret.
export const canSeeServiceHealth = (roles: GateworkRole[]) =>
  roles.some((role) => ['owner', 'security_admin', 'operations_admin', 'auditor'].includes(role));

export async function serviceHealth(): Promise<ServiceHealth[]> {
  return Promise.all(
    services().map(async ({ name, url }) => {
      try {
        const response = await fetch(`${url}/health`, {
          cache: 'no-store',
          signal: AbortSignal.timeout(TIMEOUT_MS),
        });
        return { name, healthy: response.ok };
      } catch {
        return { name, healthy: false };
      }
    }),
  );
}

/// One line for the card. Naming the services that are down matters more than
/// the count: "3/4" tells an operator to go looking, "Mesajlaşma yanıt vermiyor"
/// tells them where.
export function healthSummary(checks: ServiceHealth[]) {
  const down = checks.filter((check) => !check.healthy);
  if (down.length === 0) return `${checks.length} servisin ${checks.length}'i ayakta`;
  return `${down.map((check) => check.name).join(', ')} yanıt vermiyor`;
}
