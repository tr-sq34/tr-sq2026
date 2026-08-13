import { AnalyticsDesk } from '@/components/analytics-desk';
import { analyticsPage, canSeeAnalytics } from '@/lib/analytics';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function AnalyticsPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeAnalytics(roles)) {
    return <main><h1 className="text-3xl font-semibold">Analitik ve Konum</h1><p className="mt-4 max-w-xl text-zinc-400">Bu alan analitik yetkisi gerektirir. Mevcut rollerin: {roles.join(', ')}.</p></main>;
  }

  const { accounts, community, locations, failures } = await analyticsPage();

  return (
    <main>
      <div className="mb-8">
        <p className="text-sm text-emerald-400">Kimlik ve Topluluk bağlı</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight">Analitik ve Konum</h1>
        <p className="mt-2 max-w-2xl text-zinc-400">
          Topluluğun büyüklüğü, haftalık hareketi ve dağılımı. Yalnızca toplulaştırılmış sayılar gösterilir: konum verisi üyenin profilinde <em>kendi seçtiği</em> şehir ve eyalettir, canlı konum ya da hareket geçmişi değildir. Az üyeli yerler tek tek gösterilmez, toplu olarak sayılır.
        </p>
      </div>

      <AnalyticsDesk initialAccounts={accounts} initialCommunity={community} initialLocations={locations} initialFailures={failures} />
    </main>
  );
}
