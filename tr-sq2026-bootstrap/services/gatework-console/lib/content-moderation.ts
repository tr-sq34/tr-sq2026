import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { delegation } from './gatework';
import { getSession } from './session';

/**
 * Console side of feed moderation: reports about posts, comments and stories.
 *
 * A sibling of lib/moderation.ts rather than an extension of it. The two queues
 * live in different services because the content belongs to different services -
 * community owns the feed, the gateway owns messages - and merging the clients
 * would mean one module holding two base URLs and two failure modes. The console
 * shows them on one screen; that is a presentation decision, not a reason to
 * fuse the transports.
 *
 * Same rule as messaging: every call carries a delegation token minted for the
 * operator, never a service credential, so the community service decides what
 * each role may do and a console bug cannot grant more than the operator holds.
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
    const detail = await response.json().catch(() => null) as { error?: { code?: string; message?: string } } | null;
    throw new Error(detail?.error?.message ?? `COMMUNITY_${response.status}`);
  }
  if (response.status === 204) return null;
  return response.json();
}

export { CONTENT_TARGET_LABELS, CONTENT_ACTION_LABELS } from './content-moderation-labels';
export type { ContentReportSummary, ContentReportDetail, ContentOverview } from './content-moderation-labels';

import type { ContentOverview, ContentReportDetail, ContentReportSummary } from './content-moderation-labels';

export const contentDecisionSchema = z.object({
  action: z.enum(['dismiss', 'remove_content', 'restrict_author']),
  reason: z.string().trim().min(5).max(500),
  removeContent: z.boolean().default(false),
  restriction: z.enum(['muted', 'suspended']).optional(),
  durationHours: z.coerce.number().int().min(1).max(8760).optional(),
});

export async function listContentReports(params: { status?: string; category?: string; limit?: number } = {}): Promise<ContentReportSummary[]> {
  const query = new URLSearchParams({ status: params.status ?? 'unresolved', limit: String(params.limit ?? 50) });
  if (params.category) query.set('category', params.category);
  return (await communityFetch(`/v1/internal/gatework/community/reports?${query}`)).data as ContentReportSummary[];
}

export async function getContentReport(id: string): Promise<ContentReportDetail> {
  return (await communityFetch(`/v1/internal/gatework/community/reports/${id}`)).data as ContentReportDetail;
}

export async function claimContentReport(id: string) {
  return (await communityFetch(`/v1/internal/gatework/community/reports/${id}/claim`, { method: 'POST', body: '{}' })).data;
}

export async function decideContentReport(id: string, raw: unknown) {
  const input = contentDecisionSchema.parse(raw);
  // Minted here so a double-submitted form resolves the report once.
  return (await communityFetch(`/v1/internal/gatework/community/reports/${id}/decision`, {
    method: 'POST',
    body: JSON.stringify({ ...input, idempotencyKey: randomUUID() }),
  })).data;
}

export async function contentOverview(): Promise<ContentOverview> {
  return (await communityFetch('/v1/internal/gatework/community/overview')).data as ContentOverview;
}

export async function liftContentRestriction(userId: string, reason: string) {
  return communityFetch(`/v1/internal/gatework/community/restrictions/${userId}`, {
    method: 'DELETE',
    body: JSON.stringify({ reason, idempotencyKey: randomUUID() }),
  });
}
