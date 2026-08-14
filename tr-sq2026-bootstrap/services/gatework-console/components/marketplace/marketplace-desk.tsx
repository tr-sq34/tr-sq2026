'use client';
import { useCallback, useMemo, useState } from 'react';
import { AlertTriangle, Gavel, Search, ShieldAlert, Store, Users } from 'lucide-react';
import { apiData, errorText, formatDateTime } from '@/lib/api-client';
import {
  AUCTION_STATE_LABELS, AUCTION_STATE_ORDER, LISTING_CATEGORY_LABELS, LISTING_STATUS_LABELS, LISTING_STATUS_ORDER,
  RISK_RULES, categoryLabel, listingRiskFlags, money, placeLabel, riskTone, sellerLabel,
  type AuctionRow, type ListingRow, type MarketplaceOverview, type RiskFlag,
} from '@/lib/marketplace-labels';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { DataTable, type ColumnDef } from '@/components/ui/data-table';
import { Input, Select } from '@/components/ui/field';
import { ReasonDialog } from '@/components/ui/reason-dialog';
import { Sheet, SheetContent } from '@/components/ui/sheet';
import { StatCard } from '@/components/ui/stat-card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';

/**
 * Çarşı ve İhaleler.
 *
 * Two acts, both with a written reason: a listing goes down or comes back, an
 * auction is cancelled. There is no field here that rewrites a member's title,
 * price or description - editing somebody's listing while their name stays on
 * it is worse than taking it down, and taking it down is reversible.
 *
 * What is new is that the rows now carry what the service measured about them.
 * Before this, a listing was a title, a price and a name, and the only way to
 * notice a $60,000 car offered for $400 was to know what a car costs and to be
 * reading that particular row. The warnings are measurements with their own
 * sentence attached - never a score, never automatic - and the decision is
 * still a person's, with a reason that goes to the audit record.
 */
const AUCTION_TONE: Record<string, 'success' | 'brand' | 'neutral' | 'danger'> = {
  active: 'success',
  scheduled: 'brand',
  closed: 'neutral',
  cancelled: 'danger',
};
const LISTING_TONE: Record<string, 'success' | 'brand' | 'neutral' | 'danger'> = {
  active: 'success',
  draft: 'neutral',
  reserved: 'brand',
  sold: 'neutral',
  inactive: 'danger',
};

