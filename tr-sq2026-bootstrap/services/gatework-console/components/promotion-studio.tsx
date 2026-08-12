'use client';
import { useCallback, useEffect, useState } from 'react';
import { PROMOTION_PLACEMENT_LABELS, PROMOTION_STATUS_LABELS, type PromotionSummary } from '@/lib/promotion-labels';

async function call<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, { ...init, headers: { 'content-type': 'application/json', ...(init?.headers ?? {}) } });
  const body = await response.json().catch(() => null);
  if (!response.ok) throw new Error(body?.error?.message ?? 'İşlem tamamlanamadı.');
  return body.data as T;
}

const time = (value: string) => new Date(value).toLocaleString('tr-TR', { dateStyle: 'short', timeStyle: 'short' });
// `datetime-local` hands over a local wall clock with no zone. The instant is
// settled once, here, so an operator in Istanbul and one in New Jersey do not
// disagree about when a placement starts.
const instant = (value: FormDataEntryValue | null) => (value ? new Date(String(value)).toISOString() : undefined);

/// Tanitim Yap's console side: the approval queue on the left, and - below it -
/// the form for placements the panel makes itself. Both write to the same table
/// because a placed promotion is a requested one with the answer already given.
export function PromotionStudio() {
  const [status, setStatus] = useState('pending');
  const [rows, setRows] = useState<PromotionSummary[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async (next: string) => {
    setStatus(next);
    try {
      const data = await call<PromotionSummary[]>(`/api/promotions?status=${next}`);
      setRows(data);
      setSelectedId(data[0]?.id ?? null);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Liste yenilenemedi.');
    }
  }, []);

  useEffect(() => { void refresh('pending'); }, [refresh]);

  const detail = rows.find((row) => row.id === selectedId) ?? null;

  async function decide(form: FormData) {
    if (!detail) return;
    setBusy(true); setMessage(null);
    try {
      await call(`/api/promotions/${detail.id}/decision`, {
        method: 'POST',
        body: JSON.stringify({ action: form.get('action'), reason: form.get('reason') }),
      });
      setMessage('Karar kaydedildi.');
      await refresh(status);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Karar kaydedilemedi.');
    } finally {
      setBusy(false);
    }
  }

  async function place(form: FormData) {
    setBusy(true); setMessage(null);
    try {
      const created = await call<{ id: string }>('/api/promotions', {
        method: 'POST',
        body: JSON.stringify({
          placement: form.get('placement'),
          ownerId: form.get('ownerId'),
          title: form.get('title'),
          subtitle: String(form.get('subtitle') ?? '').trim() || undefined,
          mediaId: String(form.get('mediaId') ?? '').trim() || undefined,
          targetKind: String(form.get('targetKind') ?? '').trim() || undefined,
          targetValue: String(form.get('targetValue') ?? '').trim() || undefined,
          regionCode: String(form.get('regionCode') ?? '').trim() || undefined,
          city: String(form.get('city') ?? '').trim() || undefined,
          startsAt: instant(form.get('startsAt')),
          endsAt: instant(form.get('endsAt')),
          reason: form.get('reason'),
        }),
      });
      setMessage(`Tanıtım yayına alındı: ${created.id}`);
      await refresh('approved');
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Tanıtım yerleştirilemedi.');
    } finally {
      setBusy(false);
    }
  }

  const field = 'mt-1 w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-emerald-400';

  return (
    <div className="grid gap-8">
      <section className="grid gap-6 xl:grid-cols-[380px_1fr]">
        <div className="rounded-xl border border-white/10 bg-zinc-900/40">
          <div className="flex flex-wrap gap-2 border-b border-white/10 p-3">
            {[['pending', 'Onay bekleyen'], ['approved', 'Onaylı'], ['rejected', 'Reddedilen'], ['ended', 'Sonlandırılan']].map(([value, label]) => (
              <button key={value} type="button" onClick={() => void refresh(value)} className={`rounded-lg px-3 py-1.5 text-xs font-medium ${status === value ? 'bg-emerald-400 text-zinc-950' : 'bg-zinc-800 text-zinc-300'}`}>{label}</button>
            ))}
          </div>
          <ul className="max-h-[60vh] divide-y divide-white/5 overflow-y-auto">
            {rows.length === 0 && <li className="p-6 text-sm text-zinc-500">Bu filtrede tanıtım yok.</li>}
            {rows.map((row) => (
              <li key={row.id}>
                <button type="button" onClick={() => setSelectedId(row.id)} className={`w-full px-4 py-3 text-left transition ${selectedId === row.id ? 'bg-zinc-800' : 'hover:bg-zinc-800/50'}`}>
                  <div className="flex items-center justify-between gap-2">
                    <span className="rounded bg-zinc-700 px-1.5 py-0.5 text-[11px] font-semibold text-zinc-200">{PROMOTION_PLACEMENT_LABELS[row.placement] ?? row.placement}</span>
                    <span className="text-[11px] text-zinc-500">{time(row.createdAt)}</span>
                  </div>
                  <p className="mt-1.5 truncate text-sm text-zinc-200">{row.title}</p>
                  <p className="truncate text-xs text-zinc-500">{row.ownerName} · {row.city ?? row.regionCode ?? 'Tüm ülke'}</p>
                </button>
              </li>
            ))}
          </ul>
        </div>

        <div className="rounded-xl border border-white/10 bg-zinc-900/40 p-6">
          {!detail && <p className="text-sm text-zinc-500">Soldan bir tanıtım seç.</p>}
          {detail && (
            <>
              <div className="flex flex-wrap items-center gap-3">
                <h2 className="text-xl font-semibold">{detail.title}</h2>
                <span className="rounded bg-zinc-800 px-2 py-0.5 text-xs text-zinc-300">{PROMOTION_STATUS_LABELS[detail.status] ?? detail.status}</span>
                <span className="rounded bg-zinc-800 px-2 py-0.5 text-xs text-zinc-300">{PROMOTION_PLACEMENT_LABELS[detail.placement] ?? detail.placement}</span>
              </div>
              {detail.subtitle && <p className="mt-2 text-sm text-zinc-400">{detail.subtitle}</p>}
              <dl className="mt-4 grid gap-x-8 gap-y-2 text-sm sm:grid-cols-2">
                <div><dt className="text-zinc-500">İsteyen</dt><dd className="text-zinc-200">{detail.ownerName}</dd></div>
                <div><dt className="text-zinc-500">Hedef kitle</dt><dd className="text-zinc-200">{[detail.city, detail.regionCode].filter(Boolean).join(', ') || 'Tüm ülke'}</dd></div>
                <div><dt className="text-zinc-500">Başlangıç</dt><dd className="text-zinc-200">{time(detail.startsAt)}</dd></div>
                <div><dt className="text-zinc-500">Bitiş</dt><dd className="text-zinc-200">{time(detail.endsAt)}</dd></div>
                <div><dt className="text-zinc-500">Bağlantı</dt><dd className="text-zinc-200">{detail.targetValue ? `${detail.targetKind}: ${detail.targetValue}` : 'Yok'}</dd></div>
              </dl>
              {detail.requestNote && <p className="mt-4 rounded-lg border border-white/10 bg-zinc-950/60 p-3 text-sm text-zinc-300"><span className="text-zinc-500">Gerekçesi: </span>{detail.requestNote}</p>}
              {/* The image an operator is approving, not a placeholder: the
                  decision is about what members will actually see. */}
              {detail.imageUrl && <img src={detail.imageUrl} alt="" className="mt-4 max-h-64 rounded-lg border border-white/10 object-cover" />}
              {detail.decisionReason && <p className="mt-4 rounded-lg border border-white/10 bg-zinc-950/60 p-3 text-sm text-zinc-300"><span className="text-zinc-500">Karar notu: </span>{detail.decisionReason}</p>}

              {(detail.status === 'pending' || detail.status === 'approved') && (
                <form action={decide} className="mt-6 rounded-xl border border-white/10 bg-zinc-950/40 p-5">
                  <h3 className="font-semibold">Karar</h3>
                  <label className="mt-4 block text-sm">İşlem
                    <select name="action" className={field} defaultValue={detail.status === 'approved' ? 'end' : 'approve'}>
                      {detail.status === 'pending' && <option value="approve">Onayla — yayına alsın</option>}
                      {detail.status === 'pending' && <option value="reject">Reddet</option>}
                      {detail.status === 'approved' && <option value="end">Yayından kaldır</option>}
                    </select>
                  </label>
                  <label className="mt-4 block text-sm">Gerekçe <span className="text-zinc-600">(üyeye gösterilir ve denetim kaydına yazılır)</span>
                    <textarea name="reason" required minLength={3} maxLength={500} rows={3} className={field} />
                  </label>
                  <button disabled={busy} className="mt-4 rounded-lg bg-emerald-400 px-4 py-2 text-sm font-semibold text-zinc-950 disabled:opacity-40">Kararı uygula</button>
                </form>
              )}
            </>
          )}
          {message && <p className="mt-4 rounded-lg border border-white/10 bg-zinc-900 p-3 text-sm text-zinc-300">{message}</p>}
        </div>
      </section>

      <form action={place} className="grid max-w-3xl gap-4 rounded-xl border border-white/10 bg-zinc-900/40 p-6">
        <div>
          <h2 className="font-semibold">Panelden tanıtım yerleştir</h2>
          <p className="mt-1 text-sm text-zinc-500">Onay adımı yok: yerleştiren kişi zaten onaylayacak kişidir, işlem denetim kaydına bu şekilde yazılır. &quot;Sana Özel Öne Çıkanlar&quot; kartları yalnızca buradan girilir.</p>
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="block text-sm">Alan
            <select name="placement" className={field} defaultValue="featured_card">
              <option value="featured_card">Sana Özel Öne Çıkanlar</option>
              <option value="story_slot">Story alanı (sponsorlu)</option>
              <option value="app_banner">Uygulama içi banner</option>
            </select>
          </label>
          <label className="block text-sm">Sahip hesap ID<input className={field} name="ownerId" required placeholder="Resmî hesap ya da üye kimliği" /></label>
        </div>
        <label className="block text-sm">Başlık<input className={field} name="title" required minLength={3} maxLength={120} /></label>
        <label className="block text-sm">Alt satır <span className="text-zinc-600">(isteğe bağlı)</span><input className={field} name="subtitle" maxLength={200} /></label>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="block text-sm">Görsel medya ID <span className="text-zinc-600">(isteğe bağlı)</span><input className={field} name="mediaId" placeholder="Taranmış medya kimliği" /></label>
          <label className="block text-sm">Bağlantı türü
            <select name="targetKind" className={field} defaultValue="">
              <option value="">Yok</option>
              <option value="post">Paylaşım</option>
              <option value="listing">İlan</option>
              <option value="news">Haber</option>
              <option value="event">Etkinlik</option>
              <option value="external">Dış bağlantı</option>
            </select>
          </label>
          <label className="block text-sm">Bağlantı değeri<input className={field} name="targetValue" maxLength={500} placeholder="Kimlik ya da https://..." /></label>
          <label className="block text-sm">Eyalet kodu <span className="text-zinc-600">(boşsa tüm ülke)</span><input className={field} name="regionCode" maxLength={2} placeholder="NJ" /></label>
          <label className="block text-sm">Şehir <span className="text-zinc-600">(eyaletle birlikte)</span><input className={field} name="city" maxLength={80} placeholder="Paterson" /></label>
          <label className="block text-sm">Başlangıç<input className={field} name="startsAt" type="datetime-local" required /></label>
          <label className="block text-sm">Bitiş<input className={field} name="endsAt" type="datetime-local" required /></label>
        </div>
        <label className="block text-sm">İşlem nedeni<textarea className={field} name="reason" required minLength={5} maxLength={500} rows={2} placeholder="Denetim kaydına yazılır" /></label>
        <button disabled={busy} className="justify-self-start rounded-lg bg-emerald-400 px-4 py-2 text-sm font-semibold text-zinc-950 disabled:opacity-40">{busy ? 'Gönderiliyor...' : 'Tanıtımı yayına al'}</button>
      </form>
    </div>
  );
}
