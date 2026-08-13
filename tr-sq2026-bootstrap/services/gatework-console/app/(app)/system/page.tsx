import { AuditLog } from '@/components/audit-log';
import { auditPage, canSeeAudit, type AuditRow } from '@/lib/audit';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function SystemPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeAudit(roles)) {
    return <main><h1 className="text-3xl font-semibold">Sistem ve Denetim</h1><p className="mt-4 max-w-xl text-zinc-400">Denetim kaydı yalnızca owner, güvenlik yöneticisi ve denetçi rollerine açıktır. Mevcut rollerin: {roles.join(', ')}.</p></main>;
  }

  let rows: AuditRow[] = [];
  let failures: string[] = [];
  try {
    ({ rows, failures } = await auditPage());
  } catch {
    failures = ['Kimlik', 'Topluluk', 'Mesajlaşma'];
  }

  return (
    <main>
      <div className="mb-8">
        <p className="text-sm text-emerald-400">Kimlik + Topluluk + Mesajlaşma bağlı</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight">Sistem ve Denetim</h1>
        <p className="mt-2 max-w-2xl text-zinc-400">
          Panelden yapılan her yetkili işlem — rol verme, oturum sonlandırma, şikâyet kararı, kısıtlama, forum ve içerik değişiklikleri — gerekçesiyle birlikte buraya yazılır. Bu ekran yalnızca okur; kayıt buradan değiştirilemez ve silinemez.
        </p>
      </div>

      <AuditLog initialRows={rows} initialFailures={failures} />
    </main>
  );
}
