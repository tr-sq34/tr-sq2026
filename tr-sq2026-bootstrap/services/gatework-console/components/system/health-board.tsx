'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import {
  Activity, AlertTriangle, BellRing, BellOff, Gauge, RefreshCw, ShieldCheck, Smartphone, Wrench,
} from 'lucide-react';
import { RISK_LEVELS, riskColor, type ServiceHealth, type SystemHealthSnapshot } from '@/lib/health-labels';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

/**
 * Sistem Sağlığı.
 *
 * Two rules decide everything on this screen.
 *
 * The first is that one number goes first. An operator opening the console at
 * two in the morning should not have to read four cards to work out whether
 * anything is wrong, so the top of the board is a single percentage that starts
 * green and moves continuously to red, and everything under it exists to
 * explain that number.
 *
 * The second is the console's standing rule: a measurement that was not taken
 * is never drawn as a good one. A crash-free rate with too few sessions behind
 * it renders as a sentence saying so, not as "%100"; a probe that could not run
 * renders as "ölçülemedi", not as green. The bar itself disappears rather than
 * sitting at zero.
 *
 * It refreshes itself because the thing it reports on changes without anyone
 * touching the page - a status board that needs to be reloaded to be true is
 * not a status board.
 */
const REFRESH_MS = 30_000;

const STATE_TONE = { up: 'success', slow: 'warning', down: 'danger' } as const;
const STATE_LABEL = { up: 'Çalışıyor', slow: 'Yavaş', down: 'Yanıt vermiyor' } as const;

