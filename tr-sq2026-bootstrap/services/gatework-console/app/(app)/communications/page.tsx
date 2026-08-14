import { MessagingOperations } from '@/components/moderation/messaging-operations';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { canActOnReports, canReviewReports, canTakeDownGroups, listAudit, listGroups, listRestrictions, type AuditRow, type ModeratedGroup, type RestrictionRow } from '@/lib/moderation';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function CommunicationsPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canReviewReports(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Mesajlar" />
        <EmptyState title="Bu alan moderasyon yetkisi gerektirir." description={`Mevcut rollerin: ${roles.join(', ')}.`} />
      </main>
    );
  }

  let groups: ModeratedGroup[] = [];
  let restrictions: RestrictionRow[] = [];
  let audit: AuditRow[] = [];
  let failure: string | null = null;
  try {
    [groups, restrictions, audit] = await Promise.all([listGroups(), listRestrictions(), listAudit()]);
  } catch (error) {
    failure = error instanceof Error ? error.message : 'Mesajlaşma servisine ulaşılamadı.';
  }

  return (
    <main>
      <PageHeader
        eyebrow="Mesajlaşma operasyonu"
        title="Mesajlar"
        description="Gruplar, etkin kısıtlamalar ve moderasyon denetim kaydı. Konuşma içerikleri burada da görünmez; içerik yalnızca bir şikâyete bağlı kanıt kopyası olarak Moderasyon Merkezi’nde okunur."
      />
      {failure && (
        <p className="mb-6 rounded-card border border-warning/30 bg-warning-soft p-4 text-sm text-warning">
          Mesajlaşma servisi yanıt vermedi: {failure}
        </p>
      )}
      <MessagingOperations groups={groups} restrictions={restrictions} audit={audit} canTakeDown={canTakeDownGroups(roles)} canAct={canActOnReports(roles)} />
    </main>
  );
}
