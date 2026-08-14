'use client';
import { useCallback, useState } from 'react';
import {
  EVENT_CATEGORIES, EVENT_STATUS_LABELS, attendanceLabel, categoryLabel, eventStatusTone, eventWhen, placeLabel, type EventRow,
} from '@/lib/events-labels';

/**
 * Etkinlikler.
 *
 * The app's Etkinlikler tab has been showing four invented meetups to everybody
 * since the first release. This is where the real ones get written.
 *
 * An event is a promise that somebody will be somewhere at a stated time, so
 * publishing it is signed and audited, and cancelling it takes a reason the
 * members who planned around it can read. Nothing here shows who is coming -
 * only how many. A list of names would be a record of who was where on a given
 * evening, which is the record this service is built not to keep.
 */
async function call<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, { ...init, headers: { 'content-type': 'application/json', ...(init?.headers ?? {}) } });
  const body = await response.json().catch(() => null);
  if (!response.ok) throw new Error(body?.error?.message ?? 'İşlem tamamlanamadı.');
  return body?.data as T;
}

const TONE: Record<string, string> = {
  published: 'bg-emerald-500/10 text-emerald-300',
  draft: 'bg-amber-500/10 text-amber-300',
  cancelled: 'bg-rose-500/10 text-rose-300',
};

const EMPTY = {
  title: '', description: '', category: 'Community', startsAt: '', endsAt: '',
  venueLabel: '', city: '', regionCode: '', priceLabel: 'Ücretsiz', externalUrl: '', capacity: '',
};