export function HealthBoard({ initial, compact = false }: { initial: SystemHealthSnapshot; compact?: boolean }) {
  const [snapshot, setSnapshot] = useState(initial);
  const [refreshing, setRefreshing] = useState(false);
  const [staleSince, setStaleSince] = useState<string | null>(null);
  // A poll that is still in flight when the next tick arrives would stack
  // requests against a service that is, by hypothesis, already struggling.
  const inFlight = useRef(false);

  const refresh = useCallback(async () => {
    if (inFlight.current) return;
    inFlight.current = true;
    setRefreshing(true);
    try {
      const response = await fetch(`/api/system-health?hours=${initial.windowHours}`, { cache: 'no-store' });
      if (!response.ok) throw new Error(String(response.status));
      const body = await response.json() as { data: SystemHealthSnapshot };
      setSnapshot(body.data);
      setStaleSince(null);
    } catch {
      // The last good snapshot stays on screen, labelled with when it was taken.
      // Blanking the board when the console itself has a hiccup would hide the
      // outage it was drawn to report.
      setStaleSince((current) => current ?? new Date().toISOString());
    } finally {
      inFlight.current = false;
      setRefreshing(false);
    }
  }, [initial.windowHours]);

  useEffect(() => {
    const timer = setInterval(() => void refresh(), REFRESH_MS);
    return () => clearInterval(timer);
  }, [refresh]);

  const { risk, services, stability } = snapshot;

  if (compact) {
    return (
      <Card>
        <CardHeader>
          <div>
            <CardTitle>Sistem sağlığı</CardTitle>
            <CardDescription>Servisler ve uygulamanın çökme oranı, tek bir sorun riskinde toplanmış.</CardDescription>
          </div>
          <Badge tone={risk.level ? RISK_LEVELS[risk.level].tone : 'warning'} dot>
            {risk.level ? RISK_LEVELS[risk.level].label : 'Ölçülemedi'}
          </Badge>
        </CardHeader>
        <CardContent className="grid gap-4">
          <RiskMeter risk={risk} />
          <div className="grid gap-2 sm:grid-cols-2">
            {(services ?? []).map((check) => <ServiceRow key={check.key} check={check} />)}
          </div>
          {services === null && <p className="text-sm text-warning">Servis durumu okunamadı.</p>}
          <Link href="/health" className="text-xs text-ink-faint transition hover:text-brand-300">
            Ayrıntılı sağlık panelini aç →
          </Link>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="grid gap-4">
      <Card>
        <CardHeader>
          <div>
            <CardTitle>Sorun riski</CardTitle>
            <CardDescription>
              Sıfır yeşil, yüz kırmızı. Servislerin ayakta olup olmadığı ve uygulamanın üyelerin telefonunda
              çökme oranı bu tek sayıda toplanıyor.
            </CardDescription>
          </div>
          <button
            type="button"
            onClick={() => void refresh()}
            disabled={refreshing}
            className="flex items-center gap-1.5 rounded-lg border border-hairline px-2.5 py-1.5 text-xs text-ink-muted transition hover:border-brand-400/50 hover:text-ink disabled:opacity-40"
          >
            <RefreshCw size={13} className={refreshing ? 'animate-spin' : undefined} />
            Yenile
          </button>
        </CardHeader>
        <CardContent className="grid gap-5">
          <RiskMeter risk={risk} large />

          {risk.reasons.length > 0 && (
            <ul className="grid gap-2">
              {risk.reasons.map((reason) => (
                <li key={reason} className="flex gap-2.5 rounded-lg border border-danger/30 bg-danger-soft px-3.5 py-2.5 text-sm text-ink">
                  <AlertTriangle size={15} className="mt-0.5 shrink-0 text-danger" />
                  {reason}
                </li>
              ))}
            </ul>
          )}

          {risk.reasons.length === 0 && risk.score !== null && (
            <p className="flex items-center gap-2 text-sm text-ink-muted">
              <ShieldCheck size={15} className="text-success" />
              Ölçülen hiçbir sinyalde sorun yok.
            </p>
          )}

          {risk.blindSpots.length > 0 && (
            <div className="rounded-lg border border-dashed border-warning/30 bg-warning-soft px-3.5 py-3">
              <Badge tone="warning" dot>Ölçülemeyen</Badge>
              <ul className="mt-2 grid gap-1.5 text-xs text-ink-muted">
                {risk.blindSpots.map((gap) => <li key={gap}>{gap}</li>)}
              </ul>
            </div>
          )}

          <p className="text-xs text-ink-faint">
            {staleSince
              ? `Son başarılı ölçüm ${formatTime(snapshot.checkedAt)}. Panel o zamandan beri yenileyemiyor.`
              : `Son ölçüm ${formatTime(snapshot.checkedAt)} · ${REFRESH_MS / 1000} saniyede bir kendini yeniliyor.`}
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <div>
            <CardTitle>Servis durumları</CardTitle>
            <CardDescription>
              Her servisin kendi /health ucu, üç saniyelik zaman aşımıyla. 800 ms üzerinde yanıt veren servis
              yavaş sayılır; yanıt vermeyen düşmüş sayılır.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent>
          {services === null ? (
            <p className="text-sm text-warning">
              Servis durumu okunamadı{snapshot.servicesFailure ? `: ${snapshot.servicesFailure}` : '.'}
            </p>
          ) : (
            <div className="grid gap-2 sm:grid-cols-2">
              {services.map((check) => <ServiceRow key={check.key} check={check} detailed />)}
            </div>
          )}
        </CardContent>
      </Card>

      <StabilityCard snapshot={snapshot} />

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <div>
              <CardTitle>Uyarı kanalı</CardTitle>
              <CardDescription>Panel kapalıyken haber verecek olan taraf.</CardDescription>
            </div>
            <Badge tone={snapshot.alerting.configured ? 'success' : 'warning'} dot>
              {snapshot.alerting.configured ? 'Bağlı' : 'Bağlanmadı'}
            </Badge>
          </CardHeader>
          <CardContent className="grid gap-2.5 text-sm text-ink-muted">
            {snapshot.alerting.configured ? (
              <p className="flex gap-2.5">
                <BellRing size={15} className="mt-0.5 shrink-0 text-success" />
                Risk &quot;Bozulma var&quot; seviyesine çıktığında ve normale döndüğünde bildirim gönderiliyor.
                Aynı seviye için en fazla 15 dakikada bir yazılır.
              </p>
            ) : (
              <p className="flex gap-2.5">
                <BellOff size={15} className="mt-0.5 shrink-0 text-warning" />
                <span>
                  <code className="text-ink">OPS_ALERT_WEBHOOK_URL</code> tanımlı değil. Slack, Telegram ya da
                  Discord webhook adresi verildiğinde bu panel ve zamanlanmış sağlık kontrolü aynı adrese yazar.
                  Şu an bir sorun olduğunda kimseye haber gitmiyor.
                </span>
              </p>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div>
              <CardTitle>Bakım modu</CardTitle>
              <CardDescription>Uygulamayı geçici olarak kapatma anahtarı.</CardDescription>
            </div>
            <Badge tone="warning" dot>Bağlanmadı</Badge>
          </CardHeader>
          <CardContent>
            <p className="flex gap-2.5 text-sm text-ink-muted">
              <Wrench size={15} className="mt-0.5 shrink-0 text-warning" />
              Hiçbir serviste bakım modu anahtarı yok. Düğme buraya, çalışır hâle geldiğinde eklenecek —
              basıldığında hiçbir şey yapmayan bir düğme, olmayan düğmeden kötüdür.
            </p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------- */

function RiskMeter({ risk, large = false }: { risk: SystemHealthSnapshot['risk']; large?: boolean }) {
  if (risk.score === null) {
    return (
      <div className="rounded-lg border border-dashed border-warning/40 bg-warning-soft px-4 py-4">
        <p className="flex items-center gap-2 text-sm font-medium text-ink">
          <Gauge size={16} className="text-warning" /> Sorun riski ölçülemedi
        </p>
        <p className="mt-1 text-xs text-ink-muted">
          Hiçbir ölçüm alınamadı. Bu kutunun boş olması da bir bulgu: yüzde göstermek yerine söylüyoruz.
        </p>
      </div>
    );
  }

  const color = riskColor(risk.score);
  return (
    <div>
      <div className="flex items-end justify-between gap-3">
        <div>
          <p className="text-xs font-medium tracking-wide text-ink-faint uppercase">Sorun riski</p>
          <p className={large ? 'mt-1 text-4xl font-semibold tracking-tight' : 'mt-1 text-2xl font-semibold tracking-tight'} style={{ color }}>
            %{risk.score}
          </p>
        </div>
        <Badge tone={risk.level ? RISK_LEVELS[risk.level].tone : 'neutral'} dot>{risk.headline}</Badge>
      </div>
      <div className="mt-3 h-2.5 w-full overflow-hidden rounded-full bg-surface-overlay">
        <div
          className="h-full rounded-full transition-[width,background-color] duration-700"
          style={{ width: `${Math.max(risk.score, 2)}%`, backgroundColor: color }}
        />
      </div>
      {/* The thresholds are on screen so the number is falsifiable: an operator
          can see why 34 is "Bozulma var" without reading the source. */}
      <div className="mt-1.5 flex justify-between text-[11px] text-ink-faint">
        <span>0 · Sağlıklı</span>
        <span>10 · İzlemede</span>
        <span>30 · Bozulma</span>
        <span>60 · Kritik</span>
      </div>
      {risk.level && <p className="mt-2 text-xs text-ink-muted">{RISK_LEVELS[risk.level].description}</p>}
    </div>
  );
}

function ServiceRow({ check, detailed = false }: { check: ServiceHealth; detailed?: boolean }) {
  const tone = STATE_TONE[check.state];
  return (
    <div
      className={`flex items-center justify-between gap-3 rounded-lg border px-3.5 py-3 ${
        check.state === 'down' ? 'border-danger/40 bg-danger-soft'
          : check.state === 'slow' ? 'border-warning/40 bg-warning-soft'
          : 'border-hairline bg-surface-raised'
      }`}
    >
      <span className="min-w-0">
        <span className="flex items-center gap-2.5 text-sm text-ink">
          <Activity size={15} className={check.state === 'up' ? 'text-success' : check.state === 'slow' ? 'text-warning' : 'text-danger'} />
          {check.name}
        </span>
        {detailed && <span className="mt-0.5 block pl-6 text-xs text-ink-faint">{check.detail}</span>}
      </span>
      <Badge tone={tone} dot>
        {STATE_LABEL[check.state]}{check.latencyMs !== null && ` · ${check.latencyMs} ms`}
      </Badge>
    </div>
  );
}

function StabilityCard({ snapshot }: { snapshot: SystemHealthSnapshot }) {
  const { stability, stabilityFailure, windowHours } = snapshot;

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle>Uygulama kararlılığı</CardTitle>
          <CardDescription>
            Son {windowHours} saatte açılan oturumların kaçı çökmeden bitti. Sayı üyelerin kendi
            telefonundan geliyor; hiçbir dış servise gitmiyor.
          </CardDescription>
        </div>
      </CardHeader>
      <CardContent className="grid gap-4">
        {stability === null ? (
          <p className="text-sm text-warning">
            Kararlılık verisi okunamadı{stabilityFailure ? `: ${stabilityFailure}` : '.'}
          </p>
        ) : (
          <>
            <div className="grid gap-3 sm:grid-cols-3">
              <Figure
                label="Çökmesiz kullanım"
                value={stability.crashFreeRate === null ? '—' : `%${stability.crashFreeRate.toFixed(1)}`}
                detail={
                  stability.crashFreeRate === null
                    ? `Oran için en az ${stability.minSessionsForRate} oturum gerekiyor`
                    : stability.previous.crashFreeRate === null
                      ? 'Önceki dönemde karşılaştıracak veri yok'
                      : `Önceki ${windowHours} saat: %${stability.previous.crashFreeRate.toFixed(1)}`
                }
                unavailable={stability.crashFreeRate === null}
              />
              <Figure label="Oturum" value={String(stability.sessions)} detail={`${stability.crashedSessions} tanesi çökmeyle bitti`} />
              <Figure
                label="Hata raporu"
                value={String(stability.crashes)}
                detail={`${stability.fatalCrashes} tanesi uygulamayı kapattı`}
              />
            </div>

            {stability.platforms.length > 0 && (
              <div className="flex flex-wrap gap-2">
                {stability.platforms.map((row) => (
                  <span key={row.platform} className="flex items-center gap-1.5 rounded-lg border border-hairline bg-surface-raised px-2.5 py-1.5 text-xs text-ink-muted">
                    <Smartphone size={12} className="text-ink-faint" />
                    {row.platform} · {row.sessions} oturum
                    {row.crashFreeRate !== null && ` · %${row.crashFreeRate.toFixed(1)}`}
                  </span>
                ))}
              </div>
            )}

            {stability.sessions === 0 ? (
              <p className="rounded-lg border border-dashed border-hairline bg-surface/50 px-3.5 py-3 text-xs text-ink-muted">
                Bu dönemde hiç oturum kaydedilmedi. Uygulamanın bu ölçümü gönderen sürümü henüz üyelerde
                olmayabilir — burada %100 yazmıyoruz, çünkü ölçülen bir şey yok.
              </p>
            ) : stability.groups.length === 0 ? (
              <p className="text-sm text-ink-muted">Bu dönemde tek bir hata raporu gelmedi.</p>
            ) : (
              <div className="grid gap-2">
                <p className="text-xs font-medium tracking-wide text-ink-faint uppercase">En çok tekrarlayan hatalar</p>
                {stability.groups.map((group) => (
                  <div key={group.fingerprint} className="rounded-lg border border-hairline bg-surface-raised px-3.5 py-3">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <span className="text-sm font-medium text-ink">{group.errorType}</span>
                      <Badge tone={group.fatal ? 'danger' : 'warning'}>
                        {group.occurrences} kez · {group.sessions} oturum
                      </Badge>
                    </div>
                    <p className="mt-1 line-clamp-2 text-xs text-ink-muted">{group.message}</p>
                    <p className="mt-1.5 text-[11px] text-ink-faint">
                      {[
                        group.screen && `Ekran: ${group.screen}`,
                        group.appVersions.length > 0 && `Sürüm: ${group.appVersions.join(', ')}`,
                        group.platforms.length > 0 && group.platforms.join(', '),
                        group.deviceModels.length > 0 && group.deviceModels.slice(0, 3).join(', '),
                        `Son: ${formatTime(group.lastSeen)}`,
                      ].filter(Boolean).join(' · ')}
                    </p>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}

function Figure({ label, value, detail, unavailable = false }: { label: string; value: string; detail: string; unavailable?: boolean }) {
  return (
    <div className="rounded-lg border border-hairline bg-surface-raised px-3.5 py-3">
      <p className="text-xs font-medium tracking-wide text-ink-faint uppercase">{label}</p>
      <p className={`mt-1.5 text-xl font-semibold tracking-tight ${unavailable ? 'text-ink-faint' : 'text-ink'}`}>{value}</p>
      <p className="mt-1 text-xs text-ink-faint">{detail}</p>
    </div>
  );
}

const formatTime = (iso: string) => {
  const value = new Date(iso);
  return Number.isNaN(value.getTime()) ? '—' : value.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
};
