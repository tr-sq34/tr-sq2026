'use client';
import { useCallback, useMemo, useState } from 'react';
import { BadgeCheck, BellOff, Building2, FileText, Gavel, MapPinned, MessagesSquare, RefreshCw, Sparkles, UserPlus, Users } from 'lucide-react';
import { api, errorText } from '@/lib/api-client';
import { count, percent, regionLabel, weekLabel, NOTIFICATION_KIND_LABELS, type AccountAnalytics, type CommunityAnalytics, type LocationAnalytics } from '@/lib/analytics-labels';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { DataTable, type ColumnDef } from '@/components/ui/data-table';
import { StatCard } from '@/components/ui/stat-card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { StateGrid } from './state-grid';
import { TrendChart, type TrendSeries } from './trend-chart';

/**
 * Analitik ve Konum. Read-only, and aggregated on purpose: there is no row here
 * that is one person. The suppression threshold and the suppressed totals are
 * shown rather than hidden, so nobody reads the state list as the whole map.
 */
type Props = {
  initialAccounts: AccountAnalytics | null;
  initialCommunity: CommunityAnalytics | null;
  initialLocations: LocationAnalytics | null;
  initialFailures: string[];
};

type RegionRow = LocationAnalytics['regions'][number];
type CityRow = LocationAnalytics['cities'][number];

/**
 * The two services keep their own week lists. Aligning them on the union of
 * week starts - rather than assuming both answered for the same twelve weeks -
 * is what lets a week only one of them reported stay a gap in the other's line
 * instead of a zero.
 */
