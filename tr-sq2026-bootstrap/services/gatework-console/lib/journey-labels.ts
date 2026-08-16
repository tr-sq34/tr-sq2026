/**
 * Browser-safe half of the Rozetler ve Yolculuk screen.
 *
 * Split from lib/journey.ts for the same reason as the other label modules: the
 * desk is a client component and the server module reads the session cookie and
 * mints a delegation token.
 */

export type JourneyBadge = {
  code: string;
  title: string;
  description: string;
  icon: string;
  category: string;
  tier: string;
  points: number;
  isSecret: boolean;
  manualOnly: boolean;
  /**
   * Bu rozeti verecek bir kural var mı.
   *
   * Ekranın en önemli tek alanı. `false` olan bir rozet katalogda duruyor,
   * uygulamada kriteri yazıyor ve onu verecek hiçbir kod yok — yani kimse
   * kazanamaz. Sayıya bakıp "demek ki kimse hak etmemiş" demek, bu ekranın
   * verebileceği en yanlış cevap.
   */
  automated: boolean;
  holders: number;
  manualHolders: number;
  inProgress: number;
  lastGrantedAt: string | null;
};

export type JourneyLevel = { level: number; title: string; members: number };

/**
 * Rozeti taşıyan bir üye.
 *
 * `grantedBy` boşsa rozeti motor verdi. Ayrımı saklamak, bir denetçinin
 * "bu üye bu madalyayı nasıl aldı" sorusunu cevapsız bırakır - ve elle verilen
 * bir rozet zaten yalnızca gerekçesiyle birlikte anlamlı.
 */
export type BadgeHolder = {
  userId: string;
  displayName: string | null;
  earnedAt: string;
  grantedBy: string | null;
  grantedByName: string | null;
  grantedReason: string | null;
};

export type JourneyOverview = {
  members: number;
  granted: number;
  manualGrants: number;
  levels: JourneyLevel[];
  badges: JourneyBadge[];
};

export const CATEGORY_LABELS: Record<string, string> = {
  onboarding: 'Yeni gelenler',
  social: 'Sosyal',
  expert: 'Uzman',
  legendary: 'Efsanevi',
  secret: 'Gizli',
};

export const TIER_LABELS: Record<string, string> = {
  bronze: 'Bronz',
  silver: 'Gümüş',
  gold: 'Altın',
  legendary: 'Efsane',
};

export const TIER_TONE: Record<string, 'neutral' | 'brand' | 'success' | 'warning' | 'danger'> = {
  bronze: 'neutral',
  silver: 'neutral',
  gold: 'warning',
  legendary: 'brand',
};

/**
 * Bir rozetin durumu, tek cümlede.
 *
 * Üç hâl birbirine karışmasın diye ayrı ayrı yazılıyor. "0 kişi" satırı üç
 * farklı şeyi anlatabilir: kural var ama kimse hak etmemiş, kural yok, ya da
 * elle verilmesi gerekiyor ve henüz kimseye verilmemiş. Aynı sıfırı üç kez
 * göstermek, operatöre hiçbir şey söylememektir.
 */
export type BadgeHealth = { tone: 'neutral' | 'success' | 'warning' | 'danger'; label: string; note: string };

export function badgeHealth(badge: JourneyBadge): BadgeHealth {
  if (!badge.automated) {
    return badge.manualOnly
      ? { tone: 'neutral', label: 'Elle verilir', note: 'Tasarım gereği bir kararla verilir; kuralı yok.' }
      : {
          tone: 'danger',
          label: 'Kuralı yok',
          note: 'Katalogda duruyor ve uygulamada kriteri yazıyor, ama onu verecek bir kural yok. Kimse kazanamaz.',
        };
  }
  if (badge.holders === 0 && badge.inProgress === 0) {
    return {
      tone: 'warning',
      label: 'Hiç verilmedi',
      note: 'Kuralı var ama ne veren ne de sayacı işleyen biri olmuş. Kural hiç tetiklenmiyor olabilir.',
    };
  }
  if (badge.holders === 0) {
    return { tone: 'warning', label: 'Henüz kimse almadı', note: `${badge.inProgress} üyenin sayacı işliyor.` };
  }
  return { tone: 'success', label: 'Dağıtılıyor', note: '' };
}

export const count = (value: number) => value.toLocaleString('tr-TR');

export const grantedAgo = (iso: string | null) =>
  iso === null ? 'hiç' : new Date(iso).toLocaleDateString('tr-TR', { dateStyle: 'medium' });
