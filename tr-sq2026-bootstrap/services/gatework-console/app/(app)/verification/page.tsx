import { VerificationDesk } from '@/components/verification-desk';
import { canSeeVerification, verificationPage } from '@/lib/verification';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function VerificationPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeVerification(roles)) {
    return <main><h1 className="text-3xl font-semibold">Doğrulama</h1><p className="mt-4 max-w-xl text-zinc-400">Bu alan doğrulama yetkisi gerektirir. Mevcut rollerin: {roles.join(', ')}.</p></main>;
  }

  const { overview, sessions, failure } = await verificationPage();

  return (
    <main>
      <div className="mb-8">
        <p className="text-sm text-emerald-400">Doğrulama kasası bağlı</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight">Doğrulama</h1>
        <p className="mt-2 max-w-2xl text-zinc-400">
          Onaylı Hesap akışının nerede olduğunu gösterir. Karar Stripe&apos;a aittir ve kayıt webhook ile düşer; bu ekrandan kimse onaylanamaz veya reddedilemez. Belge, fotoğraf ve kimlik bilgisi burada yoktur — kasa bunları hiç saklamaz, yalnızca durumu tutar.
        </p>
      </div>

      <VerificationDesk initialOverview={overview} initialSessions={sessions} initialFailure={failure} />
    </main>
  );
}