function alignWeeks(accounts: AccountAnalytics | null, community: CommunityAnalytics | null) {
  const starts = [
    ...(accounts?.weeks ?? []).map((week) => week.weekStart),
    ...(community?.weeks ?? []).map((week) => week.weekStart),
  ];
  const ordered = [...new Set(starts)].sort();
  const accountsBy = new Map((accounts?.weeks ?? []).map((week) => [week.weekStart, week]));
  const communityBy = new Map((community?.weeks ?? []).map((week) => [week.weekStart, week]));
  return {
    categories: ordered.map(weekLabel),
    growth: [
      { name: 'Yeni hesap', data: ordered.map((start) => accountsBy.get(start)?.signups ?? null) },
      { name: 'E-postası doğrulanan', data: ordered.map((start) => accountsBy.get(start)?.verified ?? null) },
    ] satisfies TrendSeries[],
    activity: [
      { name: 'Akış postu', data: ordered.map((start) => communityBy.get(start)?.posts ?? null) },
      { name: 'Forum konusu', data: ordered.map((start) => communityBy.get(start)?.forumTopics ?? null) },
      { name: 'Yeni ilan', data: ordered.map((start) => communityBy.get(start)?.listings ?? null) },
    ] satisfies TrendSeries[],
    empty: ordered.length === 0,
  };
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
      const body = await api<{ accounts: AccountAnalytics | null; community: CommunityAnalytics | null; locations: LocationAnalytics | null }>('/api/analytics');
      setAccounts(body.data.accounts);
      setCommunity(body.data.community);
      setLocations(body.data.locations);
      setFailures((body.meta?.failures as string[] | undefined) ?? []);
    } catch (error) {
      setFailures([errorText(error, 'Analitik okunamadı.')]);
    } finally {
      setBusy(false);
    }
  }, []);

  const weeks = useMemo(() => alignWeeks(accounts, community), [accounts, community]);

  const regionColumns: ColumnDef<RegionRow, unknown>[] = [
    {
      id: 'region',
      header: 'Eyalet',
      accessorFn: (row) => `${regionLabel(row.regionCode)} ${row.regionCode}`,
      cell: ({ row }) => (
        <span className="font-medium text-ink">
          {regionLabel(row.original.regionCode)} <span className="text-ink-faint">{row.original.regionCode}</span>
        </span>
      ),
    },
    { id: 'members', header: 'Üye', accessorFn: (row) => row.members, cell: ({ row }) => <span className="tabular-nums">{count(row.original.members)}</span> },
    { id: 'posts', header: 'Post', accessorFn: (row) => row.posts, cell: ({ row }) => <span className="tabular-nums">{count(row.original.posts)}</span> },
    { id: 'listings', header: 'İlan', accessorFn: (row) => row.listings, cell: ({ row }) => <span className="tabular-nums">{count(row.original.listings)}</span> },
  ];

  const cityColumns: ColumnDef<CityRow, unknown>[] = [
    {
      id: 'city',
      header: 'Şehir',
      accessorFn: (row) => `${row.city} ${row.regionCode} ${regionLabel(row.regionCode)}`,
      cell: ({ row }) => (
        <span className="font-medium text-ink">
          {row.original.city} <span className="text-ink-faint">{row.original.regionCode}</span>
        </span>
      ),
    },
    { id: 'members', header: 'Üye', accessorFn: (row) => row.members, cell: ({ row }) => <span className="tabular-nums">{count(row.original.members)}</span> },
    { id: 'listings', header: 'İlan', accessorFn: (row) => row.listings, cell: ({ row }) => <span className="tabular-nums">{count(row.original.listings)}</span> },
  ];

  return (
    <div className="grid gap-5">
      <div className="flex flex-wrap items-center gap-3">
        <Button type="button" variant="secondary" disabled={busy} onClick={() => void load()}>
          <RefreshCw size={15} className={busy ? 'animate-spin' : undefined} /> {busy ? 'Okunuyor…' : 'Yenile'}
        </Button>
        {locations && (
          <span className="text-xs text-ink-faint">
            Eşik: en az {locations.threshold} üyeli yerler tek tek gösterilir.
          </span>
        )}
      </div>

      {failures.map((failure) => (
        <p key={failure} className="rounded-card border border-warning/30 bg-warning-soft p-4 text-sm text-warning">
          Bu bölüm okunamadı — {failure}. Gösterilen diğer sayılar etkilenmedi.
        </p>
      ))}

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Toplam hesap"
          value={accounts ? count(accounts.accounts) : 'Yanıt yok'}
          detail={accounts ? `${count(accounts.operators)} yetkili operatör` : 'Kimlik servisi yanıt vermedi'}
          icon={Users}
          tone="brand"
          unavailable={!accounts}
        />
        <StatCard
          label="E-postası doğrulanmış"
          value={accounts ? count(accounts.verifiedAccounts) : 'Yanıt yok'}
          badge={accounts ? percent(accounts.verifiedAccounts, accounts.accounts) : undefined}
          detail="tüm hesaplar içinde"
          icon={BadgeCheck}
          tone="success"
          unavailable={!accounts}
        />
        <StatCard
          label="Son 7 günde açılan"
          value={accounts ? count(accounts.newLast7Days) : 'Yanıt yok'}
          detail={accounts ? `son 30 günde ${count(accounts.newLast30Days)}` : 'Kimlik servisi yanıt vermedi'}
          icon={UserPlus}
          tone="neutral"
          unavailable={!accounts}
        />
        <StatCard
          label="Yer belirten profil"
          value={community ? count(community.locatedMembers) : 'Yanıt yok'}
          badge={community ? percent(community.locatedMembers, community.members) : undefined}
          detail={community ? `${count(community.members)} profil içinde` : 'Topluluk servisi yanıt vermedi'}
          icon={MapPinned}
          tone="neutral"
          unavailable={!community}
        />
      </div>

      {community && (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <StatCard label="Yeni akış postu" value={count(community.postsLast7Days)} detail={`son 7 gün · toplam ${count(community.posts)}`} icon={FileText} tone="neutral" />
          <StatCard label="Yeni yorum" value={count(community.commentsLast7Days)} detail="son 7 gün" icon={MessagesSquare} tone="neutral" />
          <StatCard label="Forum yanıtı" value={count(community.forumRepliesLast7Days)} detail={`son 7 gün · ${count(community.forumTopics)} konu`} icon={MessagesSquare} tone="neutral" />
          <StatCard label="Yayındaki ilan" value={count(community.activeListings)} detail={`${count(community.liveStories)} açık Story`} icon={Gavel} tone="neutral" />
        </div>
      )}

      {community && (
        <Card>
          <CardHeader>
            <div>
              <CardTitle>Bildirim tercihleri</CardTitle>
              <CardDescription>
                Üyenin uygulamadan kapattığı zil türleri. Kimin kapattığı değil, kaç kişinin kapattığı gösterilir.
                Bir türün yüksek olması o bildirimin rahatsız ettiğinin tek ölçülebilir işaretidir.
              </CardDescription>
            </div>
            <BellOff size={17} className="text-brand-300" />
          </CardHeader>
          <CardContent>
            {!community.notificationMutes ? (
              // Sıfır çizmiyoruz: alan gelmediyse ölçüm yapılmamıştır, kimsenin
              // kapatmadığı anlamına gelmez.
              <p className="text-sm text-warning">
                Topluluk servisi bu alanı henüz bildirmiyor. Bu, hiç kimsenin bildirim kapatmadığı anlamına gelmez — ölçüm gelmedi.
              </p>
            ) : (
              <>
                <div className="grid gap-2.5 sm:grid-cols-2">
                  {Object.entries(NOTIFICATION_KIND_LABELS).map(([kind, label]) => {
                    const muted = community.notificationMutes!.byKind[kind] ?? 0;
                    const total = community.notificationMutes!.totalMembers;
                    return (
                      <div key={kind} className="flex items-center justify-between gap-3 rounded-lg border border-hairline bg-surface-raised px-3.5 py-3">
                        <span className="text-sm text-ink-muted">{label}</span>
                        <span className="flex items-center gap-2 text-sm">
                          <span className="tabular-nums font-medium text-ink">{count(muted)}</span>
                          <span className="text-xs text-ink-faint">{percent(muted, total)}</span>
                        </span>
                      </div>
                    );
                  })}
                </div>
                <p className="mt-4 rounded-lg border border-hairline bg-canvas p-4 text-xs text-ink-muted">
                  Paydası {count(community.notificationMutes.totalMembers)} profil.
                  Duyuru ve destek yanıtı bu listede yok: ikisi de kapatılamıyor, o yüzden global duyurunun ulaştığı
                  üye sayısı bu tercihlerden etkilenmez.
                </p>
              </>
            )}
          </CardContent>
        </Card>
      )}

      {!weeks.empty && (
        <div className="grid gap-4 xl:grid-cols-2">
          <Card>
            <CardHeader>
              <div>
                <CardTitle>Haftalık büyüme</CardTitle>
                <CardDescription>Kimlik servisi · açılan ve e-postası doğrulanan hesap</CardDescription>
              </div>
              <Sparkles size={17} className="text-brand-300" />
            </CardHeader>
            <CardContent className="pt-2">
              <TrendChart categories={weeks.categories} series={weeks.growth} />
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <div>
                <CardTitle>Haftalık hareket</CardTitle>
                <CardDescription>Topluluk servisi · post, forum konusu ve ilan</CardDescription>
              </div>
              <Sparkles size={17} className="text-brand-300" />
            </CardHeader>
            <CardContent className="pt-2">
              <TrendChart categories={weeks.categories} series={weeks.activity} />
            </CardContent>
          </Card>
        </div>
      )}

      {locations && (
        <Card>
          <CardHeader>
            <div>
              <CardTitle>Konum dağılımı</CardTitle>
              <CardDescription>
                Üyenin profilinde kendi seçtiği şehir ve eyalet. Konum izni, canlı koordinat ya da hareket geçmişi bu ekranda yoktur ve bu sayılar onlardan üretilmez.
              </CardDescription>
            </div>
            <Building2 size={17} className="text-brand-300" />
          </CardHeader>
          <CardContent>
            <Tabs defaultValue="regions">
              <TabsList className="mb-4">
                <TabsTrigger value="regions" count={locations.regions.length}>Eyaletler</TabsTrigger>
                <TabsTrigger value="cities" count={locations.cities.length}>Şehirler</TabsTrigger>
              </TabsList>

              <TabsContent value="regions" className="grid gap-4 xl:grid-cols-2">
                <StateGrid locations={locations} />
                <DataTable
                  columns={regionColumns}
                  rows={locations.regions}
                  rowKey={(row) => row.regionCode}
                  emptyLabel="Henüz eyalet bilgisi olan üye yok."
                  searchPlaceholder="Eyalet ara"
                />
              </TabsContent>

              <TabsContent value="cities">
                <DataTable
                  columns={cityColumns}
                  rows={locations.cities}
                  rowKey={(row) => `${row.regionCode}/${row.city}`}
                  emptyLabel="Henüz şehir bilgisi olan üye yok."
                  searchPlaceholder="Şehir veya eyalet ara"
                />
              </TabsContent>
            </Tabs>

            {/* Not a privacy footnote, a coverage one. If most of the community
                is unplaced or under the threshold, the tables above describe a
                minority of it and must not be read as the map. */}
            <div className="mt-4 grid gap-1.5 rounded-lg border border-hairline bg-canvas p-4 text-xs text-ink-muted">
              <p>
                Yeri belirtilmemiş: {count(locations.unplaced.members)} üye · {count(locations.unplaced.posts)} post · {count(locations.unplaced.listings)} ilan.
              </p>
              {locations.suppressedRegions.buckets > 0 && (
                <p>
                  Eşik altında kalan {locations.suppressedRegions.buckets} eyalet tek tek gösterilmiyor:
                  toplam {count(locations.suppressedRegions.members)} üye, {count(locations.suppressedRegions.posts)} post, {count(locations.suppressedRegions.listings)} ilan.
                </p>
              )}
              {locations.suppressedCities.buckets > 0 && (
                <p>
                  Eşik altında kalan {locations.suppressedCities.buckets} şehir tek tek gösterilmiyor:
                  toplam {count(locations.suppressedCities.members)} üye, {count(locations.suppressedCities.listings)} ilan.
                </p>
              )}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
