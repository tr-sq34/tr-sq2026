import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { delegation } from './gatework';
import { getSession } from './session';
import type { ForumCategory, ForumTopicRow } from './forum-labels';
import type { GateworkRole } from './types';

/**
 * Console side of the forum.
 *
 * The sections people write under are data, not a migration: a category is
 * opened, renamed and retired from here, and the app picks it up on its next
 * request. Pinning and locking live here too, because "this is the rules topic"
 * and "this thread is settled" are decisions somebody takes, not states that
 * happen.
 *
 * Same rule as every other community client here: each call carries a
 * delegation token minted for the operator, never a service credential.
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

export { FORUM_STATE_LABELS } from './forum-labels';
export type { ForumCategory, ForumTopicRow } from './forum-labels';

export const canEditForum = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'operations_admin', 'content_editor'].includes(role));
export const canModerateForum = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin', 'operations_admin', 'moderator'].includes(role));
export const canSeeForum = (roles: GateworkRole[]) => canEditForum(roles) || canModerateForum(roles) || roles.some((role) => ['analyst', 'auditor'].includes(role));

export const forumCategorySchema = z.object({
  slug: z.string().trim().toLowerCase().regex(/^[a-z0-9-]{2,48}$/, 'Kısa ad yalnızca küçük harf, rakam ve tire içerebilir.'),
  title: z.string().trim().min(2).max(80),
  emoji: z.string().trim().min(1).max(8).default('💬'),
  description: z.string().trim().max(240).default(''),
  ordinal: z.coerce.number().int().min(0).max(999).default(0),
  reason: z.string().trim().min(5).max(500),
});
// The slug is missing on purpose: community refuses to patch it, because a saved
// filter and a shared link hang off it.
export const forumCategoryPatchSchema = z.object({
  title: z.string().trim().min(2).max(80).optional(),
  emoji: z.string().trim().min(1).max(8).optional(),
  description: z.string().trim().max(240).optional(),
  ordinal: z.coerce.number().int().min(0).max(999).optional(),
  isActive: z.boolean().optional(),
  reason: z.string().trim().min(5).max(500),
});
// The whole order at once rather than one ordinal per row: setting them one at
// a time leaves two categories briefly sharing a number, and the tie is broken
// by title - so the forum reshuffles itself while an operator is editing it.
export const forumCategoryOrderSchema = z.object({
  ids: z.array(z.string().uuid()).min(1).max(60),
  reason: z.string().trim().min(5).max(500),
});
export const forumTopicStateSchema = z.object({
  isPinned: z.boolean().optional(),
  isLocked: z.boolean().optional(),
  reason: z.string().trim().min(5).max(500),
});

export async function listForumCategories(): Promise<ForumCategory[]> {
  return (await communityFetch('/v1/internal/gatework/forum/categories')).data as ForumCategory[];
}

export async function createForumCategory(raw: unknown) {
  const input = forumCategorySchema.parse(raw);
  return (await communityFetch('/v1/internal/gatework/forum/categories', {
    method: 'POST',
    body: JSON.stringify({ ...input, idempotencyKey: randomUUID() }),
  })).data as { id: string; duplicate: boolean };
}

export async function updateForumCategory(id: string, raw: unknown) {
  const input = forumCategoryPatchSchema.parse(raw);
  return (await communityFetch(`/v1/internal/gatework/forum/categories/${id}`, { method: 'PATCH', body: JSON.stringify(input) })).data as { id: string };
}

export async function reorderForumCategories(raw: unknown) {
  const input = forumCategoryOrderSchema.parse(raw);
  return (await communityFetch('/v1/internal/gatework/forum/categories/order', {
    method: 'PUT',
    body: JSON.stringify(input),
  })).data as { ordered: number };
}

export async function listForumTopics(params: { categoryId?: string; state?: string; query?: string } = {}): Promise<ForumTopicRow[]> {
  const search = new URLSearchParams({ state: params.state ?? 'active', limit: '50' });
  if (params.categoryId) search.set('categoryId', params.categoryId);
  if (params.query && params.query.trim().length >= 2) search.set('query', params.query.trim());
  return (await communityFetch(`/v1/internal/gatework/forum/topics?${search}`)).data as ForumTopicRow[];
}

export async function setForumTopicState(id: string, raw: unknown) {
  const input = forumTopicStateSchema.parse(raw);
  return (await communityFetch(`/v1/internal/gatework/forum/topics/${id}/state`, { method: 'POST', body: JSON.stringify(input) })).data as { id: string; isPinned: boolean; isLocked: boolean };
}
