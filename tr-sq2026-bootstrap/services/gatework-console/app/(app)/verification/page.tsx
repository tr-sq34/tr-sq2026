import { VerificationDesk } from '@/components/verification/verification-desk';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { canSeeVerification, verificationPage } from '@/lib/verification';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function VerificationPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeVerification(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Doğrulama" />
        <EmptyState title="Bu alan doğrulama yetkisi gerektirir." description={`Mevcut rollerin: ${roles.join(', ')}.`} />
      </main>
    );
  }

  const { overview, sessions, failure } = await verificationPage();

  return (
    <main>
      <PageHeader
        eyebrow="Doğrulama kasası bağlı"
        title="Doğrulama"
        description="Onaylı Hesap akışının nerede olduğunu gösterir. Karar Stripe'a aittir ve kayıt webhook ile düşer; bu ekrandan kimse onaylanamaz veya reddedilemez. Belge, fotoğraf ve kimlik bilgisi burada yoktur — kasa bunları hiç saklamaz, yalnızca durumu tutar."
      />
      <VerificationDesk initialOverview={overview} initialSessions={sessions} initialFailure={failure} />
    </main>
  );
}