export function MarketplaceDesk({ initialOverview, initialListings, initialAuctions, initialFailure, canAct }: {
  initialOverview: MarketplaceOverview | null;
  initialListings: ListingRow[];
  initialAuctions: AuctionRow[];
  initialFailure: string | null;
  canAct: boolean;
}) {
  const [overview] = useState(initialOverview);
  const [listings, setListings] = useState(initialListings);
  const [auctions, setAuctions] = useState(initialAuctions);
  const [error, setError] = useState<string | null>(initialFailure);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [status, setStatus] = useState('all');
  const [category, setCategory] = useState('');
  const [query, setQuery] = useState('');
  const [onlyFlagged, setOnlyFlagged] = useState(false);
  const [state, setState] = useState('all');

  const [openListingId, setOpenListingId] = useState<string | null>(null);
  const [openAuctionId, setOpenAuctionId] = useState<string | null>(null);
  const [listingAction, setListingAction] = useState<{ row: ListingRow; next: 'active' | 'inactive' } | null>(null);
  const [auctionAction, setAuctionAction] = useState<AuctionRow | null>(null);

  const loadListings = useCallback(async (nextStatus: string, nextCategory: string, search: string) => {
    setBusy(true);
    try {
      const params = new URLSearchParams({ status: nextStatus });
      if (nextCategory) params.set('category', nextCategory);
      // The service wants at least two characters; sending one back means an
      // unfiltered list arriving as if it were a search result.
      if (search.trim().length >= 2) params.set('query', search.trim());
      setListings(await apiData<ListingRow[]>(`/api/marketplace/listings?${params}`));
      setError(null);
    } catch (caught) {
      setError(errorText(caught, 'İlanlar alınamadı.'));
    } finally {
      setBusy(false);
    }
  }, []);

  const loadAuctions = useCallback(async (nextState: string) => {
    setBusy(true);
    try {
      setAuctions(await apiData<AuctionRow[]>(`/api/marketplace/auctions?state=${nextState}`));
      setError(null);
    } catch (caught) {
      setError(errorText(caught, 'İhaleler alınamadı.'));
    } finally {
      setBusy(false);
    }
  }, []);

  // Computed once per list so the table, the counter and the row colour all read
  // the same flags rather than each recomputing them.
  const flagged = useMemo(
    () => new Map(listings.map((row) => [row.id, listingRiskFlags(row)] as const)),
    [listings],
  );
  const flaggedCount = useMemo(
    () => [...flagged.values()].filter((flags) => flags.length > 0).length,
    [flagged],
  );
  const visibleListings = useMemo(
    () => (onlyFlagged ? listings.filter((row) => (flagged.get(row.id)?.length ?? 0) > 0) : listings),
    [listings, flagged, onlyFlagged],
  );

  const openListing = listings.find((row) => row.id === openListingId) ?? null;
  const openAuction = auctions.find((row) => row.id === openAuctionId) ?? null;

  const listingColumns = useMemo<ColumnDef<ListingRow, unknown>[]>(
    () => [
      {
        id: 'title',
        header: 'İlan',
        accessorFn: (row) => `${row.title} ${row.ownerName ?? ''}`,
        cell: ({ row }) => (
          <div className="max-w-sm min-w-0">
            <p className="truncate font-medium text-ink">{row.original.title}</p>
            <p className="truncate text-xs text-ink-faint">
              {categoryLabel(row.original.category)}
              {placeLabel(row.original) ? ` · ${placeLabel(row.original)}` : ''} · {sellerLabel(row.original)}
            </p>
          </div>
        ),
      },
      {
        id: 'price',
        header: 'Fiyat',
        accessorFn: (row) => row.price,
        cell: ({ row }) => {
          const median = row.original.signals?.categoryMedianPrice ?? null;
          const sample = row.original.signals?.categorySample ?? 0;
          return (
            <div className="whitespace-nowrap">
              <p className="font-medium text-ink tabular-nums">{money(row.original.price)}</p>
              {/* The comparison is only shown where there is one; below the
                  sample size the median is a number two listings agreed on. */}
              <p className="text-xs text-ink-faint tabular-nums">
                {median !== null && sample >= RISK_RULES.minimumSample ? `ortanca ${money(median)}` : 'karşılaştırma yok'}
              </p>
            </div>
          );
        },
      },
      {
        id: 'status',
        header: 'Durum',
        accessorFn: (row) => row.status,
        cell: ({ row }) => (
          <div className="flex flex-wrap items-center gap-1.5">
            <Badge tone={LISTING_TONE[row.original.status] ?? 'neutral'} dot>
              {LISTING_STATUS_LABELS[row.original.status] ?? row.original.status}
            </Badge>
            {row.original.auction && (
              <Badge tone={AUCTION_TONE[row.original.auction.state] ?? 'neutral'}>
                <Gavel size={12} /> {AUCTION_STATE_LABELS[row.original.auction.state] ?? row.original.auction.state}
              </Badge>
            )}
          </div>
        ),
      },
      {
        id: 'risk',
        header: 'Uyarı',
        accessorFn: (row) => (listingRiskFlags(row).length > 0 ? 1 : 0),
        cell: ({ row }) => {
          const flags = flagged.get(row.original.id) ?? [];
          if (flags.length === 0) return <span className="text-xs text-ink-faint">—</span>;
          return (
            <div className="flex max-w-56 flex-wrap gap-1.5">
              {flags.slice(0, 2).map((flag) => (
                <Badge key={flag.key} tone={flag.tone}><AlertTriangle size={12} /> {flag.label}</Badge>
              ))}
              {flags.length > 2 && <Badge tone="neutral">+{flags.length - 2}</Badge>}
            </div>
          );
        },
      },
      {
        id: 'createdAt',
        header: 'Açılış',
        accessorFn: (row) => row.createdAt,
        cell: ({ row }) => <span className="text-xs whitespace-nowrap">{formatDateTime(row.original.createdAt)}</span>,
      },
      {
        id: 'actions',
        header: '',
        enableSorting: false,
        cell: ({ row }) => <Button size="sm" variant="outline" onClick={() => setOpenListingId(row.original.id)}>Aç</Button>,
      },
    ],
    [flagged],
  );

  const auctionColumns = useMemo<ColumnDef<AuctionRow, unknown>[]>(
    () => [
      {
        id: 'listing',
        header: 'İhale',
        accessorFn: (row) => `${row.listingTitle} ${row.sellerName ?? ''}`,
        cell: ({ row }) => (
          <div className="max-w-sm min-w-0">
            <p className="truncate font-medium text-ink">{row.original.listingTitle}</p>
            <p className="truncate text-xs text-ink-faint">satıcı: {sellerLabel(row.original)}</p>
          </div>
        ),
      },
      {
        id: 'state',
        header: 'Durum',
        accessorFn: (row) => row.state,
        cell: ({ row }) => (
          <div className="flex flex-wrap items-center gap-1.5">
            <Badge tone={AUCTION_TONE[row.original.state] ?? 'neutral'} dot>
              {AUCTION_STATE_LABELS[row.original.state] ?? row.original.state}
            </Badge>
            {auctionWarnings(row.original).map((flag) => (
              <Badge key={flag.key} tone={flag.tone}><AlertTriangle size={12} /> {flag.label}</Badge>
            ))}
          </div>
        ),
      },
      {
        id: 'bids',
        header: 'Teklif',
        accessorFn: (row) => row.bidCount,
        cell: ({ row }) => (
          <div className="whitespace-nowrap">
            <p className="text-ink tabular-nums">{row.original.bidCount} teklif</p>
            <p className="text-xs text-ink-faint tabular-nums">
              {row.original.topBid === null ? `açılış ${money(row.original.startingPrice)}` : `en yüksek ${money(row.original.topBid)}`}
            </p>
          </div>
        ),
      },
      {
        id: 'endsAt',
        header: 'Bitiş',
        accessorFn: (row) => row.endsAt,
        cell: ({ row }) => <span className="text-xs whitespace-nowrap">{formatDateTime(row.original.endsAt)}</span>,
      },
      {
        id: 'actions',
        header: '',
        enableSorting: false,
        cell: ({ row }) => <Button size="sm" variant="outline" onClick={() => setOpenAuctionId(row.original.id)}>Aç</Button>,
      },
    ],
    [],
  );

  async function applyListingStatus(reason: string) {
    if (!listingAction) return;
    const { row, next } = listingAction;
    const result = await apiData<{ status: string; cancelledAuctions: number }>(
      `/api/marketplace/listings/${row.id}/status`,
      { method: 'POST', body: JSON.stringify({ status: next, reason }) },
    );
    const label = LISTING_STATUS_LABELS[result.status]?.toLowerCase() ?? result.status;
    setNotice(result.cancelledAuctions > 0
      ? `İlan ${label}; üzerindeki ihale de iptal edildi.`
      : `İlan ${label}.`);
    setOpenListingId(null);
    await loadListings(status, category, query);
    if (result.cancelledAuctions > 0) await loadAuctions(state);
  }

  async function cancelAuction(reason: string) {
    if (!auctionAction) return;
    await apiData(`/api/marketplace/auctions/${auctionAction.id}/cancel`, { method: 'POST', body: JSON.stringify({ reason }) });
    setNotice('İhale iptal edildi; verilmiş teklifler kayıtta kalır.');
    setOpenAuctionId(null);
    await loadAuctions(state);
  }

  return (
    <div className="grid gap-6">
      {error && <div className="rounded-card border border-warning/30 bg-warning-soft p-4 text-sm text-warning">{error}</div>}
      {notice && <div className="rounded-card border border-success/30 bg-success-soft p-4 text-sm text-success">{notice}</div>}

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Yayındaki ilan"
          value={overview ? String(overview.listings.active ?? 0) : '—'}
          detail={overview ? `son 7 günde ${overview.newListingsLast7Days} yeni ilan` : 'Çarşı özeti okunamadı'}
          icon={Store}
          tone="brand"
          unavailable={!overview}
        />
        <StatCard
          label="Süren ihale"
          value={overview ? String(overview.auctions.active ?? 0) : '—'}
          detail={overview ? `${overview.endingSoon} tanesi 24 saat içinde bitiyor` : 'Çarşı özeti okunamadı'}
          icon={Gavel}
          unavailable={!overview}
        />
        <StatCard
          label="Uyarılı ilan"
          value={String(flaggedCount)}
          // Scoped on purpose: the signals arrive with the rows, so this counts
          // the page in front of the operator, not the whole marketplace.
          detail={`yüklenen ${listings.length} ilan içinde`}
          icon={ShieldAlert}
          tone={flaggedCount > 0 ? 'danger' : 'neutral'}
        />
        {/* İhale açmak Onaylı Hesap rozetine bağlı; bu sayı o rozeti taşıyan
            üye sayısıdır, yani ihale açabilecek kişi havuzu. */}
        <StatCard
          label="İhale yetkili üye"
          value={overview ? String(overview.eligibleSellers) : '—'}
          detail={overview ? `son 7 günde ${overview.bidsLast7Days} teklif verildi` : 'Çarşı özeti okunamadı'}
          icon={Users}
          unavailable={!overview}
        />
      </div>

      <Tabs defaultValue="listings">
        <TabsList>
          <TabsTrigger value="listings" count={listings.length}>İlanlar</TabsTrigger>
          <TabsTrigger value="auctions" count={auctions.length}>İhaleler</TabsTrigger>
        </TabsList>

        <TabsContent value="listings" className="mt-4 grid gap-3">
          <form
            className="flex flex-wrap gap-2"
            onSubmit={(event) => { event.preventDefault(); void loadListings(status, category, query); }}
          >
            <Select className="w-auto min-w-40" value={status} onChange={(event) => setStatus(event.target.value)} aria-label="Durum süzgeci">
              <option value="all">Tüm durumlar</option>
              {LISTING_STATUS_ORDER.map((key) => <option key={key} value={key}>{LISTING_STATUS_LABELS[key]}</option>)}
            </Select>
            <Select className="w-auto min-w-40" value={category} onChange={(event) => setCategory(event.target.value)} aria-label="Kategori süzgeci">
              <option value="">Tüm kategoriler</option>
              {Object.entries(LISTING_CATEGORY_LABELS).map(([key, label]) => <option key={key} value={key}>{label}</option>)}
            </Select>
            <Input
              className="min-w-56 flex-1"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Başlıkta ara (en az 2 harf)"
              aria-label="Başlıkta ara"
            />
            <Button type="submit" variant="secondary" disabled={busy}><Search size={15} /> {busy ? 'Okunuyor…' : 'Ara'}</Button>
          </form>

          <DataTable
            columns={listingColumns}
            rows={visibleListings}
            rowKey={(row) => row.id}
            onRowClick={(row) => setOpenListingId(row.id)}
            emptyLabel={onlyFlagged ? 'Yüklenen ilanların hiçbirinde uyarı yok.' : 'Bu süzgeçte ilan yok.'}
            isRowUrgent={(row) => riskTone(flagged.get(row.id) ?? []) === 'danger'}
            toolbar={
              <Button
                size="sm"
                variant={onlyFlagged ? 'primary' : 'outline'}
                onClick={() => setOnlyFlagged((current) => !current)}
              >
                <ShieldAlert size={14} /> {onlyFlagged ? 'Tüm ilanlar' : `Sadece uyarılı (${flaggedCount})`}
              </Button>
            }
            searchPlaceholder="Yüklenen ilanlar içinde ara"
          />
        </TabsContent>

        <TabsContent value="auctions" className="mt-4 grid gap-3">
          <form
            className="flex flex-wrap gap-2"
            onSubmit={(event) => { event.preventDefault(); void loadAuctions(state); }}
          >
            <Select className="w-auto min-w-40" value={state} onChange={(event) => setState(event.target.value)} aria-label="İhale durumu süzgeci">
              <option value="all">Tüm durumlar</option>
              {AUCTION_STATE_ORDER.map((key) => <option key={key} value={key}>{AUCTION_STATE_LABELS[key]}</option>)}
            </Select>
            <Button type="submit" variant="secondary" disabled={busy}>{busy ? 'Okunuyor…' : 'Yenile'}</Button>
          </form>

          <DataTable
            columns={auctionColumns}
            rows={auctions}
            rowKey={(row) => row.id}
            onRowClick={(row) => setOpenAuctionId(row.id)}
            emptyLabel="Bu süzgeçte ihale yok."
            isRowUrgent={(row) => auctionWarnings(row).length > 0}
            searchPlaceholder="Yüklenen ihaleler içinde ara"
          />
        </TabsContent>
      </Tabs>

      <Sheet open={openListing !== null} onOpenChange={(open) => { if (!open) setOpenListingId(null); }}>
        {openListing && (
          <SheetContent title={openListing.title} description={`${categoryLabel(openListing.category)} · ${sellerLabel(openListing)}`}>
            <ListingDetail
              row={openListing}
              flags={flagged.get(openListing.id) ?? []}
              canAct={canAct}
              onAct={(next) => setListingAction({ row: openListing, next })}
            />
          </SheetContent>
        )}
      </Sheet>

      <Sheet open={openAuction !== null} onOpenChange={(open) => { if (!open) setOpenAuctionId(null); }}>
        {openAuction && (
          <SheetContent title={openAuction.listingTitle} description={`İhale · ${sellerLabel(openAuction)}`}>
            <AuctionDetail row={openAuction} canAct={canAct} onCancel={() => setAuctionAction(openAuction)} />
          </SheetContent>
        )}
      </Sheet>

      <ReasonDialog
        open={listingAction !== null}
        onOpenChange={(open) => { if (!open) setListingAction(null); }}
        title={listingAction?.next === 'inactive' ? 'İlan yayından kaldırılacak' : 'İlan yeniden yayına alınacak'}
        description={
          listingAction?.next === 'inactive'
            ? `"${listingAction.row.title}" üyelere görünmez olur.${listingAction.row.auction && listingAction.row.auction.state === 'active' ? ` Üzerindeki ihale de iptal edilir; ${listingAction.row.auction.bidCount} teklif verilmiş durumda.` : ''}`
            : `"${listingAction?.row.title ?? ''}" yeniden çarşıda görünür. İptal edilen ihale geri gelmez.`
        }
        confirmLabel={listingAction?.next === 'inactive' ? 'Yayından kaldır' : 'Yayına al'}
        variant={listingAction?.next === 'inactive' ? 'danger' : 'success'}
        onConfirm={applyListingStatus}
      />

      <ReasonDialog
        open={auctionAction !== null}
        onOpenChange={(open) => { if (!open) setAuctionAction(null); }}
        title="İhale iptal edilecek"
        description={`"${auctionAction?.listingTitle ?? ''}" ihalesi yeni teklif almaz.${auctionAction && auctionAction.bidCount > 0 ? ` ${auctionAction.bidCount} teklif verilmiş; verilen teklifler kayıtta kalır.` : ''}`}
        confirmLabel="İhaleyi iptal et"
        variant="danger"
        onConfirm={cancelAuction}
      />
    </div>
  );
}

