'use client';
import { useCallback, useEffect, useState } from 'react';
import { SOS_KIND_LABELS, SOS_STATUS_LABELS, SOS_STATUS_TONE, isOpen, memberLabel, sosTime, waitedFor, type SosAlert, type SosLocation } from '@/lib/safety-labels';

/**
 * Güvenlik ve SOS.
 *
 * The queue refreshes itself: an emergency console that only updates when
 * somebody clicks is a console that shows an empty screen while a member waits.
 *
 * A coordinate is never in the list state. It is fetched per alert, only after
 * the operator has written a reason, and it is dropped from component state the
 * moment the alert is closed - the seal is in the service, but the screen has no
 * business holding a copy of what the service is protecting.
 */
type Props = { initialAlerts: SosAlert[]; initialFailure: string | null; canAct: boolean };

const REFRESH_MS = 20_000;

export function SafetyDesk({ initialAlerts, initialFailure, canAct }: Props) {
  const [alerts, setAlerts] = useState(initialAlerts);
  const [failure, setFailure] = useState(initialFailure);
  const [state, setState] = useState('open');
  const [busy, setBusy] = useState<string | null>(null);
  const [points, setPoints] = useState<Record<string, SosLocation>>({});
  // Recomputed on every refresh so "waited 12 min" does not freeze at the value
  // it had when the page was opened.
  const [now, setNow] = useState(() => Date.now());

  const load = useCallback(async (next: string) => {
    try {
      const response = await fetch(`/api/safety?state=${next}`, { headers: { 'content-type': 'application/json' } });
      const body = await response.json().catch(() => null);
      if (!response.ok) throw new Error(body?.error?.message ?? 'Çağrılar alınamadı.');
      setAlerts(body.data.alerts as SosAlert[]);
      setFailure((body.meta?.failure as string | null) ?? null);
      setNow(Date.now());
    } catch (error) {
      setFailure(error instanceof Error ? error.message : 'Çağrılar alınamadı.');
    }
  }, []);

  useEffect(() => {
    const timer = setInterval(() => void load(state), REFRESH_MS);
    return () => clearInterval(timer);
  }, [load, state]);

  const act = useCallback(async (id: string, path: string, body?: unknown) => {
    setBusy(id);
    try {
      const response = await fetch(`/api/safety/alerts/${id}/${path}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      const payload = await response.json().catch(() => null);
      if (!response.ok) throw new Error(payload?.error?.message ?? 'İşlem tamamlanamadı.');
      await load(state);
      return payload?.data ?? null;
    } catch (error) {
      setFailure(error instanceof Error ? error.message : 'İşlem tamamlanamadı.');
      return null;
    } finally {
      setBusy(null);
    }
  }, [load, state]);

  const unseal = useCallback(async (alert: SosAlert) => {
    const reason = window.prompt('Konumu neden görmen gerekiyor? Bu gerekçe kayda geçer ve üyeye gösterilebilir.');
    if (!reason || reason.trim().length < 5) return;
    const granted = await act(alert.id, 'location-access', { reason: reason.trim(), minutes: 30 });
    if (!granted) return;
    const response = await fetch(`/api/safety/alerts/${alert.id}/location`, { headers: { 'content-type': 'application/json' } });
    const body = await response.json().catch(() => null);
    if (!response.ok) { setFailure(body?.error?.message ?? 'Konum okunamadı.'); return; }
    setPoints((current) => ({ ...current, [alert.id]: body.data as SosLocation }));
  }, [act]);

  const close = useCallback(async (alert: SosAlert) => {
    const reason = window.prompt('Çağrı nasıl kapandı? Kısaca yaz — bu, olayın kaydı olacak.');
    if (!reason || reason.trim().length < 5) return;
    const done = await act(alert.id, 'close', { status: 'resolved', reason: reason.trim() });
    if (done) setPoints((current) => { const next = { ...current }; delete next[alert.id]; return next; });
  }, [act]);

  const open = alerts.filter(isOpen);
  const field = 'rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-emerald-400';

  return (
    <div className="grid gap-6">
      {failure && <p className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">Güvenlik servisi yanıt vermedi: {failure}.</p>}

      <div className="flex flex-wrap items-end gap-3">
        <label className="text-sm">Görünüm
          <select value={state} onChange={(event) => { setState(event.target.value); void load(event.target.value); }} className={`mt-1 block ${field}`}>
            <option value="open">Açık çağrılar</option>
            <option value="all">Tümü</option>
          </select>
        </label>
        <button type="button" onClick={() => void load(state)} className="rounded-lg bg-emerald-500 px-4 py-2 text-sm font-medium text-emerald-950">Yenile</button>
        <span className="pb-2 text-xs text-zinc-500">{open.length} açık çağrı · liste {REFRESH_MS / 1000} saniyede bir kendini yeniler</span>
      </div>

      {alerts.length === 0 && (
        <p className="rounded-xl border border-white/10 bg-zinc-900/40 p-6 text-sm text-zinc-500">
          {state === 'open' ? 'Açık yardım çağrısı yok.' : 'Hiç yardım çağrısı kaydı yok.'}
        </p>
      )}

      <div className="grid gap-3">
        {alerts.map((alert) => {
          const point = points[alert.id];
          const live = alert.location.accessExpiresAt && new Date(alert.location.accessExpiresAt).getTime() > now;
          return (
            <article key={alert.id} className={`rounded-xl border p-4 ${alert.status === 'active' ? 'border-red-500/40 bg-red-500/5' : 'border-white/10 bg-zinc-900/40'}`}>
              <div className="flex flex-wrap items-center gap-2 text-xs">
                <span className={`rounded px-2 py-0.5 ${SOS_STATUS_TONE[alert.status]}`}>{SOS_STATUS_LABELS[alert.status]}</span>
                <span className="rounded bg-zinc-800 px-2 py-0.5 text-zinc-300">{SOS_KIND_LABELS[alert.kind] ?? alert.kind}</span>
                {isOpen(alert) && <span className="text-zinc-400">{waitedFor(alert.createdAt, now)} bekliyor</span>}
                <span className="text-zinc-600">{sosTime(alert.createdAt)}</span>
              </div>

              <p className="mt-2 text-sm font-medium text-zinc-100">{memberLabel(alert)}</p>
              {alert.note && <p className="mt-1 text-sm text-zinc-300">“{alert.note}”</p>}
              {alert.locationNote && <p className="mt-1 text-sm text-zinc-400">Tarif ettiği yer: {alert.locationNote}</p>}

              <div className="mt-3 rounded-lg border border-white/10 bg-zinc-950/40 p-3 text-xs">
                {!alert.location.shared && <p className="text-zinc-500">Üye konum paylaşmadı. Yukarıdaki tarif ve mesaj dışında bir konum bilgisi yok.</p>}
                {alert.location.shared && (
                  <>
                    <p className="text-zinc-400">
                      Konum paylaşıldı{alert.location.capturedAt ? ` · ${sosTime(alert.location.capturedAt)}` : ''}
                      {alert.location.accuracyMeters !== null ? ` · ±${alert.location.accuracyMeters} m` : ''}
                      {alert.location.activeWatchers > 0 ? ` · şu an ${alert.location.activeWatchers} kişi görebiliyor` : ''}
                    </p>
                    {point ? (
                      <p className="mt-2 text-zinc-200">
                        <span className="tabular-nums">{point.latitude.toFixed(5)}, {point.longitude.toFixed(5)}</span>
                        {' · '}
                        {/* Deliberately a manual link, not an embedded map: an
                            iframe would hand the member's coordinates to a tile
                            provider on every page load, whether anybody looked
                            or not. */}
                        <a className="text-emerald-400 underline" target="_blank" rel="noreferrer" href={`https://www.openstreetmap.org/?mlat=${point.latitude}&mlon=${point.longitude}#map=16/${point.latitude}/${point.longitude}`}>haritada aç</a>
                        <span className="text-zinc-600"> (koordinat OpenStreetMap&apos;e gider)</span>
                        <br />
                        <span className="text-zinc-500">Erişimin {sosTime(point.accessExpiresAt)} tarihinde kapanır.</span>
                      </p>
                    ) : (
                      <p className="mt-2 text-zinc-500">
                        {live ? 'Erişimin açık; konumu getirmek için tekrar iste.' : 'Konum mühürlü. Görmek için gerekçe yazman gerekir; gerekçe kayda geçer ve erişim 30 dakika sonra kendiliğinden kapanır.'}
                      </p>
                    )}
                  </>
                )}
              </div>

              {alert.closureReason && <p className="mt-2 text-xs text-zinc-500">Kapanış: {alert.closureReason}</p>}

              {canAct && isOpen(alert) && (
                <div className="mt-3 flex flex-wrap gap-2">
                  {alert.status === 'active' && (
                    <button type="button" disabled={busy === alert.id} onClick={() => void act(alert.id, 'acknowledge')} className="rounded-lg bg-amber-500 px-3 py-1.5 text-xs font-medium text-amber-950 disabled:opacity-40">Üstlen</button>
                  )}
                  {alert.location.shared && (
                    <button type="button" disabled={busy === alert.id} onClick={() => void unseal(alert)} className="rounded-lg border border-zinc-600 px-3 py-1.5 text-xs text-zinc-200 disabled:opacity-40">Konumu aç</button>
                  )}
                  <button type="button" disabled={busy === alert.id} onClick={() => void close(alert)} className="rounded-lg bg-emerald-500 px-3 py-1.5 text-xs font-medium text-emerald-950 disabled:opacity-40">Kapat</button>
                </div>
              )}
            </article>
          );
        })}
      </div>
    </div>
  );
}
