import { z } from 'zod';
import { delegation } from './gatework';
import { getSession } from './session';
import { type LegalDocument, type LegalKind } from './legal-labels';
import type { GateworkRole } from './types';

/**
 * Kullanım Koşulları ve Gizlilik Politikası'nın panel tarafı.
 *
 * Giriş ekranının altında "Devam ederek Kullanım Koşulları ve Gizlilik
 * Politikası'nı kabul etmiş olursunuz" yazıyor ve iki bağlantının da altı
 * çiziliydi. İkisi de hiçbir yere gitmiyordu — uygulamada, panelde, veritabanında
 * böyle bir metin hiç olmadı. Üyeden okuyamadığı bir şeyi kabul etmesi
 * isteniyordu.
 *
 * Metin koda gömülmüyor. Bir gizlilik politikası hukuki bir taahhüt ve her
 * değiştiğinde uygulamanın yeni sürümünü mağazadan geçirmek, metnin günü geçmiş
 * kalmasının en yaygın sebebi.
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

// Servisin listesiyle birebir. Yazan ile yayımlayan ayrı: yayımlamak bir hukuki
// taahhüdü yürürlüğe koymak, ve metni yazabilen herkesin bunu tek başına
// yapabilmesi incelemeyi isteğe bağlı hale getirirdi.
export const canSeeLegal = (roles: GateworkRole[]) =>
  roles.some((role) => ['owner', 'security_admin', 'operations_admin', 'content_editor', 'auditor'].includes(role));
export const canDraftLegal = (roles: GateworkRole[]) =>
  roles.some((role) => ['owner', 'operations_admin', 'content_editor'].includes(role));
export const canPublishLegal = (roles: GateworkRole[]) =>
  roles.some((role) => ['owner', 'security_admin'].includes(role));

// Servisin sınırlarının aynısı, ki operatör reddi gönderdikten sonra değil önce
// görsün.
export const legalDraftSchema = z.object({
  title: z.string().trim().min(1, 'Başlık boş olamaz.').max(160, 'Başlık en fazla 160 karakter olabilir.'),
  body: z.string().trim().min(1, 'Metin boş olamaz.').max(200_000, 'Metin çok uzun.'),
  changeNote: z.string().trim().max(500, 'Not en fazla 500 karakter olabilir.').optional(),
});

const isKind = (value: string): value is LegalKind => value === 'terms' || value === 'privacy';

export async function legalDocuments(): Promise<LegalDocument[]> {
  return (await communityFetch('/v1/internal/gatework/legal')).data.documents as LegalDocument[];
}

export async function saveLegalDraft(kind: string, raw: unknown) {
  if (!isKind(kind)) throw new Error('Böyle bir metin yok.');
  const input = legalDraftSchema.parse(raw);
  return (await communityFetch(`/v1/internal/gatework/legal/${kind}/draft`, {
    method: 'PUT',
    body: JSON.stringify(input),
  })).data as { kind: LegalKind; id: string; version: number };
}

export async function publishLegal(kind: string) {
  if (!isKind(kind)) throw new Error('Böyle bir metin yok.');
  return (await communityFetch(`/v1/internal/gatework/legal/${kind}/publish`, { method: 'POST' })).data as {
    kind: LegalKind;
    version: number;
  };
}

/**
 * Ekranın kendisi.
 *
 * Servise ulaşılamazsa liste boş dönmüyor, `null` dönüyor ve nedeni yanında
 * geliyor: hiç metin yazılmamış gibi görünen bir ekran, bu sayfanın verebileceği
 * en yanlış cevap — operatör metni yeniden yazmaya oturur.
 */
export async function legalPage(): Promise<{ documents: LegalDocument[] | null; failure: string | null }> {
  try {
    return { documents: await legalDocuments(), failure: null };
  } catch (error) {
    return { documents: null, failure: error instanceof Error ? error.message : 'Topluluk servisine ulaşılamadı.' };
  }
}
