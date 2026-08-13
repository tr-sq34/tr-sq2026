import { z } from 'zod';
import { delegation } from './gatework';
import { getSession } from './session';
import type { SosAlert, SosLocation } from './safety-labels';
import type { GateworkRole } from './types';

/**
 * Console side of Güvenlik ve SOS.
 *
 * This is the only screen in Gatework that can reach a member's exact position,
 * and the whole design is about making that reach narrow and visible:
 *
 *   * the alert list carries no coordinates at all, at any role. It says a
 *     point exists, not where it is.
 *   * reading the point takes a separate call, and that call only answers while
 *     a grant the operator asked for by name - with a written reason and an
 *     expiry - is still live. The service checks the grant in the same statement
 *     that reads the coordinates.
 *   * closing an alert deletes the point. So does the member cancelling it.
 *
 * None of that is enforced here. It is enforced in Community, and this module
 * mirrors it so the screen cannot ask for something the service would refuse.
 */
const communityBase = () => (process.env.COMMUNITY_API_BASE_URL ?? 'http://localhost:8081').replace(/\/$/, '');

async function communityFetch(path: string, init: RequestInit = {}) {
  const session = await getSession();
  if (!session) throw new Error('UNAUTHENTICATED');
  const token = await delegation(session.accessToken);
  const response = await fetch(`${communityBase()}${path}`, {
    ...init,
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}`, ...(init.headers ?? {}) },
    cache: 'no-store',
  });
  if (!response.ok) {
    const detail = await response.json().catch(() => null) as { error?: { message?: string } } | null;
    throw new Error(detail?.error?.message ?? `COMMUNITY_${response.status}`);
  }
  if (response.status === 204) return null;
  return response.json();
}

export {
  SOS_KIND_LABELS, SOS_STATUS_LABELS, SOS_STATUS_TONE, isOpen, memberLabel, sosTime, waitedFor,
} from './safety-labels';
export type { SosAlert, SosLocation } from './safety-labels';

// Mirrors the service. An auditor may read the queue - reviewing how emergencies
// were answered is exactly their job - but cannot answer one or unseal a point.
// Moderator is absent from both: moderation is about what a member posted.
export const canSeeSafety = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin', 'operations_admin', 'auditor'].includes(role));
export const canActOnSafety = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin', 'operations_admin'].includes(role));

export const closeSchema = z.object({
  status: z.enum(['resolved', 'cancelled']),
  reason: z.string().trim().min(5, 'Gerekçe en az 5 karakter olmalı.').max(1000),
});
export const locationAccessSchema = z.object({
  reason: z.string().trim().min(5, 'Gerekçe en az 5 karakter olmalı.').max(500),
  minutes: z.coerce.number().int().min(5).max(120).default(30),
});

export async function listAlerts(params: { state?: string } = {}): Promise<SosAlert[]> {
  const search = new URLSearchParams({ state: params.state === 'all' ? 'all' : 'open', limit: '50' });
  return (await communityFetch(`/v1/internal/gatework/safety/alerts?${search}`)).data as SosAlert[];
}

export async function acknowledgeAlert(id: string) {
  await communityFetch(`/v1/internal/gatework/safety/alerts/${id}/acknowledge`, { method: 'POST' });
}

export async function openLocationAccess(id: string, raw: unknown) {
  const input = locationAccessSchema.parse(raw);
  return (await communityFetch(`/v1/internal/gatework/safety/alerts/${id}/location-access`, { method: 'POST', body: JSON.stringify(input) }))
    .data as { grantId: string; expiresAt: string };
}

export async function readLocation(id: string): Promise<SosLocation> {
  return (await communityFetch(`/v1/internal/gatework/safety/alerts/${id}/location`)).data as SosLocation;
}

export async function closeAlert(id: string, raw: unknown) {
  const input = closeSchema.parse(raw);
  await communityFetch(`/v1/internal/gatework/safety/alerts/${id}/close`, { method: 'POST', body: JSON.stringify(input) });
}

// The queue is the screen. A failure here empties it rather than showing a
// stale list: an operations console that quietly serves yesterday's emergencies
// is worse than one that says it cannot reach the service.
export async function safetyPage(params: { state?: string } = {}): Promise<{ alerts: SosAlert[]; failure: string | null }> {
  try {
    return { alerts: await listAlerts(params), failure: null };
  } catch (error) {
    return { alerts: [], failure: error instanceof Error ? error.message : 'Güvenlik servisine ulaşılamadı.' };
  }
}
