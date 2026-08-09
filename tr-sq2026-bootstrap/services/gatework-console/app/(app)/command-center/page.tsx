import Link from 'next/link';
import { Activity, Clock3, ShieldCheck, TriangleAlert } from 'lucide-react';
import { canReviewReports, moderationOverview, type ModerationOverview } from '@/lib/moderation';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

export default async function CommandCenter() {
  const session = await getSession();
  const roles = session?.member.roles ?? [];

  // The review queue is the one number on this page that is real. It is fetched
  // rather than hard-coded because a stale "0 waiting" is worse than no card:
  // the 24-hour promise this app makes to Apple and Google is measured here.
  let overview: ModerationOverview | null = null;
  if (canReviewReports(roles)) overview = await moderationOverview().catch(() => null);

  const queueDescription = !canReviewReports(roles)
    ? 'Bu rol için moderasyon verisi gösterilmez'
    : overview
      ? `${overview.openReports} bekleyen · ${overview.overdueReports} süresi geçen`
      : 'Mesajlaşma servisine ulaşılamadı';

  const cards = [
    ['Servis sağlığı', 'Bağlı servislerden veri bekleniyor', Activity, null],
    ['İnceleme kuyruğu', queueDescription, ShieldCheck, '/moderation'],
    ['Kritik olay', 'SOS altyapısı etkin değil', TriangleAlert, null],
    ['Son işlem', overview ? `Son 7 günde ${overview.resolvedLast7Days} şikâyet sonuçlandı` : 'Henüz audit olayı yok', Clock3, '/communications'],
  ] as const;

  return (
    <main>
      <div className="mb-8">
        <p className="text-sm text-emerald-400">Operasyon görünümü</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight">Komuta Merkezi</h1>
        <p className="mt-2 max-w-2xl text-zinc-400">Yalnızca etkin servisler gerçek veri sağlar. Hazır olmayan modüller yanlış operasyon verisi göstermez.</p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {cards.map(([title, description, Icon, href]) => {
          const urgent = title === 'İnceleme kuyruğu' && (overview?.overdueReports ?? 0) > 0;
          const body = (
            <article className={`h-full rounded-xl border p-5 ${urgent ? 'border-rose-500/40 bg-rose-500/10' : 'border-white/10 bg-zinc-900/50'} ${href ? 'transition hover:border-emerald-400/40' : ''}`}>
              <Icon size={20} className="text-emerald-400" />
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
