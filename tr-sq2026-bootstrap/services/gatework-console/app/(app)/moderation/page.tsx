import { AlarmClock, Gauge, ShieldAlert, Timer } from 'lucide-react';
import { ModerationQueue } from '@/components/moderation-queue';
import { canActOnReports, canReviewReports, listReports, moderationOverview, type ModerationOverview, type ReportSummary } from '@/lib/moderation';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

const formatMinutes = (minutes: number | null) => {
  if (minutes === null) return 'veri yok';
  if (minutes < 60) return `${minutes} dk`;
  return `${Math.floor(minutes / 60)} sa ${minutes % 60} dk`;
};

export default async function ModerationPage() {
  const session = await getSession();
  if (!session) return null;
  const roles = session.member.roles;

  if (!canReviewReports(roles)) {
    return <main><h1 className="text-3xl font-semibold">Moderasyon Merkezi</h1><p className="mt-4 max-w-xl text-zinc-400">Bu alan yalnızca moderasyon yetkisi olan rollere açıktır. Mevcut rollerin: {roles.join(', ')}.</p></main>;
  }

  let overview: ModerationOverview | null = null;
  let reports: ReportSummary[] = [];
  let failure: string | null = null;
  try {
    [overview, reports] = await Promise.all([moderationOverview(), listReports({ status: 'unresolved' })]);
  } catch (error) {
    failure = error instanceof Error ? error.message : 'Mesajlaşma servisine ulaşılamadı.';
  }

  const cards = overview
    ? ([
        ['Bekleyen şikâyet', String(overview.openReports), `${overview.urgentReports} acil`, ShieldAlert],
        ['Süresi geçen', String(overview.overdueReports), `Hedef: acil ${overview.slaHours.urgent} sa · normal ${overview.slaHours.standard} sa`, AlarmClock],
        ['Ortanca yanıt (30 gün)', formatMinutes(overview.medianResolutionMinutes), `Son 7 günde ${overview.resolvedLast7Days} sonuçlandı`, Timer],
        ['Etkin kısıtlama', String(overview.activeRestrictions), `Son 7 günde ${overview.filedLast7Days} yeni şikâyet`, Gauge],
      ] as const)
    : [];

  return (
    <main>
      <div className="mb-8">
        <p className="text-sm text-emerald-400">Mesajlaşma moderasyonu</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight">Moderasyon Merkezi</h1>
        {/* The privacy rule is stated where the work happens, not only in a
            policy document: an operator seeing message text needs to know that
            it is a snapshot the reporter submitted, not a window into a live
            conversation. */}
        <p className="mt-2 max-w-2xl text-zinc-400">
          Şikâyet edilen mesajlar, şikâyet anında alınan kanıt kopyasından okunur. Canlı özel konuşmalar hiçbir rol tarafından görüntülenemez. Her karar — reddetme dahil — denetim kaydına yazılır.
        </p>
      </div>

      {failure && <p className="mb-6 rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">Mesajlaşma servisi yanıt vermedi: {failure}</p>}

      {overview && (
        <div className="mb-8 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          {cards.map(([title, value, hint, Icon]) => (
            <article key={title} className={`rounded-xl border p-5 ${title === 'Süresi geçen' && overview.overdueReports > 0 ? 'border-rose-500/40 bg-rose-500/10' : 'border-white/10 bg-zinc-900/50'}`}>
              <Icon size={20} className="text-emerald-400" />
              <p className="mt-4 text-sm text-zinc-400">{title}</p>
              <p className="mt-1 text-2xl font-semibold">{value}</p>
              <p className="mt-2 text-xs text-zinc-500">{hint}</p>
            </article>
          ))}
        </div>
      )}

      <ModerationQueue initialReports={reports} canAct={canActOnReports(roles)} />
    </main>
  );
}
