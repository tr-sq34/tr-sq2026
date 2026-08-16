import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { delegation } from './gatework';
import { getSession } from './session';
import type { CommunityMember, IdentityMember, MemberSession } from './member-labels';
import type { GateworkRole } from './types';

/**
 * Console side of the Uyeler screen.
 *
 * A member is two records in two services and this module is the only place
 * that admits it. Identity owns the account - email, verification, Gatework
 * roles, refresh tokens - and answers the operator's own token. Community owns
 * what the member did and what has been decided about them, and answers a
 * short-lived delegation minted per call. Neither service learns about the
 * other; the screen is where they are put side by side.
 *
 * Nothing here reads a password hash, a token or a message. The account half is
 * email, name and role; the behaviour half is counts and decisions.
 */
const identityBase = () => (process.env.IDENTITY_API_BASE_URL ?? 'http://localhost:8080').replace(/\/$/, '');
const communityBase = () => (process.env.COMMUNITY_API_BASE_URL ?? 'http://localhost:8081').replace(/\/$/, '');

async function failure(response: Response, fallback: string) {
  const detail = await response.json().catch(() => null) as { error?: { message?: string } } | null;
  return new Error(detail?.error?.message ?? fallback);
}

async function identityFetch(path: string, init: RequestInit = {}) {
  const session = await getSession();
  if (!session) throw new Error('UNAUTHENTICATED');
  const response = await fetch(`${identityBase()}${path}`, {
    ...init,
    headers: { 'content-type': 'application/json', authorization: `Bearer ${session.accessToken}`, ...(init.headers ?? {}) },
    cache: 'no-store',
  });
  if (!response.ok) throw await failure(response, `IDENTITY_${response.status}`);
  if (response.status === 204) return null;
  return response.json();
}

async function communityFetch(path: string, init: RequestInit = {}) {
  const session = await getSession();
  if (!session) throw new Error('UNAUTHENTICATED');
  const token = await delegation(session.accessToken);
  const response = await fetch(`${communityBase()}${path}`, {
    ...init,
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}`, ...(init.headers ?? {}) },
    cache: 'no-store',
  });
  if (!response.ok) throw await failure(response, `COMMUNITY_${response.status}`);
  if (response.status === 204) return null;
  return response.json();
}

export { ROLE_LABELS, ROLE_HINTS, RESTRICTION_LABELS } from './member-labels';
export type { IdentityMember, CommunityMember, MemberSession } from './member-labels';

// The role gates are read off the session on the server and passed to the
// screen as flags. The services enforce the same rules again; this only decides
// which buttons are worth drawing.
export const canSeeMembers = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin', 'operations_admin', 'auditor'].includes(role));
export const canManageRoles = (roles: GateworkRole[]) => roles.includes('owner');
export const canRevokeSessions = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin'].includes(role));
export const canRestrictMembers = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin', 'moderator'].includes(role));
export const canSetCapabilities = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'operations_admin'].includes(role));

export const memberRoleSchema = z.object({
  role: z.enum(['owner', 'security_admin', 'operations_admin', 'content_editor', 'moderator', 'analyst', 'auditor']),
  reason: z.string().trim().min(5).max(500),
});
export const memberReasonSchema = z.object({ reason: z.string().trim().min(5).max(500) });
export const memberRestrictionSchema = z.object({
  kind: z.enum(['muted', 'suspended']),
  reason: z.string().trim().min(5).max(500),
  durationHours: z.coerce.number().int().min(1).max(8760).optional(),
});
export const memberCapabilitySchema = z.object({
  auctionSellerEligible: z.boolean(),
  reason: z.string().trim().min(5).max(500),
});

export async function searchMembers(params: { query?: string; role?: string; limit?: number } = {}): Promise<IdentityMember[]> {
  const search = new URLSearchParams({ limit: String(params.limit ?? 50) });
  // Two characters is Identity's floor for a search; sending one back would be a
  // 400 instead of the full list the operator expected.
  if (params.query && params.query.trim().length >= 2) search.set('query', params.query.trim());
  if (params.role) search.set('role', params.role);
  return (await identityFetch(`/v1/auth/gatework/members?${search}`)).data as IdentityMember[];
}

/**
 * Bir üyenin açık oturumları.
 *
 * Kimlik servisi yenileme jetonu ailelerini zaten tutuyordu; eksik olan, her
 * ailenin hangi cihazdan ve hangi ağ bloğundan açıldığıydı. Tam IP burada da
 * yok: saklanan şey /24 (IPv6'da /48) bloğu.
 */
export async function memberSessions(userId: string): Promise<MemberSession[]> {
  return (await identityFetch(`/v1/auth/gatework/members/${userId}/sessions`)).data as MemberSession[];
}

export async function grantRole(userId: string, raw: unknown) {
  const input = memberRoleSchema.parse(raw);
  return identityFetch('/v1/auth/gatework/roles', { method: 'POST', body: JSON.stringify({ userId, ...input, idempotencyKey: randomUUID() }) });
}

export async function revokeRole(userId: string, raw: unknown) {
  const input = memberRoleSchema.parse(raw);
  return identityFetch('/v1/auth/gatework/roles/revoke', { method: 'POST', body: JSON.stringify({ userId, ...input, idempotencyKey: randomUUID() }) });
}

// Ends every session the member has, everywhere. Used when an account is
// believed stolen, so it must not wait for a token to expire on its own.
export async function revokeSessions(userId: string, raw: unknown) {
  const input = memberReasonSchema.parse(raw);
  return identityFetch(`/v1/auth/gatework/members/${userId}/revoke-sessions`, { method: 'POST', body: JSON.stringify({ ...input, idempotencyKey: randomUUID() }) });
}

export async function communityMember(userId: string): Promise<CommunityMember> {
  return (await communityFetch(`/v1/internal/gatework/community/members/${userId}`)).data as CommunityMember;
}

export async function restrictMember(userId: string, raw: unknown) {
  const input = memberRestrictionSchema.parse(raw);
  return (await communityFetch(`/v1/internal/gatework/community/restrictions/${userId}`, {
    method: 'POST',
    body: JSON.stringify({ ...input, idempotencyKey: randomUUID() }),
  })).data as { userId: string; duplicate: boolean };
}

export async function setCapabilities(userId: string, raw: unknown) {
  const input = memberCapabilitySchema.parse(raw);
  return (await communityFetch(`/v1/internal/gatework/community/members/${userId}/capabilities`, {
    method: 'PUT',
    body: JSON.stringify(input),
  })).data as { userId: string; auctionSellerEligible: boolean };
}
