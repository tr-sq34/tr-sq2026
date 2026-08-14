import { AuditLog } from '@/components/system/audit-log';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { auditPage, canSeeAudit, type AuditRow } from '@/lib/audit';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function SystemPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeeAudit(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Sistem ve Denetim" />
        <EmptyState
          title="Denetim kaydı yalnızca owner, güvenlik yöneticisi ve denetçi rollerine açıktır."
          description={`Mevcut rollerin: ${roles.join(', ')}.`}
        />
      </main>
    );
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
      <PageHeader
        eyebrow="Kimlik + Topluluk + Mesajlaşma bağlı"
        title="Sistem ve Denetim"
        description="Panelden yapılan her yetkili işlem — rol verme, oturum sonlandırma, şikâyet kararı, kısıtlama, forum ve içerik değişiklikleri — gerekçesiyle birlikte buraya yazılır. Bu ekran yalnızca okur; kayıt buradan değiştirilemez ve silinemez."
      />
      <AuditLog initialRows={rows} initialFailures={failures} />
    </main>
  );
}
