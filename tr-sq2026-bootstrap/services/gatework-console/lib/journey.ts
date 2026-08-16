import { z } from 'zod';
import { delegation } from './gatework';
import { getSession } from './session';
import type { BadgeHolder, JourneyOverview } from './journey-labels';
import type { GateworkRole } from './types';

/**
 * Console side of Gurbet Yolculuğu.
 *
 * Rozet sistemi uygulamada baştan sona vardı - katalog, XP, seviye, seri - ve
 * panelde hiç yoktu. Yani "kaç rozet dağıtıldı", "bu rozeti kimse alabiliyor
 * mu", "Dayanışma Madalyası'nı kime verdik" sorularının hiçbirinin cevabı
 * yoktu; hepsi veritabanına elle bakmayı gerektiriyordu.
 *
 * Ekranın asıl bulgusu şu: katalogdaki elli rozetin on ikisinin kuralı var.
 * Kalanı üyeye kriteriyle birlikte gösteriliyor ve kazanılması imkânsız. Bu
 * ekran o farkı görünür kılıyor, gizlemiyor.
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
    const detail = (await response.json().catch(() => null)) as { error?: { message?: string } } | null;
    throw new Error(detail?.error?.message ?? `COMMUNITY_${response.status}`);
  }
  if (response.status === 204) return null;
  return response.json();
}

// Servisin listesiyle birebir. İçerik editörü katalogda ne olduğunu görmeli -
// yeni bir rozetin metnini o yazacak - ama vermek platform adına verilen bir
// karar, o yüzden verme listesi iki role iniyor.
export const canSeeJourney = (roles: GateworkRole[]) =>
  roles.some((role) => ['owner', 'security_admin', 'operations_admin', 'content_editor', 'analyst', 'auditor'].includes(role));
export const canGrantBadge = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'operations_admin'].includes(role));

// Servisin sınırlarının aynısı, ki operatör reddi gönderdikten sonra değil
// önce görsün.
export const badgeGrantSchema = z.object({
  userId: z.string().uuid('Geçerli bir üye seçilmedi.'),
  reason: z.string().trim().min(3, 'Gerekçe en az 3 karakter olmalı.').max(240, 'Gerekçe en fazla 240 karakter olabilir.'),
});

export async function journeyOverview(): Promise<JourneyOverview> {
  return (await communityFetch('/v1/internal/gatework/journey/badges')).data as JourneyOverview;
}

export async function badgeHolders(code: string): Promise<BadgeHolder[]> {
  return (await communityFetch(`/v1/internal/gatework/journey/badges/${encodeURIComponent(code)}/holders`)).data as BadgeHolder[];
}

export async function grantBadge(code: string, raw: unknown) {
  const input = badgeGrantSchema.parse(raw);
  return (await communityFetch(`/v1/internal/gatework/journey/badges/${encodeURIComponent(code)}/grant`, {
    method: 'POST',
    body: JSON.stringify(input),
  })).data as { code: string; userId: string; granted: boolean };
}

export async function revokeBadge(code: string, userId: string) {
  await communityFetch(`/v1/internal/gatework/journey/badges/${encodeURIComponent(code)}/holders/${encodeURIComponent(userId)}`, {
    method: 'DELETE',
  });
}

/**
 * Ekranın kendisi.
 *
 * Servise ulaşılamazsa katalog boş dönüyor ama nedeni de dönüyor: hiç rozet
 * tanımlanmamış gibi görünen bir ekran, bu sayfanın verebileceği en yanlış
 * cevap - operatör sistemin kurulmadığını sanır.
 */
export async function journeyPage(): Promise<{ overview: JourneyOverview | null; failure: string | null }> {
  try {
    return { overview: await journeyOverview(), failure: null };
  } catch (error) {
    return { overview: null, failure: error instanceof Error ? error.message : 'Topluluk servisine ulaşılamadı.' };
  }
}
