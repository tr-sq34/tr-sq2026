import { PromotionDesk } from '@/components/promotions/promotion-desk';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { listSystemAccounts, type SystemAccount } from '@/lib/content';
import { canDecidePromotions, canSeePromotions, listPromotions } from '@/lib/promotions';
import type { PromotionSummary } from '@/lib/promotion-labels';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function PromotionsPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canSeePromotions(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Tanıtımlar" />
        <EmptyState title="Bu alan tanıtım yetkisi gerektirir." description={`Mevcut rollerin: ${roles.join(', ')}.`} />
      </main>
    );
  }

  // Three independent reads. The queue and the running list are the two tabs an
  // operator opens first, and the account list only feeds the place form - one
  // failing must not take the others down.
  const [pending, approved, accounts] = await Promise.all([
    listPromotions('pending').catch((error: unknown) => (error instanceof Error ? error : new Error('Kuyruk okunamadı.'))),
    listPromotions('approved').catch(() => [] as PromotionSummary[]),
    listSystemAccounts().catch(() => [] as SystemAccount[]),
  ]);

  const failed = pending instanceof Error;

  return (
    <main>
      <PageHeader
        eyebrow="Topluluk servisine bağlı"
        title="Tanıtımlar"
        description="Üyelerin Story alanı ve banner talepleri burada onaylanır; “Sana Özel Öne Çıkanlar” kartları yalnızca panelden yerleştirilir. Gösterim ve tıklanma sayıları uygulamanın kendi saydığı sayılardır. Bu fazda ödeme alınmaz."
      />
      <PromotionDesk
        initialPending={failed ? [] : (pending as PromotionSummary[])}
        initialApproved={approved}
        accounts={accounts}
        loadFailure={failed ? `Tanıtım kuyruğu okunamadı: ${(pending as Error).message}.` : null}
        canDecide={canDecidePromotions(roles)}
      />
    </main>
  );
}
