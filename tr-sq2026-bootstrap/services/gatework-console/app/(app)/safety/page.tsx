import { SafetyDesk } from '@/components/safety/safety-desk';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { canActOnSafety, canSeeSafety, safetyPage } from '@/lib/safety';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function SafetyPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeSafety(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Güvenlik ve SOS" />
        <EmptyState title="Bu alan güvenlik yetkisi gerektirir." description={`Mevcut rollerin: ${roles.join(', ')}.`} />
      </main>
    );
  }

  const { alerts, failure } = await safetyPage();

  return (
    <main>
      <PageHeader
        eyebrow="Topluluk servisi bağlı"
        title="Güvenlik ve SOS"
        description="Yardım isteyen üyeler. En uzun bekleyen en üstte. Üyenin konumu mühürlüdür: bu liste konumu içermez, görmek için gerekçe yazman gerekir, erişim süreyle sınırlıdır ve çağrı kapandığında konum silinir."
      />
      <SafetyDesk initialAlerts={alerts} initialFailure={failure} canAct={canActOnSafety(roles)} />
    </main>
  );
}
