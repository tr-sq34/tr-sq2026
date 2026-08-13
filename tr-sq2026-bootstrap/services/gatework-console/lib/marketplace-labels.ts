/**
 * Browser-safe half of the Çarşı ve İhaleler screen: row shapes and Turkish
 * labels. Split from lib/marketplace.ts for the same reason as the other label
 * modules - the screen is a client component and the server module reads the
 * session cookie.
 */

export type ListingRow = {
  id: string;
  title: string;
  description: string;
  price: number;
  status: string;
  city: string | null;
  regionCode: string | null;
  ownerId: string;
  ownerName: string | null;
  createdAt: string;
  updatedAt: string;
  auction: { id: string; state: string; bidCount: number } | null;
};

export type AuctionRow = {
  id: string;
  listingId: string;
  listingTitle: string;
  listingStatus: string;
  sellerId: string;
  sellerName: string | null;
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

export const LISTING_STATUS_ORDER = ['active', 'draft', 'reserved', 'sold', 'inactive'];
export const AUCTION_STATE_ORDER = ['active', 'scheduled', 'closed', 'cancelled'];

// Prices are stored as NUMERIC(12,2) and arrive as numbers; the app writes them
// in dollars, so the console does too rather than inventing a second unit.
export const money = (value: number) => value.toLocaleString('tr-TR', { style: 'currency', currency: 'USD', maximumFractionDigits: 2 });
export const sellerLabel = (row: { ownerName?: string | null; sellerName?: string | null; ownerId?: string; sellerId?: string }) =>
  row.ownerName ?? row.sellerName ?? `${(row.ownerId ?? row.sellerId ?? '').slice(0, 8)}…`;
export const placeLabel = (row: { city: string | null; regionCode: string | null }) => [row.city, row.regionCode].filter(Boolean).join(', ');
