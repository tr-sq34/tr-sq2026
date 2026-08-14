'use client';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlarmClock, LifeBuoy, RefreshCw, ShieldCheck, Siren } from 'lucide-react';
import { api, apiData, errorText } from '@/lib/api-client';
import { SOS_KIND_LABELS, SOS_STATUS_LABELS, SOS_STATUS_TONE, isOpen, memberLabel, sosTime, waitedFor, type SosAlert, type SosLocation } from '@/lib/safety-labels';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Field, Select } from '@/components/ui/field';
import { EmptyState } from '@/components/ui/page';
import { ReasonDialog } from '@/components/ui/reason-dialog';
import { StatCard } from '@/components/ui/stat-card';
import { SosMap } from './sos-map';
import { cn } from '@/lib/cn';

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
type Pending = { kind: 'unseal' | 'close'; alert: SosAlert };

const REFRESH_MS = 20_000;
const LOCATION_MINUTES = 30;

export function SafetyDesk({ initialAlerts, initialFailure, canAct }: Props) {
  const [alerts, setAlerts] = useState(initialAlerts);
  const [failure, setFailure] = useState(initialFailure);
  const [state, setState] = useState('open');
  const [selectedId, setSelectedId] = useState<string | null>(initialAlerts[0]?.id ?? null);
  const [busy, setBusy] = useState<string | null>(null);
  const [points, setPoints] = useState<Record<string, SosLocation>>({});
  const [pending, setPending] = useState<Pending | null>(null);
  // Recomputed on every refresh so "waited 12 min" does not freeze at the value
  // it had when the page was opened.
  const [now, setNow] = useState(() => Date.now());

  const load = useCallback(async (next: string) => {
    try {
      const body = await api<{ alerts: SosAlert[] }>(`/api/safety?state=${next}`);
      setAlerts(body.data.alerts);
      setFailure((body.meta?.failure as string | null) ?? null);
      setNow(Date.now());
    } catch (error) {
      setFailure(errorText(error, 'Çağrılar alınamadı.'));
    }
  }, []);

  useEffect(() => {
    const timer = setInterval(() => void load(state), REFRESH_MS);
    return () => clearInterval(timer);
  }, [load, state]);

  const acknowledge = useCallback(async (alert: SosAlert) => {
    setBusy(alert.id);
    try {
      await apiData(`/api/safety/alerts/${alert.id}/acknowledge`, { method: 'POST' });
      await load(state);
    } catch (error) {
      setFailure(errorText(error, 'İşlem tamamlanamadı.'));
    } finally {
      setBusy(null);
    }
  }, [load, state]);

  async function confirm(reason: string) {
    if (!pending) return;
    const { alert, kind } = pending;
    if (kind === 'unseal') {
      await apiData(`/api/safety/alerts/${alert.id}/location-access`, {
        method: 'POST',
        body: JSON.stringify({ reason, minutes: LOCATION_MINUTES }),
      });
      const point = await apiData<SosLocation>(`/api/safety/alerts/${alert.id}/location`);
      setPoints((current) => ({ ...current, [alert.id]: point }));
    } else {
      await apiData(`/api/safety/alerts/${alert.id}/close`, {
        method: 'POST',
        body: JSON.stringify({ status: 'resolved', reason }),
      });
      // The service deletes the point when the alert closes; the screen drops
      // its copy in the same breath rather than keeping one it no longer needs.
      setPoints((current) => { const next = { ...current }; delete next[alert.id]; return next; });
    }
    await load(state);
  }

  const open = useMemo(() => alerts.filter(isOpen), [alerts]);
  const waiting = open.filter((alert) => alert.status === 'active');
  const longestWait = open.reduce<SosAlert | null>(
    (worst, alert) => (worst === null || new Date(alert.createdAt) < new Date(worst.createdAt) ? alert : worst),
    null,
  );
  const selected = alerts.find((alert) => alert.id === selectedId) ?? alerts[0] ?? null;
  const point = selected ? points[selected.id] : undefined;
  const grantLive = selected?.location.accessExpiresAt ? new Date(selected.location.accessExpiresAt).getTime() > now : false;

  return (
    <div className="grid gap-5">
      {failure && (
        <p className="rounded-card border border-warning/30 bg-warning-soft p-4 text-sm text-warning">
          Güvenlik servisi yanıt vermedi: {failure}.
        </p>
      )}

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="Açık çağrı" value={String(open.length)} detail={`liste ${REFRESH_MS / 1000} saniyede bir yenilenir`} icon={LifeBuoy} tone={open.length > 0 ? 'danger' : 'success'} />
        <StatCard label="Henüz üstlenilmedi" value={String(waiting.length)} detail="kimse cevap vermedi" icon={Siren} tone={waiting.length > 0 ? 'danger' : 'neutral'} />
        <StatCard label="Üstlenildi" value={String(open.length - waiting.length)} detail="bir operatör ilgileniyor" icon={ShieldCheck} tone="neutral" />
        <StatCard
          label="En uzun bekleyen"
          value={longestWait ? waitedFor(longestWait.createdAt, now) : '—'}
          detail={longestWait ? memberLabel(longestWait) : 'bekleyen çağrı yok'}
          icon={AlarmClock}
          tone={longestWait ? 'warning' : 'neutral'}
          unavailable={!longestWait}
        />
      </div>

      <div className="flex flex-wrap items-end gap-3">
        <Field label="Görünüm" className="w-52">
          <Select value={state} onChange={(event) => { setState(event.target.value); void load(event.target.value); }}>
            <option value="open">Açık çağrılar</option>
            <option value="all">Tümü</option>
          </Select>
        </Field>
        <Button type="button" variant="secondary" className="mb-[1px]" onClick={() => void load(state)}>
          <RefreshCw size={15} /> Yenile
        </Button>
      </div>

      {alerts.length === 0 ? (
        <EmptyState
          icon={ShieldCheck}
          title={state === 'open' ? 'Açık yardım çağrısı yok.' : 'Hiç yardım çağrısı kaydı yok.'}
          description="Yeni bir çağrı geldiğinde bu liste kendiliğinden dolar."
        />
      ) : (
        <section className="grid gap-4 xl:grid-cols-[340px_minmax(0,1fr)]">
          <ul className="max-h-[70vh] divide-y divide-hairline/60 overflow-y-auto rounded-card border border-hairline bg-surface">
            {alerts.map((alert) => (
              <li key={alert.id}>
                <button
                  type="button"
                  onClick={() => setSelectedId(alert.id)}
                  className={cn(
                    'w-full px-4 py-3 text-left transition',
                    selected?.id === alert.id ? 'bg-surface-raised' : 'hover:bg-surface-raised/60',
                    alert.status === 'active' && 'border-l-2 border-danger',
                  )}
                >
                  <div className="flex items-center justify-between gap-2">
                    <Badge tone={SOS_STATUS_TONE[alert.status]} dot>{SOS_STATUS_LABELS[alert.status]}</Badge>
                    {isOpen(alert) && <span className="text-[11px] whitespace-nowrap text-ink-faint">{waitedFor(alert.createdAt, now)} bekliyor</span>}
                  </div>
                  <p className="mt-1.5 truncate text-sm font-medium text-ink">{memberLabel(alert)}</p>
                  <p className="truncate text-xs text-ink-faint">
                    {SOS_KIND_LABELS[alert.kind] ?? alert.kind} · {sosTime(alert.createdAt)}
                  </p>
                </button>
              </li>
            ))}
          </ul>

          {!selected ? (
            <EmptyState title="Soldan bir çağrı seç." />
          ) : (
            <div className="grid gap-4">
              <div className={cn('rounded-card border p-5', selected.status === 'active' ? 'border-danger/40 bg-danger-soft' : 'border-hairline bg-surface')}>
                <div className="flex flex-wrap items-center gap-2">
                  <Badge tone={SOS_STATUS_TONE[selected.status]} dot>{SOS_STATUS_LABELS[selected.status]}</Badge>
                  <Badge tone="neutral">{SOS_KIND_LABELS[selected.kind] ?? selected.kind}</Badge>
                  {isOpen(selected) && <span className="text-xs text-ink-muted">{waitedFor(selected.createdAt, now)} bekliyor</span>}
                  <span className="text-xs text-ink-faint">{sosTime(selected.createdAt)}</span>
                </div>

                <h2 className="mt-3 text-base font-semibold text-ink">{memberLabel(selected)}</h2>
                {selected.note && <p className="mt-1.5 text-sm text-ink">“{selected.note}”</p>}
                {selected.locationNote && <p className="mt-1.5 text-sm text-ink-muted">Tarif ettiği yer: {selected.locationNote}</p>}
                {selected.closureReason && <p className="mt-3 text-xs text-ink-faint">Kapanış: {selected.closureReason}</p>}

                {canAct && isOpen(selected) && (
                  <div className="mt-4 flex flex-wrap gap-2">
                    {selected.status === 'active' && (
                      <Button type="button" variant="primary" size="sm" disabled={busy === selected.id} onClick={() => void acknowledge(selected)}>
                        Üstlen
                      </Button>
                    )}
                    {selected.location.shared && (
                      <Button type="button" variant="outline" size="sm" onClick={() => setPending({ kind: 'unseal', alert: selected })}>
                        Konumu aç
                      </Button>
                    )}
                    <Button type="button" variant="success" size="sm" onClick={() => setPending({ kind: 'close', alert: selected })}>
                      Çağrıyı kapat
                    </Button>
                  </div>
                )}
              </div>

              <div className="rounded-card border border-hairline bg-surface p-5">
                <h3 className="text-xs font-medium tracking-wide text-ink-faint uppercase">Konum</h3>
                {!selected.location.shared ? (
                  <p className="mt-2 text-sm text-ink-muted">
                    Üye konum paylaşmadı. Yukarıdaki tarif ve mesaj dışında bir konum bilgisi yok.
                  </p>
                ) : (
                  <>
                    <p className="mt-2 text-xs text-ink-faint">
                      Konum paylaşıldı{selected.location.capturedAt ? ` · ${sosTime(selected.location.capturedAt)}` : ''}
                      {selected.location.accuracyMeters !== null ? ` · ±${selected.location.accuracyMeters} m` : ''}
                      {selected.location.activeWatchers > 0 ? ` · şu an ${selected.location.activeWatchers} kişi görebiliyor` : ''}
                    </p>
                    <div className="mt-3">
                      {point ? (
                        <>
                          <SosMap latitude={point.latitude} longitude={point.longitude} accuracyMeters={point.accuracyMeters} />
                          <p className="mt-2 text-xs text-ink-faint">Erişimin {sosTime(point.accessExpiresAt)} tarihinde kendiliğinden kapanır.</p>
                        </>
                      ) : (
                        <p className="text-sm text-ink-muted">
                          {grantLive
                            ? 'Erişimin açık; konumu getirmek için “Konumu aç” ile tekrar iste.'
                            : `Konum mühürlü. Görmek için gerekçe yazman gerekir; gerekçe kayda geçer ve erişim ${LOCATION_MINUTES} dakika sonra kendiliğinden kapanır.`}
                        </p>
                      )}
                    </div>
                  </>
                )}
              </div>
            </div>
          )}
        </section>
      )}

      <ReasonDialog
        open={pending !== null}
        onOpenChange={(next) => { if (!next) setPending(null); }}
        title={pending?.kind === 'unseal' ? 'Konum mührü açılacak' : 'Çağrı kapatılacak'}
        description={
          pending?.kind === 'unseal'
            ? `Konumu neden görmen gerekiyor? Bu gerekçe kayda geçer, üyeye gösterilebilir ve erişim ${LOCATION_MINUTES} dakika sonra kendiliğinden kapanır.`
            : 'Çağrı nasıl kapandı? Kısaca yaz — bu, olayın kaydı olacak. Kapanışla birlikte üyenin konumu silinir.'
        }
        confirmLabel={pending?.kind === 'unseal' ? 'Konumu aç' : 'Çağrıyı kapat'}
        variant={pending?.kind === 'unseal' ? 'danger' : 'success'}
        onConfirm={confirm}
      />
    </div>
  );
}
