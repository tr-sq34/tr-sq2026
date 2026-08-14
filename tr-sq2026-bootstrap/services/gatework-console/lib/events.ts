import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { delegation } from './gatework';
import { getSession } from './session';
import type { EventRow } from './events-labels';
import type { GateworkRole } from './types';

/**
 * Console side of Etkinlikler.
 *
 * The app has shipped an Etkinlikler tab since its first release against four
 * invented meetups in a mock repository - no table, no route, and no way for
 * anybody at TurkSquare to publish a real one. Migration 022 gives them a
 * table and this desk is where they are written.
 *
 * Publishing lives here rather than in the app on purpose: an event carries a
 * date, a place and an implicit promise that somebody will be there, and the
 * person making that promise should be named and audited. When members get to
 * host their own, this desk becomes their review queue.
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

export { EVENT_CATEGORIES, categoryLabel, EVENT_STATUS_LABELS, EVENT_STATUS_ORDER, eventStatusTone, eventWhen, placeLabel, attendanceLabel } from './events-labels';
export type { EventRow } from './events-labels';

// Mirrors the service. Auditor and analyst read the list; writing one is an
// editorial act, so content_editor writes and moderator does not.
export const canSeeEvents = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'operations_admin', 'content_editor', 'moderator', 'analyst', 'auditor'].includes(role));
export const canPublishEvents = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'operations_admin', 'content_editor'].includes(role));

export const eventDraftSchema = z.object({
  title: z.string().trim().min(3, 'Başlık en az 3 karakter olmalı.').max(140),
  description: z.string().trim().max(4000).default(''),
  category: z.string().trim().min(2, 'Kategori en az 2 karakter olmalı.').max(40).default('Etkinlik'),
  startsAt: z.string().min(1, 'Başlangıç zamanı gerekli.'),
  endsAt: z.string().optional(),
  venueLabel: z.string().trim().min(2, 'Mekân adı gerekli.').max(200),
  city: z.string().trim().min(2, 'Şehir gerekli.').max(80),
  regionCode: z.string().trim().length(2, 'Eyalet kodu iki harf olmalı.'),
  priceLabel: z.string().trim().min(1).max(60).default('Ücretsiz'),
  externalUrl: z.string().trim().url('Bağlantı geçersiz.').startsWith('https://', 'Bağlantı https ile başlamalı.').max(500).optional(),
  capacity: z.number().int().min(1).max(100000).optional(),
  publish: z.boolean().default(true),
});
export const eventCancelSchema = z.object({ reason: z.string().trim().min(5, 'Gerekçe en az 5 karakter olmalı.').max(500) });

export async function listEvents(status = 'published'): Promise<EventRow[]> {
  const search = new URLSearchParams({ status, limit: '50' });
  return (await communityFetch(`/v1/internal/gatework/events?${search}`)).data as EventRow[];
}

export async function createEvent(raw: unknown) {
  const input = eventDraftSchema.parse(raw);
  // The form sends local wall-clock ("2026-09-04T19:00"); the service stores an
  // instant. Converting here rather than in the browser keeps one answer for
  // what "19:00" meant, instead of one per operator's laptop clock.
  const body = {
    ...input,
    startsAt: new Date(input.startsAt).toISOString(),
    endsAt: input.endsAt ? new Date(input.endsAt).toISOString() : undefined,
    idempotencyKey: randomUUID(),
  };
  return (await communityFetch('/v1/internal/gatework/events', { method: 'POST', body: JSON.stringify(body) })).data as { id: string; duplicate: boolean };
}

export async function publishEvent(id: string) {
  await communityFetch(`/v1/internal/gatework/events/${id}/publish`, { method: 'POST' });
  return { id, status: 'published' };
}

export async function cancelEvent(id: string, raw: unknown) {
  const input = eventCancelSchema.parse(raw);
  await communityFetch(`/v1/internal/gatework/events/${id}/cancel`, { method: 'POST', body: JSON.stringify({ ...input, idempotencyKey: randomUUID() }) });
  return { id, status: 'cancelled' };
}

// One page load, three lists. A failing list must not blank the other two: a
// draft nobody can see is how an event misses its own date.
export async function eventsPage(): Promise<{ published: EventRow[]; drafts: EventRow[]; cancelled: EventRow[]; failure: string | null }> {
  try {
    const [published, drafts, cancelled] = await Promise.all([listEvents('published'), listEvents('draft'), listEvents('cancelled')]);
    return { published, drafts, cancelled, failure: null };
  } catch (error) {
    return { published: [], drafts: [], cancelled: [], failure: error instanceof Error ? error.message : 'Etkinlik servisine ulaşılamadı.' };
  }
}
