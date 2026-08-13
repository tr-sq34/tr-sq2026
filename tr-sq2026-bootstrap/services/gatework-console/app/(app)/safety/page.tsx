import { SafetyDesk } from '@/components/safety-desk';
import { canActOnSafety, canSeeSafety, safetyPage } from '@/lib/safety';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function SafetyPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeSafety(roles)) {
    return <main><h1 className="text-3xl font-semibold">Güvenlik ve SOS</h1><p className="mt-4 max-w-xl text-zinc-400">Bu alan güvenlik yetkisi gerektirir. Mevcut rollerin: {roles.join(', ')}.</p></main>;
  }

  const { alerts, failure } = await safetyPage();

  return (
    <main>
      <div className="mb-8">
        <p className="text-sm text-emerald-400">Topluluk servisi bağlı</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight">Güvenlik ve SOS</h1>
        <p className="mt-2 max-w-2xl text-zinc-400">
          Yardım isteyen üyeler. En uzun bekleyen en üstte. Üyenin konumu <strong>mühürlüdür</strong>: bu liste konumu içermez, görmek için gerekçe yazman gerekir, erişim süreyle sınırlıdır ve çağrı kapandığında konum silinir.
        </p>
      </div>

      <SafetyDesk initialAlerts={alerts} initialFailure={failure} canAct={canActOnSafety(roles)} />
    </main>
  );
}
