import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { delegation } from './gatework';
import { getSession } from './session';
import type { GateworkRole } from './types';

/**
 * Console side of messaging moderation.
 *
 * Every call goes out with a delegation token minted for the operator, not with
 * a service credential: the messaging gateway decides what each role may do, and
 * a console bug must not be able to grant more than the operator holds. The
 * console never talks to Matrix and never reads a live conversation — the only
 * message text it can obtain is the evidence snapshot frozen when a report was
 * filed.
 */
const messagingBase = () => (process.env.MESSAGING_API_BASE_URL ?? 'http://localhost:8082').replace(/\/$/, '');

async function messagingFetch(path: string, init: RequestInit = {}) {
  const session = await getSession();
  if (!session) throw new Error('UNAUTHENTICATED');
  const token = await delegation(session.accessToken);
  const response = await fetch(`${messagingBase()}${path}`, {
    ...init,
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}`, ...(init.headers ?? {}) },
    cache: 'no-store',
  });
  if (!response.ok) {
    const detail = await response.json().catch(() => null) as { error?: { code?: string; message?: string } } | null;
    throw new Error(detail?.error?.message ?? `MESSAGING_${response.status}`);
  }
  return response.json();
}

export {
  REPORT_CATEGORY_LABELS,
  REPORT_STATUS_LABELS,
  MODERATION_ACTION_LABELS,
} from './moderation-labels';
export type {
  AuditRow, EvidenceMessage, ModeratedGroup, ModerationOverview,
  ReportDetail, ReportSummary, RestrictionRow,
} from './moderation-labels';

import type {
  AuditRow, ModeratedGroup, ModerationOverview, ReportDetail, ReportSummary, RestrictionRow,
} from './moderation-labels';

// Mirrors the gateway's own role gate. Duplicated on purpose: the server is the
// authority, and this copy only decides whether a button is worth rendering.
export const canReviewReports = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin', 'moderator', 'auditor'].includes(role));
export const canActOnReports = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin', 'moderator'].includes(role));
export const canTakeDownGroups = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin'].includes(role));

export const decisionSchema = z.object({
  action: z.enum(['dismiss', 'remove_message', 'restrict_user', 'remove_from_group']),
  reason: z.string().trim().min(5).max(500),
  restriction: z.enum(['muted', 'suspended']).optional(),
  durationHours: z.coerce.number().int().min(1).max(8760).optional(),
  removeMessage: z.boolean().default(false),
});
export const reasonSchema = z.object({ reason: z.string().trim().min(5).max(500) });

export async function listReports(params: { status?: string; category?: string; limit?: number } = {}): Promise<ReportSummary[]> {
  const query = new URLSearchParams({ status: params.status ?? 'unresolved', limit: String(params.limit ?? 50) });
  if (params.category) query.set('category', params.category);
  return (await messagingFetch(`/v1/internal/gatework/messaging/reports?${query}`)).data as ReportSummary[];
}
export async function getReport(id: string): Promise<ReportDetail> {
  return (await messagingFetch(`/v1/internal/gatework/messaging/reports/${id}`)).data as ReportDetail;
}
export async function claimReport(id: string) {
  return (await messagingFetch(`/v1/internal/gatework/messaging/reports/${id}/claim`, { method: 'POST', body: '{}' })).data;
}
export async function decideReport(id: string, raw: unknown) {
  const input = decisionSchema.parse(raw);
  // The key is minted here so a double-submitted form resolves the report once.
  return (await messagingFetch(`/v1/internal/gatework/messaging/reports/${id}/decision`, {
    method: 'POST',
    body: JSON.stringify({ ...input, idempotencyKey: randomUUID() }),
  })).data;
}
export async function moderationOverview(): Promise<ModerationOverview> {
  return (await messagingFetch('/v1/internal/gatework/messaging/overview')).data as ModerationOverview;
}
export async function listRestrictions(): Promise<RestrictionRow[]> {
  return (await messagingFetch('/v1/internal/gatework/messaging/restrictions')).data as RestrictionRow[];
}
export async function liftRestriction(userId: string, raw: unknown) {
  const { reason } = reasonSchema.parse(raw);
  return (await messagingFetch(`/v1/internal/gatework/messaging/restrictions/${userId}`, { method: 'DELETE', body: JSON.stringify({ reason }) })).data;
}
export async function listGroups(): Promise<ModeratedGroup[]> {
  return (await messagingFetch('/v1/internal/gatework/messaging/groups?limit=100')).data as ModeratedGroup[];
}
export async function takeDownGroup(id: string, raw: unknown) {
  const { reason } = reasonSchema.parse(raw);
  return (await messagingFetch(`/v1/internal/gatework/messaging/groups/${id}/takedown`, { method: 'POST', body: JSON.stringify({ reason, idempotencyKey: randomUUID() }) })).data;
}
export async function listAudit(): Promise<AuditRow[]> {
  return (await messagingFetch('/v1/internal/gatework/messaging/audit?limit=100')).data as AuditRow[];
}
