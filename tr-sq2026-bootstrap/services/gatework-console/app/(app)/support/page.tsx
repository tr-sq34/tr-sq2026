import { SupportDesk } from '@/components/support/support-desk';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { getSession } from '@/lib/session';
import { canAnswerSupport, canSeeSupport, supportPage } from '@/lib/support';

export const dynamic = 'force-dynamic';

export default async function SupportPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeSupport(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Destek Talepleri" />
        <EmptyState title="Bu alan destek yetkisi gerektirir." description={`Mevcut rollerin: ${roles.join(', ')}.`} />
      </main>
    );
  }

  const { requests, failure } = await supportPage();

  return (
    <main>
      <PageHeader
        eyebrow="Topluluk servisi bağlı"
        title="Destek Talepleri"
        description="Üyelerin uygulamadan yazdığı talepler. En uzun süredir cevap bekleyen en üstte. Şikâyetlerden ayrıdır: şikâyet başka bir üyeyi işaret eder, buradaki muhatap biziz. Kısıtlanmış üyeler de yazabilir — bir karara itiraz edebilecekleri tek yer burası."
      />
      <SupportDesk initialRequests={requests} initialFailure={failure} canAnswer={canAnswerSupport(roles)} />
    </main>
  );
}
