import { z } from 'zod';
import { delegation } from './gatework';
import { getSession } from './session';
import type { SupportRequest, SupportThread } from './support-labels';
import type { GateworkRole } from './types';

/**
 * Console side of Destek Talepleri.
 *
 * Bir üyenin platformla konuştuğu yer. Şikâyet (moderasyon) başka bir şey: o,
 * başka bir üyeyi işaret ediyor. Burada karşı taraf biziz.
 *
 * Sıra Community'de belirleniyor, burada değil: en uzun süredir cevap bekleyen
 * talep başta. Konsol o sırayı yeniden hesaplamıyor, çünkü iki yerde hesaplanan
 * bir sıra er geç iki farklı sıra olur.
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
  SUPPORT_STATUS_LABELS, SUPPORT_STATUS_TONE, SUPPORT_TOPIC_LABELS, clientLabel, supportMemberLabel, supportTime, waitingFor,
} from './support-labels';
export type { SupportRequest, SupportThread, SupportMessage, SupportStatus, SupportTopic } from './support-labels';

// Servisin listesiyle aynı: denetçi kuyruğu okuyabiliyor - desteğin nasıl
// yürüdüğünü incelemek işinin tanımı - ama cevap yazamıyor. Moderatör ikisini
// de yapabiliyor, çünkü gelen taleplerin çoğu bir moderasyon kararının
// arkasından geliyor.
export const canSeeSupport = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin', 'operations_admin', 'moderator', 'auditor'].includes(role));
export const canAnswerSupport = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin', 'operations_admin', 'moderator'].includes(role));

export const supportReplySchema = z.object({
  body: z.string().trim().min(2, 'Yanıt boş olamaz.').max(4000),
  close: z.boolean().default(false),
});
export const supportCloseSchema = z.object({
  reason: z.string().trim().min(5, 'Gerekçe en az 5 karakter olmalı.').max(500),
});

const STATES = ['waiting', 'open', 'closed', 'all'] as const;

export async function listSupportRequests(params: { state?: string; topic?: string } = {}): Promise<SupportRequest[]> {
  const search = new URLSearchParams({
    state: (STATES as readonly string[]).includes(params.state ?? '') ? params.state! : 'waiting',
    limit: '100',
  });
  if (params.topic) search.set('topic', params.topic);
  return (await communityFetch(`/v1/internal/gatework/support/requests?${search}`)).data as SupportRequest[];
}

export async function supportThread(id: string): Promise<SupportThread> {
  return (await communityFetch(`/v1/internal/gatework/support/requests/${id}`)).data as SupportThread;
}

export async function replyToSupport(id: string, raw: unknown) {
  const input = supportReplySchema.parse(raw);
  await communityFetch(`/v1/internal/gatework/support/requests/${id}/reply`, { method: 'POST', body: JSON.stringify(input) });
}

export async function closeSupport(id: string, raw: unknown) {
  const input = supportCloseSchema.parse(raw);
  await communityFetch(`/v1/internal/gatework/support/requests/${id}/close`, { method: 'POST', body: JSON.stringify(input) });
}

// Ekranın kendisi. Servise ulaşılamazsa liste boş dönüyor ama neden boş olduğu
// da dönüyor: cevap bekleyen kimse yokmuş gibi görünen bir destek kuyruğu, en
// kötü yanlış.
export async function supportPage(params: { state?: string; topic?: string } = {}): Promise<{ requests: SupportRequest[]; failure: string | null }> {
  try {
    return { requests: await listSupportRequests(params), failure: null };
  } catch (error) {
    return { requests: [], failure: error instanceof Error ? error.message : 'Destek servisine ulaşılamadı.' };
  }
}
