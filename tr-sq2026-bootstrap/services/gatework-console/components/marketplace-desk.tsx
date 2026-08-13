'use client';
import { useCallback, useState } from 'react';
import {
  AUCTION_STATE_LABELS, AUCTION_STATE_ORDER, LISTING_STATUS_LABELS, LISTING_STATUS_ORDER,
  money, placeLabel, sellerLabel, type AuctionRow, type ListingRow, type MarketplaceOverview,
} from '@/lib/marketplace-labels';

/**
 * Çarşı ve İhaleler.
 *
 * Two acts, both with a written reason: a listing goes down or comes back, an
 * auction is cancelled. There is no field here that rewrites a member's title,
 * price or description - editing somebody's listing while their name stays on
 * it is worse than taking it down, and taking it down is reversible.
 */
async function call<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, { ...init, headers: { 'content-type': 'application/json', ...(init?.headers ?? {}) } });
  const body = await response.json().catch(() => null);
  if (!response.ok) throw new Error(body?.error?.message ?? 'İşlem tamamlanamadı.');
  return body.data as T;
}

const time = (value: string) => new Date(value).toLocaleString('tr-TR', { dateStyle: 'short', timeStyle: 'short' });

const LISTING_TONE: Record<string, string> = {
  active: 'bg-emerald-500/10 text-emerald-300',
  draft: 'bg-zinc-800 text-zinc-400',
  reserved: 'bg-sky-500/10 text-sky-300',
  sold: 'bg-zinc-800 text-zinc-300',
  inactive: 'bg-rose-500/10 text-rose-300',
};
const AUCTION_TONE: Record<string, string> = {
  active: 'bg-emerald-500/10 text-emerald-300',
  scheduled: 'bg-sky-500/10 text-sky-300',
  closed: 'bg-zinc-800 text-zinc-400',
  cancelled: 'bg-rose-500/10 text-rose-300',
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
  const [tab, setTab] = useState<'listings' | 'auctions'>('listings');
  const [status, setStatus] = useState('all');
  const [query, setQuery] = useState('');
  const [state, setState] = useState('all');
  const [message, setMessage] = useState<string | null>(initialFailure);
  const [busy, setBusy] = useState(false);

  const loadListings = useCallback(async (nextStatus: string, search: string) => {
    setBusy(true);
    try {
      const params = new URLSearchParams({ status: nextStatus });
      if (search.trim().length >= 2) params.set('query', search.trim());
      setListings(await call<ListingRow[]>(`/api/marketplace/listings?${params}`));
      setMessage(null);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'İlanlar alınamadı.');
    } finally { setBusy(false); }
  }, []);

  const loadAuctions = useCallback(async (nextState: string) => {
    setBusy(true);
    try {
      setAuctions(await call<AuctionRow[]>(`/api/marketplace/auctions?state=${nextState}`));
      setMessage(null);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'İhaleler alınamadı.');
    } finally { setBusy(false); }
  }, []);

  // The reason is not paperwork: it is the only part of the record that says
  // why, and it is what the member is owed when they ask what happened.
  function ask(prompt_: string) {
    const reason = window.prompt(`${prompt_}\n\nGerekçe (denetim kaydına yazılır, en az 5 karakter):`)?.trim();
    if (!reason || reason.length < 5) { setMessage('Gerekçe en az 5 karakter olmalı; işlem yapılmadı.'); return null; }
    return reason;
  }

  async function changeListing(row: ListingRow, next: 'active' | 'inactive') {
    const reason = ask(next === 'inactive' ? `"${row.title}" yayından kaldırılacak.` : `"${row.title}" yeniden yayına alınacak.`);
    if (!reason) return;
    setBusy(true);
    try {
      const result = await call<{ status: string; cancelledAuctions: number }>(`/api/marketplace/listings/${row.id}/status`, { method: 'POST', body: JSON.stringify({ status: next, reason }) });
      setMessage(result.cancelledAuctions > 0
        ? `İlan ${LISTING_STATUS_LABELS[result.status]?.toLowerCase() ?? result.status}; üzerindeki ihale de iptal edildi.`
        : `İlan ${LISTING_STATUS_LABELS[result.status]?.toLowerCase() ?? result.status}.`);
      await loadListings(status, query);
      if (result.cancelledAuctions > 0) await loadAuctions(state);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'İlan durumu değiştirilemedi.');
    } finally { setBusy(false); }
  }

  async function cancel(row: AuctionRow) {
    const reason = ask(`"${row.listingTitle}" ihalesi iptal edilecek${row.bidCount > 0 ? `; ${row.bidCount} teklif verilmiş durumda` : ''}.`);
    if (!reason) return;
    setBusy(true);
    try {
      await call(`/api/marketplace/auctions/${row.id}/cancel`, { method: 'POST', body: JSON.stringify({ reason }) });
      setMessage('İhale iptal edildi; verilmiş teklifler kayıtta kalır.');
      await loadAuctions(state);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'İhale iptal edilemedi.');
    } finally { setBusy(false); }
  }

  const field = 'rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-emerald-400';
  const tabButton = (key: 'listings' | 'auctions', label: string) => (
    <button key={key} type="button" onClick={() => setTab(key)} className={`rounded-lg px-4 py-2 text-sm font-medium transition ${tab === key ? 'bg-emerald-400 text-zinc-950' : 'bg-zinc-800 text-zinc-300 hover:bg-zinc-700'}`}>{label}</button>
  );

  return (
    <div className="grid gap-6">
      {message && <p className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">{message}</p>}

      {overview && (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div className="rounded-xl border border-white/10 bg-zinc-900/40 p-4">
            <p className="text-2xl font-semibold">{overview.listings.active ?? 0}</p>
            <p className="mt-1 text-xs text-zinc-400">yayındaki ilan · son 7 günde {overview.newListingsLast7Days} yeni</p>
          </div>
          <div className="rounded-xl border border-white/10 bg-zinc-900/40 p-4">
            <p className="text-2xl font-semibold">{overview.auctions.active ?? 0}</p>
            <p className="mt-1 text-xs text-zinc-400">süren ihale · {overview.endingSoon} tanesi 24 saat içinde bitiyor</p>
          </div>
          <div className="rounded-xl border border-white/10 bg-zinc-900/40 p-4">
            <p className="text-2xl font-semibold">{overview.bidsLast7Days}</p>
            <p className="mt-1 text-xs text-zinc-400">son 7 gündeki teklif</p>
          </div>
          {/* İhale açmak Onaylı Hesap rozetine bağlı; bu sayı o rozeti taşıyan
              üye sayısıdır, yani ihale açabilecek kişi havuzu. */}
          <div className="rounded-xl border border-white/10 bg-zinc-900/40 p-4">
            <p className="text-2xl font-semibold">{overview.eligibleSellers}</p>
            <p className="mt-1 text-xs text-zinc-400">ihale açma yetkisi olan üye</p>
          </div>
        </div>
      )}

      <div className="flex flex-wrap gap-2">{tabButton('listings', `İlanlar (${listings.length})`)}{tabButton('auctions', `İhaleler (${auctions.length})`)}</div>

      {tab === 'listings' ? (
        <>
          <div className="flex flex-wrap items-end gap-3">
            <label className="text-sm">Durum
              <select value={status} onChange={(event) => { setStatus(event.target.value); void loadListings(event.target.value, query); }} className={`mt-1 block ${field}`}>
                <option value="all">Hepsi</option>
                {LISTING_STATUS_ORDER.map((key) => <option key={key} value={key}>{LISTING_STATUS_LABELS[key]}</option>)}
              </select>
            </label>
            <label className="text-sm">Başlıkta ara
              <input value={query} onChange={(event) => setQuery(event.target.value)} onKeyDown={(event) => { if (event.key === 'Enter') void loadListings(status, query); }} placeholder="en az 2 karakter" className={`mt-1 block w-56 ${field}`} />
            </label>
            <button type="button" disabled={busy} onClick={() => void loadListings(status, query)} className="rounded-lg bg-emerald-500 px-4 py-2 text-sm font-medium text-emerald-950 disabled:opacity-40">{busy ? 'Okunuyor…' : 'Ara'}</button>
          </div>

          <div className="grid gap-2">
            {listings.length === 0 && <p className="rounded-xl border border-white/10 bg-zinc-900/40 p-6 text-sm text-zinc-500">Bu filtreye uyan ilan yok.</p>}
            {listings.map((row) => (
              <article key={row.id} className="rounded-xl border border-white/10 bg-zinc-900/40 p-4">
                <div className="flex flex-wrap items-center gap-2 text-xs">
                  <span className={`rounded px-2 py-0.5 ${LISTING_TONE[row.status] ?? 'bg-zinc-800 text-zinc-300'}`}>{LISTING_STATUS_LABELS[row.status] ?? row.status}</span>
                  <span className="font-semibold text-zinc-200">{money(row.price)}</span>
                  {placeLabel(row) && <span className="text-zinc-500">{placeLabel(row)}</span>}
                  <span className="text-zinc-600">{time(row.createdAt)}</span>
                  {row.auction && <span className={`rounded px-2 py-0.5 ${AUCTION_TONE[row.auction.state] ?? 'bg-zinc-800 text-zinc-300'}`}>İhale: {AUCTION_STATE_LABELS[row.auction.state] ?? row.auction.state} · {row.auction.bidCount} teklif</span>}
                </div>
                <p className="mt-2 text-sm font-medium text-zinc-100">{row.title}</p>
                <p className="mt-1 line-clamp-3 text-sm text-zinc-400">{row.description}</p>
                <p className="mt-2 text-xs text-zinc-500">satıcı: {sellerLabel(row)}</p>
                {canAct && (
                  <div className="mt-3 flex flex-wrap gap-2">
                    {row.status === 'inactive'
                      ? <button type="button" disabled={busy} onClick={() => void changeListing(row, 'active')} className="rounded-lg border border-emerald-500/40 px-3 py-1.5 text-xs text-emerald-300 disabled:opacity-40">Yeniden yayına al</button>
                      : <button type="button" disabled={busy} onClick={() => void changeListing(row, 'inactive')} className="rounded-lg border border-rose-500/40 px-3 py-1.5 text-xs text-rose-300 disabled:opacity-40">Yayından kaldır</button>}
                  </div>
                )}
              </article>
            ))}
          </div>
        </>
      ) : (
        <>
          <div className="flex flex-wrap items-end gap-3">
            <label className="text-sm">Durum
              <select value={state} onChange={(event) => { setState(event.target.value); void loadAuctions(event.target.value); }} className={`mt-1 block ${field}`}>
                <option value="all">Hepsi</option>
                {AUCTION_STATE_ORDER.map((key) => <option key={key} value={key}>{AUCTION_STATE_LABELS[key]}</option>)}
              </select>
            </label>
            <button type="button" disabled={busy} onClick={() => void loadAuctions(state)} className="rounded-lg bg-emerald-500 px-4 py-2 text-sm font-medium text-emerald-950 disabled:opacity-40">{busy ? 'Okunuyor…' : 'Yenile'}</button>
          </div>

          <div className="grid gap-2">
            {auctions.length === 0 && <p className="rounded-xl border border-white/10 bg-zinc-900/40 p-6 text-sm text-zinc-500">Bu filtreye uyan ihale yok.</p>}
            {auctions.map((row) => (
              <article key={row.id} className="rounded-xl border border-white/10 bg-zinc-900/40 p-4">
                <div className="flex flex-wrap items-center gap-2 text-xs">
                  <span className={`rounded px-2 py-0.5 ${AUCTION_TONE[row.state] ?? 'bg-zinc-800 text-zinc-300'}`}>{AUCTION_STATE_LABELS[row.state] ?? row.state}</span>
                  <span className="text-zinc-500">{time(row.startsAt)} → {time(row.endsAt)}</span>
                  <span className="text-zinc-600">{row.bidCount} teklif</span>
                  {row.listingStatus !== 'active' && <span className="rounded bg-rose-500/10 px-2 py-0.5 text-rose-300">ilan {LISTING_STATUS_LABELS[row.listingStatus] ?? row.listingStatus}</span>}
                </div>
                <p className="mt-2 text-sm font-medium text-zinc-100">{row.listingTitle}</p>
                <p className="mt-1 text-sm text-zinc-300">
                  açılış {money(row.startingPrice)} · artış adımı {money(row.minimumIncrement)}
                  {row.topBid !== null && <> · en yüksek <span className="font-semibold text-emerald-300">{money(row.topBid)}</span>{row.topBidderName ? ` (${row.topBidderName})` : ''}</>}
                </p>
                <p className="mt-2 text-xs text-zinc-500">satıcı: {sellerLabel(row)}</p>
                {canAct && row.state !== 'cancelled' && (
                  <div className="mt-3">
                    <button type="button" disabled={busy} onClick={() => void cancel(row)} className="rounded-lg border border-rose-500/40 px-3 py-1.5 text-xs text-rose-300 disabled:opacity-40">İhaleyi iptal et</button>
                  </div>
                )}
              </article>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
