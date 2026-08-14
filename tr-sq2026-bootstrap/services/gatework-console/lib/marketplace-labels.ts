/**
 * Browser-safe half of the Çarşı ve İhaleler screen: row shapes, Turkish
 * labels, and the rules that turn the service's measurements into a warning.
 *
 * Split from lib/marketplace.ts for the same reason as the other label modules
 * - the screen is a client component and the server module reads the session
 * cookie.
 */

export type ListingSignals = {
  // Median price of the other active listings in the same category, and how
  // many rows that median was taken over. The sample is carried so the screen
  // can say "not enough listings to compare" rather than compare against two.
  categoryMedianPrice: number | null;
  categorySample: number;
  sellerListingsLast24h: number;
  sellerActiveListings: number;
  sellerOpenReports: number;
  sellerFraudReports: number;
  sellerVerified: boolean;
  duplicateTitleOwners: number;
};

export type ListingRow = {
  id: string;
  title: string;
  description: string;
  price: number;
  status: string;
  category: string;
  city: string | null;
  regionCode: string | null;
  ownerId: string;
  ownerName: string | null;
  createdAt: string;
  updatedAt: string;
  auction: { id: string; state: string; bidCount: number } | null;
  signals: ListingSignals | null;
};

export type AuctionRow = {
  id: string;
  listingId: string;
  listingTitle: string;
  listingStatus: string;
  sellerId: string;
  sellerName: string | null;
  // The Onaylı Hesap badge is checked when the auction opens and never again;
  // this is whether the seller still holds it right now.
  sellerEligible: boolean;
  startingPrice: number;
  minimumIncrement: number;
  startsAt: string;
  endsAt: string;
  // What the row is worth acting on, derived from the clock. storedStatus is
  // carried alongside because the column is written once at insert and never
  // advances; showing it as the truth would label every finished auction
  // "planlandı".
  state: string;
  storedStatus: string;
  bidCount: number;
  topBid: number | null;
  topBidderId: string | null;
  topBidderName: string | null;
  createdAt: string;
};

export type MarketplaceOverview = {
  listings: Record<string, number>;
  auctions: Record<string, number>;
  newListingsLast7Days: number;
  bidsLast7Days: number;
  endingSoon: number;
  eligibleSellers: number;
};

export const LISTING_STATUS_LABELS: Record<string, string> = {
  draft: 'Taslak',
  active: 'Yayında',
  reserved: 'Ayrıldı',
  sold: 'Satıldı',
  inactive: 'Yayından kaldırıldı',
};

export const AUCTION_STATE_LABELS: Record<string, string> = {
  scheduled: 'Başlamadı',
  active: 'Sürüyor',
  closed: 'Bitti',
  cancelled: 'İptal edildi',
};

// Same keys and same wording as the app's MarketplaceCategory enum; a listing
// whose category this console renamed would be a listing the operator and the
// member are looking at under two different names.
export const LISTING_CATEGORY_LABELS: Record<string, string> = {
  vehicle: 'Araçlar',
  rental: 'Kiralamalar',
  home: 'Ev & eşya',
  electronics: 'Elektronik',
  collectible: 'Koleksiyon',
  art: 'Sanat & hobi',
  other: 'Diğer',
};

export const LISTING_STATUS_ORDER = ['active', 'draft', 'reserved', 'sold', 'inactive'];
export const AUCTION_STATE_ORDER = ['active', 'scheduled', 'closed', 'cancelled'];

// Prices are stored as NUMERIC(12,2) and arrive as numbers; the app writes them
// in dollars, so the console does too rather than inventing a second unit.
export const money = (value: number) => value.toLocaleString('tr-TR', { style: 'currency', currency: 'USD', maximumFractionDigits: 2 });
export const sellerLabel = (row: { ownerName?: string | null; sellerName?: string | null; ownerId?: string; sellerId?: string }) =>
  row.ownerName ?? row.sellerName ?? `${(row.ownerId ?? row.sellerId ?? '').slice(0, 8)}…`;
export const placeLabel = (row: { city: string | null; regionCode: string | null }) => [row.city, row.regionCode].filter(Boolean).join(', ');
export const categoryLabel = (key: string) => LISTING_CATEGORY_LABELS[key] ?? LISTING_CATEGORY_LABELS.other!;

/**
 * The thresholds.
 *
 * They live here, in the open, next to the sentence the operator reads - not in
 * the database and not in a stored score. Every one of them is a guess about
 * where "unusual" starts, and a guess that can only be changed by a migration
 * is a guess nobody ever revisits.
 *
 * None of these is evidence of fraud on its own. A listing priced at a tenth of
 * its category is often a category the seller picked wrong; an account with
 * eight listings in a day is usually a shop. The flags say what was measured
 * and leave the decision - and the written reason - to a person.
 */
export const RISK_RULES = {
  // A tenth of the going rate, over a sample large enough to have a going rate.
  cheapRatio: 0.1,
  minimumSample: 5,
  listingsPerDay: 8,
} as const;

export type RiskFlag = {
  key: string;
  tone: 'danger' | 'warning';
  label: string;
  detail: string;
};

export function listingRiskFlags(row: ListingRow): RiskFlag[] {
  const signals = row.signals;
  if (!signals) return [];
  const flags: RiskFlag[] = [];

  if (signals.sellerFraudReports > 0) {
    flags.push({
      key: 'fraud-reports',
      tone: 'danger',
      label: 'Dolandırıcılık şikâyeti',
      detail: `Satıcı hakkında son 180 günde ${signals.sellerFraudReports} dolandırıcılık ya da yasa dışı ürün şikâyeti kaydedilmiş.`,
    });
  }

  if (signals.duplicateTitleOwners > 0) {
    flags.push({
      key: 'duplicate-title',
      tone: 'danger',
      label: 'Aynı başlık başka hesapta',
      detail: `Bu başlığın aynısı ${signals.duplicateTitleOwners} farklı hesapta daha var. Kopyala-yapıştır ilan ağı en sık görülen dolandırıcılık düzenidir.`,
    });
  }

  const median = signals.categoryMedianPrice;
  if (median !== null && signals.categorySample >= RISK_RULES.minimumSample && row.price > 0 && row.price < median * RISK_RULES.cheapRatio) {
    flags.push({
      key: 'price-outlier',
      tone: 'warning',
      label: 'Fiyat kategori ortancasının çok altında',
      detail: `${categoryLabel(row.category)} kategorisindeki ${signals.categorySample} yayın ilanın ortanca fiyatı ${money(median)}; bu ilan ${money(row.price)}.`,
    });
  }

  if (signals.sellerListingsLast24h >= RISK_RULES.listingsPerDay) {
    flags.push({
      key: 'bulk-posting',
      tone: 'warning',
      label: 'Toplu ilan',
      detail: `Aynı hesap son 24 saatte ${signals.sellerListingsLast24h} ilan açmış.`,
    });
  }

  if (signals.sellerOpenReports > 0) {
    flags.push({
      key: 'open-reports',
      tone: 'warning',
      label: 'Açık şikâyet',
      detail: `Satıcı hakkında ${signals.sellerOpenReports} şikâyet Moderasyon Merkezi'nde hâlâ açık.`,
    });
  }

  return flags;
}

// The strongest flag decides the row's colour; a listing with a fraud report and
// a cheap price is not "a bit of both", it is the fraud report.
export const riskTone = (flags: RiskFlag[]) => (flags.some((flag) => flag.tone === 'danger') ? 'danger' : flags.length > 0 ? 'warning' : null);
