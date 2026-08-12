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
};
