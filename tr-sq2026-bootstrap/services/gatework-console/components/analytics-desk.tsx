'use client';
import { useCallback, useState } from 'react';
import { count, percent, regionLabel, weekLabel, type AccountAnalytics, type CommunityAnalytics, type LocationAnalytics } from '@/lib/analytics-labels';

/**
 * Analitik ve Konum. Read-only, and aggregated on purpose: there is no row here
 * that is one person. The suppression threshold and the suppressed totals are
 * shown rather than hidden, so nobody reads the state list as the whole map.
 */
type Props = { initialAccounts: AccountAnalytics | null; initialCommunity: CommunityAnalytics | null; initialLocations: LocationAnalytics | null; initialFailures: string[] };

const card = 'rounded-xl border border-white/10 bg-zinc-900/40 p-4';

function Metric({ value, label, hint }: { value: string; label: string; hint?: string }) {
  return (
    <div className={card}>
      <p className="text-2xl font-semibold">{value}</p>
      <p className="mt-1 text-xs text-zinc-400">{label}</p>
      {hint && <p className="mt-1 text-xs text-zinc-600">{hint}</p>}
    </div>
  );
}

// A bar chart with no chart library: the series is twelve points and every one
// of them is a whole number, so a div with a width is the honest drawing of it.
// Scaled against the largest week, with the value written out - a bar that is
// half as tall says nothing on its own.
function Bars({ title, weeks }: { title: string; weeks: { key: string; label: string; value: number }[] }) {
  const peak = Math.max(1, ...weeks.map((week) => week.value));
  return (
    <div className={card}>
      <p className="text-xs text-zinc-400">{title}</p>
      <div className="mt-3 grid gap-1">
        {weeks.map((week) => (
          <div key={week.key} className="flex items-center gap-2">
            <span className="w-14 shrink-0 text-xs text-zinc-500">{week.label}</span>
            <span className="h-2 flex-1 overflow-hidden rounded bg-zinc-800">
              <span className="block h-full rounded bg-emerald-500/70" style={{ width: `${(week.value / peak) * 100}%` }} />
            </span>
            <span className="w-10 shrink-0 text-right text-xs tabular-nums text-zinc-400">{count(week.value)}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

export function AnalyticsDesk({ initialAccounts, initialCommunity, initialLocations, initialFailures }: Props) {
  const [accounts, setAccounts] = useState(initialAccounts);
  const [community, setCommunity] = useState(initialCommunity);
  const [locations, setLocations] = useState(initialLocations);
  const [failures, setFailures] = useState(initialFailures);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setBusy(true);
    try {
      const response = await fetch('/api/analytics', { headers: { 'content-type': 'application/json' } });
      const body = await response.json().catch(() => null);
      if (!response.ok) throw new Error(body?.error?.message ?? 'Analitik okunamadı.');
      setAccounts(body.data.accounts as AccountAnalytics | null);
      setCommunity(body.data.community as CommunityAnalytics | null);
      setLocations(body.data.locations as LocationAnalytics | null);
      setFailures((body.meta?.failures as string[] | undefined) ?? []);
    } catch (error) {
      setFailures([error instanceof Error ? error.message : 'Analitik okunamadı.']);
    } finally {
      setBusy(false);
    }
  }, []);

  return (
    <div className="grid gap-6">
      <div className="flex items-center gap-3">
        <button type="button" disabled={busy} onClick={() => void load()} className="rounded-lg bg-emerald-500 px-4 py-2 text-sm font-medium text-emerald-950 disabled:opacity-40">
          {busy ? 'Okunuyor…' : 'Yenile'}
        </button>
        {locations && <span className="text-xs text-zinc-500">Eşik: en az {locations.threshold} üyeli yerler tek tek gösterilir.</span>}
      </div>

      {failures.map((failure) => (
        <p key={failure} className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">Bu bölüm okunamadı — {failure}. Gösterilen diğer sayılar etkilenmedi.</p>
      ))}

      {accounts && (
        <section className="grid gap-3">
          <h2 className="text-sm font-medium text-zinc-300">Hesaplar <span className="text-zinc-600">· Kimlik servisi</span></h2>
          <div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-5">
            <Metric value={count(accounts.accounts)} label="Toplam hesap" />
            <Metric value={count(accounts.verifiedAccounts)} label="E-postası doğrulanmış" hint={percent(accounts.verifiedAccounts, accounts.accounts)} />
            <Metric value={count(accounts.newLast7Days)} label="Son 7 günde açılan" />
            <Metric value={count(accounts.newLast30Days)} label="Son 30 günde açılan" />
            <Metric value={count(accounts.operators)} label="Yetkili operatör" hint="rolü geri alınmamış" />
          </div>
        </section>
      )}

      {community && (
        <section className="grid gap-3">
          <h2 className="text-sm font-medium text-zinc-300">Topluluk <span className="text-zinc-600">· son 7 gün</span></h2>
          <div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-6">
            <Metric value={count(community.members)} label="Profil" hint={`${count(community.locatedMembers)} tanesi yer belirtmiş`} />
            <Metric value={count(community.postsLast7Days)} label="Yeni akış postu" hint={`toplam ${count(community.posts)}`} />
            <Metric value={count(community.commentsLast7Days)} label="Yeni yorum" />
            <Metric value={count(community.forumRepliesLast7Days)} label="Forum yanıtı" hint={`${count(community.forumTopics)} konu`} />
            <Metric value={count(community.activeListings)} label="Yayındaki ilan" />
            <Metric value={count(community.liveStories)} label="Açık Story" hint="24 saat içinde sönecek" />
          </div>
        </section>
      )}

      {(community || accounts) && (
        <section className="grid gap-3 lg:grid-cols-2">
          {accounts && <Bars title="Haftalık yeni hesap" weeks={accounts.weeks.map((week) => ({ key: week.weekStart, label: weekLabel(week.weekStart), value: week.signups }))} />}
          {community && <Bars title="Haftalık akış postu" weeks={community.weeks.map((week) => ({ key: week.weekStart, label: weekLabel(week.weekStart), value: week.posts }))} />}
        </section>
      )}

      {locations && (
        <section className="grid gap-3">
          <h2 className="text-sm font-medium text-zinc-300">Konum <span className="text-zinc-600">· üyenin kendi seçtiği şehir ve eyalet</span></h2>
          <p className="text-xs text-zinc-500">
            Bu tablo üyelerin profilinde belirttiği yerleşim tercihinden gelir. Konum izni, canlı koordinat veya hareket geçmişi bu ekranda yoktur ve bu sayılar onlardan üretilmez.
          </p>

          <div className="grid gap-4 lg:grid-cols-2">
            <div className={card}>
              <p className="text-xs text-zinc-400">Eyaletler</p>
              <table className="mt-3 w-full text-sm">
                <thead className="text-xs text-zinc-500"><tr><th className="pb-2 text-left font-normal">Eyalet</th><th className="pb-2 text-right font-normal">Üye</th><th className="pb-2 text-right font-normal">Post</th><th className="pb-2 text-right font-normal">İlan</th></tr></thead>
                <tbody>
                  {locations.regions.map((row) => (
                    <tr key={row.regionCode} className="border-t border-white/5">
                      <td className="py-1.5">{regionLabel(row.regionCode)} <span className="text-zinc-600">{row.regionCode}</span></td>
                      <td className="py-1.5 text-right tabular-nums">{count(row.members)}</td>
                      <td className="py-1.5 text-right tabular-nums text-zinc-400">{count(row.posts)}</td>
                      <td className="py-1.5 text-right tabular-nums text-zinc-400">{count(row.listings)}</td>
                    </tr>
                  ))}
                  {locations.suppressedRegions.buckets > 0 && (
                    <tr className="border-t border-white/5 text-zinc-500">
                      <td className="py-1.5">{locations.suppressedRegions.buckets} eyalet · eşik altı</td>
                      <td className="py-1.5 text-right tabular-nums">{count(locations.suppressedRegions.members)}</td>
                      <td className="py-1.5 text-right tabular-nums">{count(locations.suppressedRegions.posts)}</td>
                      <td className="py-1.5 text-right tabular-nums">{count(locations.suppressedRegions.listings)}</td>
                    </tr>
                  )}
                  {locations.regions.length === 0 && locations.suppressedRegions.buckets === 0 && <tr><td colSpan={4} className="py-4 text-zinc-500">Henüz eyalet bilgisi olan üye yok.</td></tr>}
                </tbody>
              </table>
            </div>

            <div className={card}>
              <p className="text-xs text-zinc-400">Şehirler</p>
              <table className="mt-3 w-full text-sm">
                <thead className="text-xs text-zinc-500"><tr><th className="pb-2 text-left font-normal">Şehir</th><th className="pb-2 text-right font-normal">Üye</th><th className="pb-2 text-right font-normal">İlan</th></tr></thead>
                <tbody>
                  {locations.cities.map((row) => (
                    <tr key={`${row.regionCode}/${row.city}`} className="border-t border-white/5">
                      <td className="py-1.5">{row.city} <span className="text-zinc-600">{row.regionCode}</span></td>
                      <td className="py-1.5 text-right tabular-nums">{count(row.members)}</td>
                      <td className="py-1.5 text-right tabular-nums text-zinc-400">{count(row.listings)}</td>
                    </tr>
                  ))}
                  {locations.suppressedCities.buckets > 0 && (
                    <tr className="border-t border-white/5 text-zinc-500">
                      <td className="py-1.5">{locations.suppressedCities.buckets} şehir · eşik altı</td>
                      <td className="py-1.5 text-right tabular-nums">{count(locations.suppressedCities.members)}</td>
                      <td className="py-1.5 text-right tabular-nums">{count(locations.suppressedCities.listings)}</td>
                    </tr>
                  )}
                  {locations.cities.length === 0 && locations.suppressedCities.buckets === 0 && <tr><td colSpan={3} className="py-4 text-zinc-500">Henüz şehir bilgisi olan üye yok.</td></tr>}
                </tbody>
              </table>
            </div>
          </div>

          {/* Not a privacy number, a coverage one. If most of the community is
              here, the tables above describe a minority of it and should not be
              read as the map. */}
          <p className="rounded-xl border border-white/10 bg-zinc-900/40 p-4 text-xs text-zinc-400">
            Yeri belirtilmemiş: {count(locations.unplaced.members)} üye, {count(locations.unplaced.posts)} post, {count(locations.unplaced.listings)} ilan.
            {locations.suppressedRegions.members > 0 && ` Eşik altında kalan ${count(locations.suppressedRegions.members)} üye yukarıdaki listede tek tek görünmez.`}
          </p>
        </section>
      )}
    </div>
  );
}
