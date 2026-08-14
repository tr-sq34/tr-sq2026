import { AlarmClock, Gauge, ShieldAlert, Timer } from 'lucide-react';
import { ContentReportQueue } from '@/components/moderation/content-report-queue';
import { MessageReportQueue } from '@/components/moderation/message-report-queue';
import { EmptyState, PageHeader } from '@/components/ui/page';
import { StatCard } from '@/components/ui/stat-card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { canActOnReports, canReviewReports, listReports, moderationOverview, type ModerationOverview, type ReportSummary } from '@/lib/moderation';
import { contentOverview, listContentReports, type ContentOverview, type ContentReportSummary } from '@/lib/content-moderation';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

const formatMinutes = (minutes: number | null) => {
  if (minutes === null) return 'veri yok';
  if (minutes < 60) return `${minutes} dk`;
  return `${Math.floor(minutes / 60)} sa ${minutes % 60} dk`;
};

// The median of two medians is not a median. When both queues have resolved
// something recently the honest summary is the slower of the two, because that
// is the number a reviewer has to bring down.
const worstMedian = (a: number | null, b: number | null) => (a === null ? b : b === null ? a : Math.max(a, b));

export default async function ModerationPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canReviewReports(roles)) {
    return (
      <main>
        <PageHeader eyebrow="Yetki gerekli" tone="warning" title="Moderasyon Merkezi" />
        <EmptyState
          title="Bu alan moderasyon yetkisi gerektirir."
          description={`Mevcut rollerin: ${roles.join(', ')}.`}
        />
      </main>
    );
  }

  // Settled, not all: one service being down must not blank the other's queue.
  // A moderator with a child-safety report waiting in messaging should still see
  // it when community is mid-deploy.
  const [messagingOverviewResult, messagingReportsResult, contentOverviewResult, contentReportsResult] = await Promise.allSettled([
    moderationOverview(),
    listReports({ status: 'unresolved' }),
    contentOverview(),
    listContentReports({ status: 'unresolved' }),
  ]);

  const messagingOverview: ModerationOverview | null = messagingOverviewResult.status === 'fulfilled' ? messagingOverviewResult.value : null;
  const messagingReports: ReportSummary[] = messagingReportsResult.status === 'fulfilled' ? messagingReportsResult.value : [];
  const feedOverview: ContentOverview | null = contentOverviewResult.status === 'fulfilled' ? contentOverviewResult.value : null;
  const contentReports: ContentReportSummary[] = contentReportsResult.status === 'fulfilled' ? contentReportsResult.value : [];

  const messagingFailure = [messagingOverviewResult, messagingReportsResult].find((r) => r.status === 'rejected') as PromiseRejectedResult | undefined;
  const contentFailure = [contentOverviewResult, contentReportsResult].find((r) => r.status === 'rejected') as PromiseRejectedResult | undefined;
  const reasonOf = (result: PromiseRejectedResult | undefined) => (result?.reason instanceof Error ? result.reason.message : 'bilinmeyen hata');

  const totals = {
    open: (messagingOverview?.openReports ?? 0) + (feedOverview?.openReports ?? 0),
    urgent: (messagingOverview?.urgentReports ?? 0) + (feedOverview?.urgentReports ?? 0),
    overdue: (messagingOverview?.overdueReports ?? 0) + (feedOverview?.overdueReports ?? 0),
    resolved7: (messagingOverview?.resolvedLast7Days ?? 0) + (feedOverview?.resolvedLast7Days ?? 0),
    filed7: (messagingOverview?.filedLast7Days ?? 0) + (feedOverview?.filedLast7Days ?? 0),
    restrictions: (messagingOverview?.activeRestrictions ?? 0) + (feedOverview?.activeRestrictions ?? 0),
  };
  const slaHours = messagingOverview?.slaHours ?? feedOverview?.slaHours ?? { urgent: 2, standard: 24 };
  const median = worstMedian(messagingOverview?.medianResolutionMinutes ?? null, feedOverview?.medianResolutionMinutes ?? null);
  // Both summaries missing means the four cards are adding nothing to nothing.
  // Saying "0 bekleyen" then would be the most expensive wrong answer a queue
  // can give, so the cards grey out instead.
  const countsUnavailable = !messagingOverview && !feedOverview;

  return (
    <main>
      <PageHeader
        eyebrow="Mesajlaşma ve içerik moderasyonu"
        title="Moderasyon Merkezi"
        /* The privacy rule is stated where the work happens, not only in a
           policy document: an operator seeing message text needs to know that
           it is a snapshot the reporter submitted, not a window into a live
           conversation. */
        description="Şikâyet edilen mesajlar ve paylaşımlar, şikâyet anında alınan kanıt kopyasından okunur. Canlı özel konuşmalar hiçbir rol tarafından görüntülenemez. Her karar — reddetme dahil — denetim kaydına yazılır."
      />

      {messagingFailure && (
        <p className="mb-4 rounded-card border border-warning/30 bg-warning-soft p-4 text-sm text-warning">
          Mesajlaşma servisi yanıt vermedi: {reasonOf(messagingFailure)}. Aşağıdaki mesaj kuyruğu eksik olabilir.
        </p>
      )}
      {contentFailure && (
        <p className="mb-4 rounded-card border border-warning/30 bg-warning-soft p-4 text-sm text-warning">
          Topluluk servisi yanıt vermedi: {reasonOf(contentFailure)}. Aşağıdaki içerik kuyruğu eksik olabilir.
        </p>
      )}

      <div className="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Bekleyen şikâyet"
          value={countsUnavailable ? 'Yanıt yok' : String(totals.open)}
          detail={`${messagingOverview?.openReports ?? 0} mesaj · ${feedOverview?.openReports ?? 0} içerik`}
          badge={totals.urgent > 0 ? `${totals.urgent} acil` : undefined}
          icon={ShieldAlert}
          tone={totals.urgent > 0 ? 'danger' : 'brand'}
          unavailable={countsUnavailable}
        />
        <StatCard
          label="Süresi geçen"
          value={countsUnavailable ? 'Yanıt yok' : String(totals.overdue)}
          detail={`Hedef: acil ${slaHours.urgent} sa · normal ${slaHours.standard} sa`}
          icon={AlarmClock}
          tone={totals.overdue > 0 ? 'danger' : 'neutral'}
          unavailable={countsUnavailable}
        />
        <StatCard
          label="Ortanca yanıt (30 gün)"
          value={countsUnavailable ? 'Yanıt yok' : formatMinutes(median)}
          detail={`Son 7 günde ${totals.resolved7} sonuçlandı`}
          icon={Timer}
          tone="neutral"
          unavailable={countsUnavailable || median === null}
        />
        <StatCard
          label="Etkin kısıtlama"
          value={countsUnavailable ? 'Yanıt yok' : String(totals.restrictions)}
          detail={`Son 7 günde ${totals.filed7} yeni şikâyet`}
          icon={Gauge}
          tone="neutral"
          unavailable={countsUnavailable}
        />
      </div>

      <Tabs defaultValue="messaging">
        <TabsList className="mb-4">
          <TabsTrigger value="messaging" count={messagingOverview?.openReports ?? messagingReports.length}>Mesaj şikâyetleri</TabsTrigger>
          <TabsTrigger value="content" count={feedOverview?.openReports ?? contentReports.length}>Paylaşım ve yorum şikâyetleri</TabsTrigger>
        </TabsList>
        {/* forceMount, because switching tabs must not throw away the selected
            report or a half-typed reason. Radix unmounts inactive panels by
            default; here they stay mounted and are hidden with CSS. */}
        <TabsContent value="messaging" forceMount className="data-[state=inactive]:hidden">
          <MessageReportQueue initialReports={messagingReports} canAct={canActOnReports(roles)} />
        </TabsContent>
        <TabsContent value="content" forceMount className="data-[state=inactive]:hidden">
          <ContentReportQueue initialReports={contentReports} canAct={canActOnReports(roles)} />
        </TabsContent>
      </Tabs>
    </main>
  );
}
