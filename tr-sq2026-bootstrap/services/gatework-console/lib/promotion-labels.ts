/**
 * Browser-safe half of the Tanitim Yap contract, split from lib/promotions.ts
 * for the same reason lib/moderation-labels.ts is split from lib/moderation.ts:
 * the server module reads the session cookie, and importing it from a client
 * component drags next/headers into the browser bundle and breaks the build.
 */

export const PROMOTION_PLACEMENT_LABELS: Record<string, string> = {
  story_slot: 'Story alanı (sponsorlu)',
  app_banner: 'Uygulama içi banner',
  featured_card: 'Sana Özel Öne Çıkanlar',
};

export const PROMOTION_STATUS_LABELS: Record<string, string> = {
  pending: 'Onay bekliyor',
  approved: 'Onaylandı',
  rejected: 'Reddedildi',
  ended: 'Sonlandırıldı',
};

export type PromotionSummary = {
  id: string;
  placement: string;
  title: string;
  subtitle: string | null;
  imageUrl: string | null;
  targetKind: string | null;
  targetValue: string | null;
  regionCode: string | null;
  city: string | null;
  startsAt: string;
  endsAt: string;
  status: string;
  decisionReason: string | null;
  createdAt: string;
  ownerId: string;
  ownerName: string;
  requestNote: string | null;
  // NULL means "never hand-ordered". Those cards keep the old newest-first
  // behaviour behind the ordered ones, so migration 031 could not reshuffle
  // placements that were already running.
  displayOrder: number | null;
  impressions: number;
  clicks: number;
};

/**
 * Clicks per impression, as a percentage, or null when nothing has been shown
 * yet. The null matters: a promotion with no impressions has no rate at all,
 * and printing "%0" there reads as "shown to everyone, clicked by nobody" -
 * the opposite conclusion from "not on screen yet".
 */
export function promotionCtr(impressions: number, clicks: number): number | null {
  return impressions > 0 ? (clicks / impressions) * 100 : null;
}

export const formatCtr = (value: number | null) =>
  value === null ? '—' : `%${value.toLocaleString('tr-TR', { minimumFractionDigits: 1, maximumFractionDigits: 1 })}`;

export const formatCount = (value: number) => value.toLocaleString('tr-TR');

/**
 * Whether the app would draw this card right now. `promotions_controller.dart`
 * keeps only promotions live at this instant, so an approved row outside its
 * window is on nobody's screen - a distinction the status alone cannot make.
 */
export function promotionWindowState(row: { status: string; startsAt: string; endsAt: string }): 'live' | 'scheduled' | 'expired' | 'off' {
  if (row.status !== 'approved') return 'off';
  const now = Date.now();
  if (Date.parse(row.startsAt) > now) return 'scheduled';
  if (Date.parse(row.endsAt) <= now) return 'expired';
  return 'live';
}

export const PROMOTION_WINDOW_LABELS: Record<string, string> = {
  live: 'Şu an yayında',
  scheduled: 'Başlamadı',
  expired: 'Süresi doldu',
  off: 'Yayında değil',
};
