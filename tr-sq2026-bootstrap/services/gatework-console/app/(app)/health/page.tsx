import { HealthBoard } from '@/components/system/health-board';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { canSeeServiceHealth, systemHealthSnapshot } from '@/lib/health';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

/**
 * Sistem Sağlığı ve Bakım.
 *
 * The first snapshot is taken on the server so the page is already true when it
 * paints - a status board that opens empty and fills in a second later is a
 * status board that reads as "everything is fine" for that second.
 */
export default async function HealthPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeServiceHealth(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Sistem Sağlığı ve Bakım" />
        <EmptyState
          title="Sistem durumu yalnızca owner, güvenlik yöneticisi, operasyon yöneticisi ve denetçi rollerine açıktır."
          description={`Mevcut rollerin: ${roles.join(', ')}.`}
        />
      </main>
    );
  }

  const snapshot = await systemHealthSnapshot(24);

  return (
    <main>
      <PageHeader
        eyebrow="Canlı izleme"
        tone={snapshot.risk.level === 'kritik' ? 'danger' : snapshot.risk.level === 'saglikli' ? 'success' : 'warning'}
        title="Sistem Sağlığı ve Bakım"
        description="Servislerin ayakta olup olmadığı, uygulamanın üyelerin telefonunda çökme oranı ve bu ikisinin tek bir sorun riskindeki karşılığı. Ölçülemeyen hiçbir şey iyi sayılmaz; ölçülemediği yazılır."
      />
      <HealthBoard initial={snapshot} />
    </main>
  );
}
