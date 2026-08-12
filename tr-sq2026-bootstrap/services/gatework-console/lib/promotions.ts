import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { delegation } from './gatework';
import type { PromotionSummary } from './promotion-labels';
import { getSession } from './session';

/**
 * Console side of Tanitim Yap: the sponsored story slot, the in-app banner and
 * the "Sana Ozel One Cikanlar" cards.
 *
 * Two jobs, one module, because they are two halves of the same decision. A
 * member asks and an operator answers; an operator can also place one directly,
 * which is the same row with the answer already filled in. Splitting them would
 * mean two clients writing to one table with two idea of what a promotion is.
 *
 * Same rule as the other community clients here: every call carries a
 * delegation token minted for the operator, never a service credential, so the
 * community service decides what each role may do.
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

// The labels and the row shape live in the browser-safe module; the queue is a
// client component and cannot pull this file's session read into its bundle.
export {
  PROMOTION_PLACEMENT_LABELS,
  PROMOTION_STATUS_LABELS,
  type PromotionSummary,
} from './promotion-labels';

export const promotionDecisionSchema = z.object({
  action: z.enum(['approve', 'reject', 'end']),
  reason: z.string().trim().min(3).max(500),
});

// The console lets an operator place all three kinds, including the featured
// cards members cannot ask for. The window fields are strings on purpose: the
// browser hands over a local `datetime-local` value and the conversion to an
// instant happens once, here, rather than in every form.
export const placePromotionSchema = z.object({
  placement: z.enum(['story_slot', 'app_banner', 'featured_card']),
  ownerId: z.string().uuid(),
  title: z.string().trim().min(3).max(120),
  subtitle: z.string().trim().min(1).max(200).optional(),
  mediaId: z.string().uuid().optional(),
  targetKind: z.enum(['post', 'listing', 'news', 'event', 'external']).optional(),
  targetValue: z.string().trim().min(1).max(500).optional(),
  regionCode: z.string().trim().regex(/^[A-Za-z]{2}$/).optional(),
  city: z.string().trim().min(2).max(80).optional(),
  startsAt: z.string().datetime(),
  endsAt: z.string().datetime(),
  reason: z.string().trim().min(5).max(500),
});

export async function listPromotions(status = 'pending'): Promise<PromotionSummary[]> {
  const query = new URLSearchParams({ status, limit: '50' });
  return (await communityFetch(`/v1/internal/gatework/promotions?${query}`)).data as PromotionSummary[];
}

export async function decidePromotion(id: string, raw: unknown) {
  const input = promotionDecisionSchema.parse(raw);
  return (await communityFetch(`/v1/internal/gatework/promotions/${id}/decision`, {
    method: 'POST',
    body: JSON.stringify({ ...input, idempotencyKey: randomUUID() }),
  })).data as { id: string; status: string; duplicate: boolean };
}

export async function placePromotion(raw: unknown) {
  const input = placePromotionSchema.parse(raw);
  return (await communityFetch('/v1/internal/gatework/promotions', {
    method: 'POST',
    body: JSON.stringify({ ...input, idempotencyKey: randomUUID() }),
  })).data as { id: string };
}
