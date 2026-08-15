import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { delegation } from './gatework';
import { getSession } from './session';
import type { NewsSummary, OfficialStory, SystemAccount } from './content-labels';
import type { GateworkRole } from './types';

/**
 * The read half of İçerik Stüdyosu and Haber Merkezi.
 *
 * Publishing already lived in lib/gatework.ts and stays there. What did not
 * exist was any way to read back what had been published: creating an official
 * account returned a UUID and nothing ever listed it again, so an editor kept
 * that id outside the product and pasted it into every form. A mistyped paste
 * was not caught by the form - it was caught by the publish endpoint, after the
 * article body had already been written.
 *
 * Same delegation rule as everywhere else in this console: Community answers a
 * short-lived token minted for this operator, never a service credential.
 */
const communityBase = () => (process.env.COMMUNITY_API_BASE_URL ?? 'http://localhost:8081').replace(/\/$/, '');

export { NEWS_CATEGORIES, NEWS_CATEGORY_LABELS, VISIBILITY_LABELS } from './content-labels';
export type { NewsSummary, OfficialStory, SystemAccount } from './content-labels';

// Mirrors the roles the community service enforces on the publish endpoints.
// Moderators and auditors can read the news list but never write to it.
export const canPublishContent = (roles: GateworkRole[]) =>
  roles.some((role) => ['owner', 'operations_admin', 'content_editor'].includes(role));
export const canSeeNews = (roles: GateworkRole[]) =>
  roles.some((role) => ['owner', 'operations_admin', 'content_editor', 'moderator', 'auditor'].includes(role));

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
    const detail = (await response.json().catch(() => null)) as { error?: { message?: string } } | null;
    throw new Error(detail?.error?.message ?? `COMMUNITY_${response.status}`);
  }
  if (response.status === 204) return null;
  return response.json();
}

export async function listSystemAccounts(): Promise<SystemAccount[]> {
  return (await communityFetch('/v1/internal/gatework/system-accounts')).data as SystemAccount[];
}

export async function listNewsArticles(params: { category?: string; limit?: number } = {}): Promise<NewsSummary[]> {
  const search = new URLSearchParams({ limit: String(params.limit ?? 50) });
  if (params.category) search.set('category', params.category);
  return (await communityFetch(`/v1/internal/gatework/news?${search}`)).data as NewsSummary[];
}

export const retractNewsSchema = z.object({ reason: z.string().trim().min(5).max(500) });

/* --- Story ----------------------------------------------------------------
 *
 * Ana sayfanın en üstündeki Story şeridi, yeni bir üyenin ağı boş olduğu için
 * ilk gün tamamen boş kalıyordu. Sponsorlu yuvalar panelden yerleştirilebiliyor
 * ama platformun kendi Story'si için hiçbir yol yoktu; uygulamadaki oluşturucu
 * ise resmî hesap adına değil, o an giriş yapmış kişinin adına yayınlıyor.
 *
 * Story 24 saatte kendiliğinden düşer. Bu yüzden liste "yayınlananlar" değil,
 * "hâlâ yayında olanlar": kalan süreyi gösteren başka bir ekran yok.
 */
export const publishStorySchema = z.object({
  authorId: z.string().uuid(),
  mediaId: z.string().uuid(),
  ttlHours: z.coerce.number().int().min(1).max(24).default(24),
  reason: z.string().trim().min(5).max(500),
});

export async function listOfficialStories(): Promise<OfficialStory[]> {
  return (await communityFetch('/v1/internal/gatework/stories')).data as OfficialStory[];
}

export async function publishOfficialStory(raw: unknown) {
  const input = publishStorySchema.parse(raw);
  return (await communityFetch('/v1/internal/gatework/stories', {
    method: 'POST',
    body: JSON.stringify({ ...input, idempotencyKey: randomUUID() }),
  })).data as { id: string };
}

/// Satır silinmiyor, süresi şimdiye çekiliyor: görüntülenmeler ve beğeniler o
/// Story'ye bağlı duruyor ve açılmış bir şikâyet varsa hedefi hâlâ çözülebilir
/// olmalı.
export async function retractOfficialStory(id: string, raw: unknown) {
  const input = retractNewsSchema.parse(raw);
  z.string().uuid().parse(id);
  await communityFetch(`/v1/internal/gatework/stories/${id}`, {
    method: 'DELETE',
    body: JSON.stringify(input),
  });
  return { id };
}

// A soft delete on the service side: the comments and any report filed against
// the article still resolve to something after it comes down.
export async function retractNewsArticle(id: string, raw: unknown) {
  const input = retractNewsSchema.parse(raw);
  z.string().uuid().parse(id);
  await communityFetch(`/v1/internal/gatework/news/${id}`, {
    method: 'DELETE',
    body: JSON.stringify({ ...input, idempotencyKey: randomUUID() }),
  });
  return { id };
}
