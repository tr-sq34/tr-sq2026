import { z } from 'zod';
import { delegation } from './gatework';
import { getSession } from './session';
import type { AuctionRow, ListingRow, MarketplaceOverview } from './marketplace-labels';
import type { GateworkRole } from './types';

/**
 * Console side of Çarşı ve İhaleler.
 *
 * Listings and auctions were the one member-created, money-adjacent area with
 * no operator view at all: the public endpoint returns active listings only and
 * auctions have no read endpoint, so a counterfeit listing could be found only
 * by scrolling the app as a member.
 *
 * The two acts here are deliberately narrow. A listing can be taken down or put
 * back, and an auction can be cancelled - both with a reason and an audit line.
 * Nothing here edits a member's price, title or description: rewriting somebody
 * else's listing and leaving their name on it is worse than removing it.
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
  LISTING_STATUS_LABELS, AUCTION_STATE_LABELS, LISTING_STATUS_ORDER, AUCTION_STATE_ORDER, money, sellerLabel, placeLabel,
} from './marketplace-labels';
export type { AuctionRow, ListingRow, MarketplaceOverview } from './marketplace-labels';

// Mirrors the service. Analyst and auditor read; content_editor does not - the
// listings are not editorial content, they are other people's property.
export const canSeeMarketplace = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin', 'operations_admin', 'moderator', 'analyst', 'auditor'].includes(role));
export const canActOnMarketplace = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin', 'operations_admin', 'moderator'].includes(role));

export const listingStatusSchema = z.object({
  status: z.enum(['active', 'inactive']),
  reason: z.string().trim().min(5, 'Gerekçe en az 5 karakter olmalı.').max(500),
});
export const auctionCancelSchema = z.object({ reason: z.string().trim().min(5, 'Gerekçe en az 5 karakter olmalı.').max(500) });

export async function listListings(params: { status?: string; query?: string; regionCode?: string } = {}): Promise<ListingRow[]> {
  const search = new URLSearchParams({ status: params.status ?? 'all', limit: '50' });
  if (params.query && params.query.trim().length >= 2) search.set('query', params.query.trim());
  if (params.regionCode) search.set('regionCode', params.regionCode);
  return (await communityFetch(`/v1/internal/gatework/marketplace/listings?${search}`)).data as ListingRow[];
}

export async function listAuctions(params: { state?: string } = {}): Promise<AuctionRow[]> {
  const search = new URLSearchParams({ state: params.state ?? 'all', limit: '50' });
  return (await communityFetch(`/v1/internal/gatework/marketplace/auctions?${search}`)).data as AuctionRow[];
}

export async function setListingStatus(id: string, raw: unknown) {
  const input = listingStatusSchema.parse(raw);
  return (await communityFetch(`/v1/internal/gatework/marketplace/listings/${id}/status`, { method: 'POST', body: JSON.stringify(input) }))
    .data as { id: string; status: string; cancelledAuctions: number };
}

export async function cancelAuction(id: string, raw: unknown) {
  const input = auctionCancelSchema.parse(raw);
  return (await communityFetch(`/v1/internal/gatework/marketplace/auctions/${id}/cancel`, { method: 'POST', body: JSON.stringify(input) })).data as { id: string; state: string };
}

// One page load, three calls, and a failed overview must not empty the lists:
// the counts are context, the rows are the work.
export async function marketplacePage(): Promise<{ overview: MarketplaceOverview | null; listings: ListingRow[]; auctions: AuctionRow[]; failure: string | null }> {
  try {
    const [overview, listings, auctions] = await Promise.all([
      communityFetch('/v1/internal/gatework/marketplace/overview').then((body) => body.data as MarketplaceOverview).catch(() => null),
      listListings(),
      listAuctions(),
    ]);
    return { overview, listings, auctions, failure: null };
  } catch (error) {
    return { overview: null, listings: [], auctions: [], failure: error instanceof Error ? error.message : 'Çarşı servisine ulaşılamadı.' };
  }
}
