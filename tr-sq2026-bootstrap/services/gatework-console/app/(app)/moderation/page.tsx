import { AlarmClock, Gauge, ShieldAlert, Timer } from 'lucide-react';
import { ContentModerationQueue } from '@/components/content-moderation-queue';
import { ModerationQueue } from '@/components/moderation-queue';
import { QueueTabs } from '@/components/queue-tabs';
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
    return <main><h1 className="text-3xl font-semibold">Moderasyon Merkezi</h1><p className="mt-4 max-w-xl text-zinc-400">Bu alan yalnızca moderasyon yetkisi olan rollere açıktır. Mevcut rollerin: {roles.join(', ')}.</p></main>;
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

  const cards = ([
    ['Bekleyen şikâyet', String(totals.open), `${totals.urgent} acil · ${messagingOverview?.openReports ?? 0} mesaj, ${feedOverview?.openReports ?? 0} içerik`, ShieldAlert],
    ['Süresi geçen', String(totals.overdue), `Hedef: acil ${slaHours.urgent} sa · normal ${slaHours.standard} sa`, AlarmClock],
    ['Ortanca yanıt (30 gün)', formatMinutes(median), `Son 7 günde ${totals.resolved7} sonuçlandı`, Timer],
    ['Etkin kısıtlama', String(totals.restrictions), `Son 7 günde ${totals.filed7} yeni şikâyet`, Gauge],
  ] as const);

  return (
    <main>
      <div className="mb-8">
        <p className="text-sm text-emerald-400">Mesajlaşma ve içerik moderasyonu</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight">Moderasyon Merkezi</h1>
        {/* The privacy rule is stated where the work happens, not only in a
            policy document: an operator seeing message text needs to know that
            it is a snapshot the reporter submitted, not a window into a live
            conversation. */}
        <p className="mt-2 max-w-2xl text-zinc-400">
          Şikâyet edilen mesajlar ve paylaşımlar, şikâyet anında alınan kanıt kopyasından okunur. Canlı özel konuşmalar hiçbir rol tarafından görüntülenemez. Her karar — reddetme dahil — denetim kaydına yazılır.
        </p>
      </div>

      {messagingFailure && <p className="mb-4 rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">Mesajlaşma servisi yanıt vermedi: {reasonOf(messagingFailure)}. Aşağıdaki mesaj kuyruğu eksik olabilir.</p>}
      {contentFailure && <p className="mb-4 rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">Topluluk servisi yanıt vermedi: {reasonOf(contentFailure)}. Aşağıdaki içerik kuyruğu eksik olabilir.</p>}

      <div className="mb-8 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {cards.map(([title, value, hint, Icon]) => (
          <article key={title} className={`rounded-xl border p-5 ${title === 'Süresi geçen' && totals.overdue > 0 ? 'border-rose-500/40 bg-rose-500/10' : 'border-white/10 bg-zinc-900/50'}`}>
            <Icon size={20} className="text-emerald-400" />
            <p className="mt-4 text-sm text-zinc-400">{title}</p>
            <p className="mt-1 text-2xl font-semibold">{value}</p>
            <p className="mt-2 text-xs text-zinc-500">{hint}</p>
          </article>
        ))}
      </div>

      <QueueTabs
        tabs={[
          { key: 'messaging', label: 'Mesaj şikâyetleri', badge: messagingOverview?.openReports ?? messagingReports.length, panel: <ModerationQueue initialReports={messagingReports} canAct={canActOnReports(roles)} /> },
          { key: 'content', label: 'Paylaşım ve yorum şikâyetleri', badge: feedOverview?.openReports ?? contentReports.length, panel: <ContentModerationQueue initialReports={contentReports} canAct={canActOnReports(roles)} /> },
        ]}
      />
    </main>
  );
}