/**
 * The two things about an auction that cannot be seen from its own row.
 *
 * The badge is checked once, when the auction is opened, and the listing can be
 * taken down by a path that does not touch a scheduled auction. Both leave a
 * row that looks perfectly normal and is not.
 */
function auctionWarnings(row: AuctionRow): RiskFlag[] {
  if (row.state === 'cancelled' || row.state === 'closed') return [];
  const flags: RiskFlag[] = [];
  if (!row.sellerEligible) {
    flags.push({
      key: 'badge-revoked',
      tone: 'danger',
      label: 'Satıcının rozeti yok',
      detail: 'İhale açıldığında Onaylı Hesap rozeti vardı; şu anda yok. Rozet yalnızca açılışta kontrol edilir.',
    });
  }
  if (row.listingStatus !== 'active') {
    flags.push({
      key: 'listing-down',
      tone: 'warning',
      label: `İlan ${(LISTING_STATUS_LABELS[row.listingStatus] ?? row.listingStatus).toLowerCase()}`,
      detail: 'İhale sürüyor ama arkasındaki ilan çarşıda görünmüyor.',
    });
  }
  return flags;
}

function ListingDetail({ row, flags, canAct, onAct }: {
  row: ListingRow;
  flags: RiskFlag[];
  canAct: boolean;
  onAct: (next: 'active' | 'inactive') => void;
}) {
  const signals = row.signals;
  return (
    <div className="grid gap-5 p-5">
      <div className="flex flex-wrap items-center gap-2">
        <Badge tone={LISTING_TONE[row.status] ?? 'neutral'} dot>{LISTING_STATUS_LABELS[row.status] ?? row.status}</Badge>
        <Badge tone="neutral">{categoryLabel(row.category)}</Badge>
        <span className="text-sm font-semibold text-ink">{money(row.price)}</span>
      </div>

      {flags.length > 0 && (
        <div className="grid gap-2">
          {flags.map((flag) => (
            <div
              key={flag.key}
              className={`rounded-card border p-3 ${flag.tone === 'danger' ? 'border-danger/30 bg-danger-soft' : 'border-warning/30 bg-warning-soft'}`}
            >
              <p className={`flex items-center gap-1.5 text-sm font-medium ${flag.tone === 'danger' ? 'text-danger' : 'text-warning'}`}>
                <AlertTriangle size={14} /> {flag.label}
              </p>
              <p className="mt-1 text-sm text-ink-muted">{flag.detail}</p>
            </div>
          ))}
          {/* Said once, under the warnings, because it is the whole point: these
              are counts, not conclusions, and a warning is not a takedown. */}
          <p className="text-xs text-ink-faint">
            Bunlar ölçüm, karar değil. Hiçbiri tek başına dolandırıcılık kanıtı sayılmaz; ilanı yalnızca sen, gerekçe yazarak kaldırabilirsin.
          </p>
        </div>
      )}

      <div className="rounded-card border border-hairline bg-surface-raised p-4">
        <p className="text-sm leading-relaxed whitespace-pre-wrap text-ink-muted">{row.description}</p>
      </div>

      <dl className="grid gap-x-6 gap-y-3 text-sm sm:grid-cols-2">
        <div><dt className="text-xs text-ink-faint">Satıcı</dt><dd className="truncate text-ink">{sellerLabel(row)}</dd></div>
        <div><dt className="text-xs text-ink-faint">Konum</dt><dd className="text-ink">{placeLabel(row) || 'belirtilmemiş'}</dd></div>
        <div><dt className="text-xs text-ink-faint">Açılış</dt><dd className="text-ink">{formatDateTime(row.createdAt)}</dd></div>
        <div><dt className="text-xs text-ink-faint">Son güncelleme</dt><dd className="text-ink">{formatDateTime(row.updatedAt)}</dd></div>
      </dl>

      {signals ? (
        <div className="rounded-card border border-hairline p-4">
          <p className="text-xs font-medium tracking-wide text-ink-faint uppercase">Ölçümler</p>
          <dl className="mt-3 grid gap-x-6 gap-y-3 text-sm sm:grid-cols-2">
            <div>
              <dt className="text-xs text-ink-faint">Kategori ortancası</dt>
              <dd className="text-ink">
                {signals.categoryMedianPrice !== null && signals.categorySample >= RISK_RULES.minimumSample
                  ? `${money(signals.categoryMedianPrice)} · ${signals.categorySample} yayın ilan`
                  : `Karşılaştırma için yeterli ilan yok (${signals.categorySample} yayın ilan).`}
              </dd>
            </div>
            <div>
              <dt className="text-xs text-ink-faint">Satıcının ilanları</dt>
              <dd className="text-ink">{signals.sellerActiveListings} yayında · son 24 saatte {signals.sellerListingsLast24h} yeni</dd>
            </div>
            <div>
              <dt className="text-xs text-ink-faint">Satıcı şikâyetleri</dt>
              <dd className="text-ink">
                {signals.sellerOpenReports} açık · son 180 günde {signals.sellerFraudReports} dolandırıcılık
              </dd>
            </div>
            <div>
              <dt className="text-xs text-ink-faint">Kimlik doğrulaması</dt>
              <dd className="text-ink">{signals.sellerVerified ? 'Onaylı hesap' : 'Doğrulanmamış'}</dd>
            </div>
            <div className="sm:col-span-2">
              <dt className="text-xs text-ink-faint">Aynı başlık</dt>
              <dd className="text-ink">
                {signals.duplicateTitleOwners === 0
                  ? 'Bu başlık başka hesapta yok.'
                  : `${signals.duplicateTitleOwners} farklı hesapta daha aynı başlık var.`}
              </dd>
            </div>
          </dl>
        </div>
      ) : (
        <p className="text-xs text-ink-faint">Bu ilan için ölçüm okunamadı; uyarı olmaması uyarı yok anlamına gelmez.</p>
      )}

      {row.auction && (
        <div className="rounded-card border border-hairline p-4 text-sm">
          <p className="flex items-center gap-2 text-ink">
            <Gavel size={15} className="text-ink-faint" />
            İhale: <Badge tone={AUCTION_TONE[row.auction.state] ?? 'neutral'}>{AUCTION_STATE_LABELS[row.auction.state] ?? row.auction.state}</Badge>
            <span className="text-ink-muted">{row.auction.bidCount} teklif</span>
          </p>
        </div>
      )}

      {canAct && (
        <div className="flex flex-wrap gap-2 border-t border-hairline pt-5">
          {row.status === 'inactive'
            ? <Button variant="success" onClick={() => onAct('active')}>Yeniden yayına al</Button>
            : <Button variant="danger" onClick={() => onAct('inactive')}>Yayından kaldır</Button>}
          <p className="w-full text-xs text-ink-faint">
            Başlık, fiyat ve açıklama buradan değiştirilemez: başkasının ilanını, adı üstünde dururken yeniden yazmak kaldırmaktan daha ağırdır.
          </p>
        </div>
      )}
    </div>
  );
}

