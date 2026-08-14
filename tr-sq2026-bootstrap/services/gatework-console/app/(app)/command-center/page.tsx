import Link from 'next/link';
import { Activity, Clock3, ShieldCheck, TriangleAlert } from 'lucide-react';
import { canReviewReports, moderationOverview, type ModerationOverview } from '@/lib/moderation';
import { canSeeServiceHealth, healthSummary, serviceHealth, type ServiceHealth } from '@/lib/health';
import { canSeeSafety, isOpen, safetyPage, waitedFor } from '@/lib/safety';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function CommandCenter() {
  const session = await getSession();
  const roles = session?.member.roles ?? [];

  // Nothing on this page is hard-coded any more. Every card is either a number
  // a service answered with, or a sentence saying which service did not answer;
  // a stale "0 waiting" is worse than no card, and a permanent "not connected
  // yet" on a module that has been live for weeks is worse than both.
  const [overview, health, safety] = await Promise.all([
    canReviewReports(roles) ? moderationOverview().catch(() => null) : Promise.resolve(null),
    canSeeServiceHealth(roles) ? serviceHealth().catch(() => null) : Promise.resolve(null),
    canSeeSafety(roles) ? safetyPage() : Promise.resolve(null),
  ]) as [ModerationOverview | null, ServiceHealth[] | null, Awaited<ReturnType<typeof safetyPage>> | null];

  const queueDescription = !canReviewReports(roles)
    ? 'Bu rol için moderasyon verisi gösterilmez'
    : overview
      ? `${overview.openReports} bekleyen · ${overview.overdueReports} süresi geçen`
      : 'Mesajlaşma servisine ulaşılamadı';

  const healthDescription = !canSeeServiceHealth(roles)
    ? 'Bu rol için servis durumu gösterilmez'
    : health
      ? healthSummary(health)
      : 'Servis durumu okunamadı';
  const healthUrgent = (health ?? []).some((check) => !check.healthy);

  // The alert that has been waiting longest is the only number here that gets
  // worse while nobody looks at it, so it is the one the card carries.
  const openAlerts = (safety?.alerts ?? []).filter(isOpen);
  const oldest = openAlerts.reduce<string | null>(
    (waiting, alert) => (waiting === null || alert.createdAt < waiting ? alert.createdAt : waiting),
    null,
  );
  const safetyDescription = !canSeeSafety(roles)
    ? 'Bu rol için güvenlik verisi gösterilmez'
    : safety?.failure
      ? 'Güvenlik servisine ulaşılamadı'
      : openAlerts.length === 0
        ? 'Açık çağrı yok'
        : `${openAlerts.length} açık çağrı · en eskisi ${waitedFor(oldest!, Date.now())} bekliyor`;

  const cards = [
    ['Servis sağlığı', healthDescription, Activity, canSeeServiceHealth(roles) ? '/system' : null, healthUrgent],
    ['İnceleme kuyruğu', queueDescription, ShieldCheck, '/moderation', (overview?.overdueReports ?? 0) > 0],
    ['Kritik olay', safetyDescription, TriangleAlert, canSeeSafety(roles) ? '/safety' : null, openAlerts.length > 0],
    ['Son işlem', overview ? `Son 7 günde ${overview.resolvedLast7Days} şikâyet sonuçlandı` : 'Henüz audit olayı yok', Clock3, '/communications', false],
  ] as const;

  return (
    <main>
      <div className="mb-8">
        <p className="text-sm text-emerald-400">Operasyon görünümü</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight">Komuta Merkezi</h1>
        <p className="mt-2 max-w-2xl text-zinc-400">Buradaki her sayı bir servisin verdiği yanıttır. Servis yanıt vermediğinde kart eski sayıyı göstermez, ulaşılamadığını söyler.</p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {cards.map(([title, description, Icon, href, urgent]) => {
          const body = (
            <article className={`h-full rounded-xl border p-5 ${urgent ? 'border-rose-500/40 bg-rose-500/10' : 'border-white/10 bg-zinc-900/50'} ${href ? 'transition hover:border-emerald-400/40' : ''}`}>
              <Icon size={20} className={urgent ? 'text-rose-300' : 'text-emerald-400'} />
              <h2 className="mt-5 font-medium">{title}</h2>
              <p className="mt-2 text-sm text-zinc-500">{description}</p>
            </article>
          );
          return href ? <Link key={title} href={href}>{body}</Link> : <div key={title}>{body}</div>;
        })}
      </div>
      <section className="mt-8 rounded-xl border border-white/10 bg-zinc-900/30 p-6">
        <h2 className="font-semibold">Güvenlik durumu</h2>
        <ul className="mt-4 grid gap-3 text-sm text-zinc-300">
          <li>✓ Gatework uygulama verileri önbelleğe alınmaz.</li>
          <li>✓ Yüksek riskli işlemler için step-up doğrulama zorunludur.</li>
          <li>✓ Normal kullanıcı taklidi yerine resmî sistem hesapları kullanılır.</li>
          <li>✓ Şikâyet edilen mesajlar yalnızca donmuş kanıt kopyası olarak görüntülenir; canlı özel konuşma okunamaz.</li>
        </ul>
      </section>
    </main>
  );
}
