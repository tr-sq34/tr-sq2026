import { MessagingOperations } from '@/components/messaging-operations';
import { canActOnReports, canReviewReports, canTakeDownGroups, listAudit, listGroups, listRestrictions, type AuditRow, type ModeratedGroup, type RestrictionRow } from '@/lib/moderation';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function CommunicationsPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canReviewReports(roles)) {
    return <main><h1 className="text-3xl font-semibold">Mesajlar ve Forum</h1><p className="mt-4 max-w-xl text-zinc-400">Bu alan moderasyon yetkisi gerektirir. Mevcut rollerin: {roles.join(', ')}.</p></main>;
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
      <div className="mb-8">
        <p className="text-sm text-emerald-400">Mesajlaşma operasyonu</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight">Mesajlar ve Forum</h1>
        <p className="mt-2 max-w-2xl text-zinc-400">
          Gruplar, etkin kısıtlamalar ve moderasyon denetim kaydı. Konuşma içerikleri burada da görünmez; içerik yalnızca bir şikâyete bağlı kanıt kopyası olarak Moderasyon Merkezi&apos;nde okunur.
        </p>
      </div>
      {failure && <p className="mb-6 rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">Mesajlaşma servisi yanıt vermedi: {failure}</p>}
      <MessagingOperations groups={groups} restrictions={restrictions} audit={audit} canTakeDown={canTakeDownGroups(roles)} canAct={canActOnReports(roles)} />
    </main>
  );
}