function AuctionDetail({ row, canAct, onCancel }: { row: AuctionRow; canAct: boolean; onCancel: () => void }) {
  const warnings = auctionWarnings(row);
  return (
    <div className="grid gap-5 p-5">
      <div className="flex flex-wrap items-center gap-2">
        <Badge tone={AUCTION_TONE[row.state] ?? 'neutral'} dot>{AUCTION_STATE_LABELS[row.state] ?? row.state}</Badge>
        <Badge tone={LISTING_TONE[row.listingStatus] ?? 'neutral'}>İlan: {LISTING_STATUS_LABELS[row.listingStatus] ?? row.listingStatus}</Badge>
      </div>

      {warnings.map((flag) => (
        <div
          key={flag.key}
          className={`rounded-card border p-3 ${flag.tone === 'danger' ? 'border-danger/30 bg-danger-soft' : 'border-warning/30 bg-warning-soft'}`}
        >
          <p className={`flex items-center gap-1.5 text-sm font-medium ${flag.tone === 'danger' ? 'text-danger' : 'text-warning'}`}>
            <AlertTriangle size={14} /> {flag.label}
          </p>
          <p className="mt-1 text-sm text-ink-muted">{flag.detail}</p>
        </div>
      ))}

      <dl className="grid gap-x-6 gap-y-3 text-sm sm:grid-cols-2">
        <div><dt className="text-xs text-ink-faint">Satıcı</dt><dd className="truncate text-ink">{sellerLabel(row)}</dd></div>
        <div><dt className="text-xs text-ink-faint">Teklif</dt><dd className="text-ink">{row.bidCount}</dd></div>
        <div><dt className="text-xs text-ink-faint">Açılış fiyatı</dt><dd className="text-ink">{money(row.startingPrice)}</dd></div>
        <div><dt className="text-xs text-ink-faint">Artış adımı</dt><dd className="text-ink">{money(row.minimumIncrement)}</dd></div>
        <div>
          <dt className="text-xs text-ink-faint">En yüksek teklif</dt>
          <dd className="text-ink">
            {row.topBid === null ? 'Henüz teklif yok' : `${money(row.topBid)}${row.topBidderName ? ` · ${row.topBidderName}` : ''}`}
          </dd>
        </div>
        <div><dt className="text-xs text-ink-faint">Rozet</dt><dd className="text-ink">{row.sellerEligible ? 'Onaylı hesap' : 'Rozet yok'}</dd></div>
        <div><dt className="text-xs text-ink-faint">Başlangıç</dt><dd className="text-ink">{formatDateTime(row.startsAt)}</dd></div>
        <div><dt className="text-xs text-ink-faint">Bitiş</dt><dd className="text-ink">{formatDateTime(row.endsAt)}</dd></div>
      </dl>

      {/* The stored column never advances, so it disagrees with the state shown
          on every finished auction. Saying so here stops the next person from
          reporting it as a bug. */}
      {row.storedStatus !== row.state && (
        <p className="text-xs text-ink-faint">
          Kayıttaki değer “{AUCTION_STATE_LABELS[row.storedStatus] ?? row.storedStatus}”. Ekranda gösterilen durum saatten türetilir; ihale kaydı yalnızca iptal edildiğinde güncellenir.
        </p>
      )}

      {canAct && row.state !== 'cancelled' && (
        <div className="border-t border-hairline pt-5">
          <Button variant="danger" onClick={onCancel}>İhaleyi iptal et</Button>
          <p className="mt-2 text-xs text-ink-faint">
            İptal yeni teklifleri durdurur; verilmiş teklifler kayıtta kalır, çünkü çoğu iptalin sebebi tam da o tekliflerdir.
          </p>
        </div>
      )}
    </div>
  );
}
