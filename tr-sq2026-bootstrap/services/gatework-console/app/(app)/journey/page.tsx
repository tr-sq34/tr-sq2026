import { JourneyDesk } from '@/components/journey/journey-desk';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { canGrantBadge, canSeeJourney, journeyPage } from '@/lib/journey';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function JourneyPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeJourney(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Rozetler ve Yolculuk" />
        <EmptyState title="Bu alan topluluk yetkisi gerektirir." description={`Mevcut rollerin: ${roles.join(', ')}.`} />
      </main>
    );
  }

  const { overview, failure } = await journeyPage();

  return (
    <main>
      <PageHeader
        eyebrow="Topluluk servisi bağlı"
        title="Rozetler ve Yolculuk"
        description="Gurbet Yolculuğu'nun panel tarafı: katalogdaki her rozet, kaç üyeye gitti, sayacı işliyor mu ve elle verilenler kime hangi gerekçeyle verildi. Kuralı olmayan rozetler en üstte duruyor — üye kriterini uygulamada okuyor, o kriteri sağlayacak kod yok."
      />
      <JourneyDesk initial={overview} initialFailure={failure} canGrant={canGrantBadge(roles)} />
    </main>
  );
}
