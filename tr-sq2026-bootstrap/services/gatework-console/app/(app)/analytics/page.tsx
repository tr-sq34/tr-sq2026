import { AnalyticsDesk } from '@/components/analytics/analytics-desk';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { analyticsPage, canSeeAnalytics } from '@/lib/analytics';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function AnalyticsPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeAnalytics(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Analitik ve Konum" />
        <EmptyState title="Bu alan analitik yetkisi gerektirir." description={`Mevcut rollerin: ${roles.join(', ')}.`} />
      </main>
    );
  }

  const { accounts, community, locations, failures } = await analyticsPage();

  return (
    <main>
      <PageHeader
        eyebrow="Kimlik ve Topluluk bağlı"
        title="Analitik ve Konum"
        description="Topluluğun büyüklüğü, haftalık hareketi ve dağılımı. Yalnızca toplulaştırılmış sayılar gösterilir: konum verisi üyenin profilinde kendi seçtiği şehir ve eyalettir, canlı konum ya da hareket geçmişi değildir. Az üyeli yerler tek tek gösterilmez, toplu olarak sayılır."
      />
      <AnalyticsDesk initialAccounts={accounts} initialCommunity={community} initialLocations={locations} initialFailures={failures} />
    </main>
  );
}