export function EventsDesk({ initialPublished, initialDrafts, initialCancelled, initialFailure, canPublish }: {
  initialPublished: EventRow[];
  initialDrafts: EventRow[];
  initialCancelled: EventRow[];
  initialFailure: string | null;
  canPublish: boolean;
}) {
  const [rows, setRows] = useState<Record<string, EventRow[]>>({ published: initialPublished, draft: initialDrafts, cancelled: initialCancelled });
  const [tab, setTab] = useState<'published' | 'draft' | 'cancelled'>('published');
  const [form, setForm] = useState(EMPTY);
  const [composerOpen, setComposerOpen] = useState(false);
  const [message, setMessage] = useState<string | null>(initialFailure);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async (status: string) => {
    setBusy(true);
    try {
      setRows((current) => ({ ...current, [status]: [] }));
      const data = await call<EventRow[]>(`/api/events?status=${status}`);
      setRows((current) => ({ ...current, [status]: data }));
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Etkinlikler alınamadı.');
    } finally { setBusy(false); }
  }, []);

  async function submit(publish: boolean) {
    setBusy(true);
    try {
      const payload = {
        ...form,
        externalUrl: form.externalUrl.trim() || undefined,
        capacity: form.capacity.trim() ? Number(form.capacity) : undefined,
        publish,
      };
      await call<{ id: string }>('/api/events', { method: 'POST', body: JSON.stringify(payload) });
      setMessage(publish ? 'Etkinlik yayında; uygulamadaki Etkinlikler sekmesinde görünüyor.' : 'Taslak kaydedildi; yayına almadan kimse görmüyor.');
      setForm(EMPTY);
      setComposerOpen(false);
      const target = publish ? 'published' : 'draft';
      setTab(target);
      await load(target);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Etkinlik kaydedilemedi.');
    } finally { setBusy(false); }
  }

  async function publishRow(row: EventRow) {
    setBusy(true);
    try {
      await call(`/api/events/${row.id}/publish`, { method: 'POST' });
      setMessage(`"${row.title}" yayında.`);
      await Promise.all([load('draft'), load('published')]);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Etkinlik yayınlanamadı.');
    } finally { setBusy(false); }
  }

  async function cancelRow(row: EventRow) {
    // İptal gerekçesi kâğıt işi değil: o akşamı ayıran üyenin okuyacağı tek
    // cümle bu.
    const reason = window.prompt(`"${row.title}" iptal edilecek.\n\nGerekçe (denetim kaydına yazılır ve üyeye gösterilir, en az 5 karakter):`)?.trim();
    if (!reason || reason.length < 5) { setMessage('Gerekçe en az 5 karakter olmalı; işlem yapılmadı.'); return; }
    setBusy(true);
    try {
      await call(`/api/events/${row.id}/cancel`, { method: 'POST', body: JSON.stringify({ reason }) });
      setMessage('Etkinlik iptal edildi; kayıt ve gerekçe duruyor.');
      await Promise.all([load(row.status), load('cancelled')]);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Etkinlik iptal edilemedi.');
    } finally { setBusy(false); }
  }

  const field = 'rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-emerald-400';
  const set = (key: keyof typeof EMPTY) => (event: { target: { value: string } }) => setForm((current) => ({ ...current, [key]: event.target.value }));
  const tabButton = (key: 'published' | 'draft' | 'cancelled') => (
    <button key={key} type="button" onClick={() => { setTab(key); void load(key); }} className={`rounded-lg px-4 py-2 text-sm font-medium transition ${tab === key ? 'bg-emerald-400 text-zinc-950' : 'bg-zinc-800 text-zinc-300 hover:bg-zinc-700'}`}>
      {EVENT_STATUS_LABELS[key]} ({rows[key]?.length ?? 0})
    </button>
  );

  const list = rows[tab] ?? [];

  return (
    <div className="grid gap-6">
      {message && <p className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">{message}</p>}

      {canPublish && (
        <div className="rounded-xl border border-white/10 bg-zinc-900/40 p-4">
          <div className="flex items-center justify-between gap-3">
            <div>
              <p className="text-sm font-medium text-zinc-100">Yeni etkinlik</p>
              <p className="mt-1 text-xs text-zinc-500">Yayınlanan etkinlik uygulamadaki Etkinlikler sekmesinde, senin adına ve denetim kaydıyla görünür.</p>
            </div>
            <button type="button" onClick={() => setComposerOpen((open) => !open)} className="rounded-lg bg-emerald-500 px-4 py-2 text-sm font-medium text-emerald-950">{composerOpen ? 'Kapat' : 'Etkinlik oluştur'}</button>
          </div>

          {composerOpen && (
            <div className="mt-4 grid gap-3 border-t border-white/10 pt-4 sm:grid-cols-2">
              <label className="text-sm sm:col-span-2">Başlık<input value={form.title} onChange={set('title')} className={`mt-1 block w-full ${field}`} placeholder="Türk Kahvaltısı Buluşması" /></label>
              <label className="text-sm sm:col-span-2">Açıklama<textarea value={form.description} onChange={set('description')} rows={3} className={`mt-1 block w-full ${field}`} placeholder="Ne olacağı, kimin için, ne getirmeli." /></label>
              <label className="text-sm">Kategori
                <select value={form.category} onChange={set('category')} className={`mt-1 block w-full ${field}`}>
                  {EVENT_CATEGORIES.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                </select>
              </label>
              <label className="text-sm">Ücret<input value={form.priceLabel} onChange={set('priceLabel')} className={`mt-1 block w-full ${field}`} placeholder="Ücretsiz / Kapıda 20$" /></label>
              <label className="text-sm">Başlangıç<input type="datetime-local" value={form.startsAt} onChange={set('startsAt')} className={`mt-1 block w-full ${field}`} /></label>
              <label className="text-sm">Bitiş (isteğe bağlı)<input type="datetime-local" value={form.endsAt} onChange={set('endsAt')} className={`mt-1 block w-full ${field}`} /></label>
              <label className="text-sm sm:col-span-2">Mekân<input value={form.venueLabel} onChange={set('venueLabel')} className={`mt-1 block w-full ${field}`} placeholder="Anadolu Kültür Merkezi, 214 5th Ave" /></label>
              <label className="text-sm">Şehir<input value={form.city} onChange={set('city')} className={`mt-1 block w-full ${field}`} placeholder="Brooklyn" /></label>
              <label className="text-sm">Eyalet kodu<input value={form.regionCode} onChange={(event) => setForm((current) => ({ ...current, regionCode: event.target.value.toUpperCase().slice(0, 2) }))} className={`mt-1 block w-full ${field}`} placeholder="NY" /></label>
              <label className="text-sm">Kontenjan (isteğe bağlı)<input value={form.capacity} onChange={set('capacity')} inputMode="numeric" className={`mt-1 block w-full ${field}`} placeholder="boş = sınırsız" /></label>
              <label className="text-sm">Kayıt bağlantısı (isteğe bağlı)<input value={form.externalUrl} onChange={set('externalUrl')} className={`mt-1 block w-full ${field}`} placeholder="https://…" /></label>
              <div className="flex flex-wrap gap-2 sm:col-span-2">
                <button type="button" disabled={busy} onClick={() => void submit(true)} className="rounded-lg bg-emerald-500 px-4 py-2 text-sm font-medium text-emerald-950 disabled:opacity-40">{busy ? 'Kaydediliyor…' : 'Yayınla'}</button>
                <button type="button" disabled={busy} onClick={() => void submit(false)} className="rounded-lg border border-zinc-600 px-4 py-2 text-sm text-zinc-300 disabled:opacity-40">Taslak olarak kaydet</button>
              </div>
            </div>
          )}
        </div>
      )}

      <div className="flex flex-wrap gap-2">{tabButton('published')}{tabButton('draft')}{tabButton('cancelled')}</div>

      <div className="grid gap-2">
        {list.length === 0 && <p className="rounded-xl border border-white/10 bg-zinc-900/40 p-6 text-sm text-zinc-500">{busy ? 'Okunuyor…' : `${EVENT_STATUS_LABELS[tab]} durumunda etkinlik yok.`}</p>}
        {list.map((row) => (
          <article key={row.id} className="rounded-xl border border-white/10 bg-zinc-900/40 p-4">
            <div className="flex flex-wrap items-center gap-2 text-xs">
              <span className={`rounded px-2 py-0.5 ${TONE[row.status] ?? 'bg-zinc-800 text-zinc-300'}`}>{EVENT_STATUS_LABELS[row.status] ?? row.status}</span>
              <span className="text-zinc-400">{categoryLabel(row.category)}</span>
              <span className={eventStatusTone(row.status)}>{eventWhen(row.startsAt, row.endsAt)}</span>
              <span className="text-zinc-500">{row.priceLabel}</span>
            </div>
            <p className="mt-2 text-sm font-medium text-zinc-100">{row.title}</p>
            {row.description && <p className="mt-1 line-clamp-3 text-sm text-zinc-400">{row.description}</p>}
            <p className="mt-2 text-xs text-zinc-500">{placeLabel(row)}</p>
            <p className="mt-1 text-xs text-zinc-500">{attendanceLabel(row)}</p>
            {row.cancellationReason && <p className="mt-2 rounded-lg border border-rose-500/20 bg-rose-500/5 p-2 text-xs text-rose-200">İptal gerekçesi: {row.cancellationReason}</p>}
            {canPublish && row.status !== 'cancelled' && (
              <div className="mt-3 flex flex-wrap gap-2">
                {row.status === 'draft' && <button type="button" disabled={busy} onClick={() => void publishRow(row)} className="rounded-lg border border-emerald-500/40 px-3 py-1.5 text-xs text-emerald-300 disabled:opacity-40">Yayınla</button>}
                <button type="button" disabled={busy} onClick={() => void cancelRow(row)} className="rounded-lg border border-rose-500/40 px-3 py-1.5 text-xs text-rose-300 disabled:opacity-40">İptal et</button>
              </div>
            )}
          </article>
        ))}
      </div>
    </div>
  );
}
