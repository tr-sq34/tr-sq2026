import Link from 'next/link';
import {
  Activity, BadgeCheck, Gavel, Megaphone, MessageSquare, Radio, ShieldAlert, Siren, TrendingUp,
} from 'lucide-react';
import { canSendAnnouncement } from '@/lib/announcements';
import { canReviewReports, moderationOverview, type ModerationOverview } from '@/lib/moderation';
import { contentOverview, type ContentOverview } from '@/lib/content-moderation';
import { RISK_LEVELS, canSeeServiceHealth, systemHealthSnapshot, type SystemHealthSnapshot } from '@/lib/health';
import { canSeeSafety, isOpen, safetyPage, waitedFor } from '@/lib/safety';
import { canSeeVerification, verificationPage } from '@/lib/verification';
import { canSeeMarketplace, marketplacePage } from '@/lib/marketplace';
import { listPromotions } from '@/lib/promotions';
import { getSession } from '@/lib/session';
import { AnnouncementDialog } from '@/components/command-center/announcement-dialog';
import { HealthBoard } from '@/components/system/health-board';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { PageHeader } from '@/components/ui/page';
import { StatCard } from '@/components/ui/stat-card';

export const dynamic = 'force-dynamic';

/**
 * Komuta Merkezi.
 *
 * The rule this page is built on has not changed: every number is one a service
 * answered with, and a service that did not answer produces a sentence saying
 * so rather than a stale figure. A "0 bekleyen" that is really "the messaging
 * gateway is down" is the most expensive wrong answer a console can give, since
 * it reads as "nothing to do".
 *
 * What changed is coverage. The page used to ask three services and show four
 * cards, two of which were prose. An operator opening the console still had to
 * visit six sections to find out whether anything was waiting. Every queue in
 * the console now reports here.
 *
 * The two cards at the bottom are the exception that proves the rule: real-time
 * presence and daily transaction volume are on the specification but have no
 * backend at all - no presence tracking, no wallet, no ledger. They are drawn
 * as explicitly unavailable instead of being quietly dropped, so the gap stays
 * visible to whoever picks the work up.
 */
export default async function CommandCenter() {
  const session = await getSession();
  const roles = session?.member.roles ?? [];

  // Every one of these catches, without exception. This page asks seven
  // services and `Promise.all` rejects on the first refusal, so a single one of
  // them throwing is a server error page instead of a dashboard - which is
  // exactly what happened when Identity started refusing delegation tokens.
  // Each loader already reports its own failure; the catch is the guarantee
  // that none of them can reach the renderer.
  const [messaging, content, health, safety, verification, marketplace, promotions] = await Promise.all([
    canReviewReports(roles) ? moderationOverview().catch(() => null) : Promise.resolve(null),
    canReviewReports(roles) ? contentOverview().catch(() => null) : Promise.resolve(null),
    canSeeServiceHealth(roles) ? systemHealthSnapshot(24).catch(() => null) : Promise.resolve(null),
    canSeeSafety(roles) ? safetyPage().catch(() => null) : Promise.resolve(null),
    canSeeVerification(roles) ? verificationPage().catch(() => null) : Promise.resolve(null),
    canSeeMarketplace(roles) ? marketplacePage().catch(() => null) : Promise.resolve(null),
    listPromotions('pending').catch(() => null),
  ]) as [
    ModerationOverview | null,
    ContentOverview | null,
    SystemHealthSnapshot | null,
    Awaited<ReturnType<typeof safetyPage>> | null,
    Awaited<ReturnType<typeof verificationPage>> | null,
    Awaited<ReturnType<typeof marketplacePage>> | null,
    Awaited<ReturnType<typeof listPromotions>> | null,
  ];

  // The alert that has been waiting longest is the only number here that gets
  // worse while nobody looks at it, so it is the one the card carries.
  const openAlerts = (safety?.alerts ?? []).filter(isOpen);
  const oldestAlert = openAlerts.reduce<string | null>(
    (waiting, alert) => (waiting === null || alert.createdAt < waiting ? alert.createdAt : waiting),
    null,
  );

  const pendingVerification =
    (verification?.overview?.counts.created ?? 0) + (verification?.overview?.counts.requires_input ?? 0);

  /** A queue card: the count when a service answered, and why not when it did not. */
  const queue = (
    allowed: boolean,
    data: unknown,
    count: number,
    detail: string,
    urgentCount: number,
  ) => {
    if (!allowed) return { value: '—', detail: 'Bu rol için gösterilmez', unavailable: true, tone: 'neutral' as const };
    if (data === null || data === undefined) return { value: '—', detail: 'Servise ulaşılamadı', unavailable: true, tone: 'warning' as const };
    return {
      value: String(count),
      detail,
      unavailable: false,
      tone: urgentCount > 0 ? ('danger' as const) : count > 0 ? ('warning' as const) : ('success' as const),
    };
  };

  const messagingCard = queue(
    canReviewReports(roles), messaging, messaging?.openReports ?? 0,
    messaging ? `${messaging.overdueReports} süresi geçen · son 7 günde ${messaging.resolvedLast7Days} sonuçlandı` : '',
    messaging?.overdueReports ?? 0,
  );
  const contentCard = queue(
    canReviewReports(roles), content, content?.openReports ?? 0,
    content ? `${content.urgentReports} acil · ${content.overdueReports} süresi geçen` : '',
    content?.overdueReports ?? 0,
  );
  const safetyCard = queue(
    canSeeSafety(roles), safety?.failure ? null : safety, openAlerts.length,
    openAlerts.length === 0 ? 'Açık çağrı yok' : `En eskisi ${waitedFor(oldestAlert!, Date.now())} bekliyor`,
    openAlerts.length,
  );
  const verificationCard = queue(
    canSeeVerification(roles), verification?.failure ? null : verification?.overview, pendingVerification,
    verification?.overview ? `${verification.overview.total} başvurunun ${pendingVerification} tanesi sırada` : '',
    0,
  );

  return (
    <>
      <PageHeader
        eyebrow="Operasyon görünümü"
        title="Komuta Merkezi"
        description="Buradaki her sayı bir servisin verdiği yanıttır. Servis yanıt vermediğinde kart eski sayıyı göstermez, ulaşılamadığını söyler."
        actions={
          <>
            {/* Duyuru writes for real now: migration 033 gave the community
                service a table and a fan-out, and the button opens the composer. */}
            <AnnouncementDialog canSend={canSendAnnouncement(roles)} />
            {/* The header carries the risk number itself, not a link to where it
                lives. An operator who opens the console and reads nothing else
                should still learn whether anything is on fire. Bakım modu moved
                to that page too: it has no switch in any service yet, and the
                sentence explaining why belongs next to the rest of the system
                state rather than under a disabled button here. */}
            {canSeeServiceHealth(roles) && (
              <Link
                href="/health"
                className="flex items-center gap-2 rounded-lg border border-hairline px-3 py-2 text-sm text-ink-muted transition hover:border-brand-400/50 hover:text-ink"
              >
                <Activity size={15} className="text-ink-faint" />
                Sistem sağlığı
                <Badge tone={health?.risk.level ? RISK_LEVELS[health.risk.level].tone : 'warning'} dot>
                  {health?.risk.score === null || health === null ? 'Ölçülemedi' : `%${health.risk.score}`}
                </Badge>
              </Link>
            )}
          </>
        }
      />

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Mesaj şikâyetleri" value={messagingCard.value} detail={messagingCard.detail}
          icon={MessageSquare} tone={messagingCard.tone} unavailable={messagingCard.unavailable}
          href={canReviewReports(roles) ? '/moderation' : null}
        />
        <StatCard
          label="İçerik şikâyetleri" value={contentCard.value} detail={contentCard.detail}
          icon={ShieldAlert} tone={contentCard.tone} unavailable={contentCard.unavailable}
          href={canReviewReports(roles) ? '/moderation' : null}
        />
        <StatCard
          label="Açık SOS çağrısı" value={safetyCard.value} detail={safetyCard.detail}
          icon={Siren} tone={safetyCard.tone} unavailable={safetyCard.unavailable}
          href={canSeeSafety(roles) ? '/safety' : null}
        />
        <StatCard
          label="Bekleyen doğrulama" value={verificationCard.value} detail={verificationCard.detail}
          icon={BadgeCheck} tone={verificationCard.tone} unavailable={verificationCard.unavailable}
          href={canSeeVerification(roles) ? '/verification' : null}
        />
      </section>

      <section className="mt-4 grid gap-4 lg:grid-cols-3">
        {/* The board refreshes itself every thirty seconds, so this half of the
            dashboard stays true while an operator reads the rest of it. */}
        <div className="lg:col-span-2">
          {!canSeeServiceHealth(roles) ? (
            <Card>
              <CardHeader><div><CardTitle>Sistem sağlığı</CardTitle></div></CardHeader>
              <CardContent><p className="text-sm text-ink-faint">Bu rol için servis durumu gösterilmez.</p></CardContent>
            </Card>
          ) : health === null ? (
            <Card>
              <CardHeader>
                <div><CardTitle>Sistem sağlığı</CardTitle></div>
                <Badge tone="warning" dot>Ölçülemedi</Badge>
              </CardHeader>
              <CardContent>
                <p className="text-sm text-warning">
                  Sistem durumu okunamadı. Bu kutunun boş olması da bir bulgu; yeşil göstermek yerine söylüyoruz.
                </p>
              </CardContent>
            </Card>
          ) : (
            <HealthBoard initial={health} compact />
          )}
        </div>

        <Card>
          <CardHeader>
            <div>
              <CardTitle>Onay bekleyenler</CardTitle>
              <CardDescription>Bir yetkilinin karar vermesini bekleyen kuyruklar.</CardDescription>
            </div>
          </CardHeader>
          <CardContent className="grid gap-2.5">
            <PendingRow
              icon={Megaphone} label="Tanıtım talebi" href="/promotions"
              value={promotions === null ? null : promotions.length}
            />
            <PendingRow
              icon={Gavel} label="Biten ihale" href="/marketplace"
              value={!canSeeMarketplace(roles) ? undefined : marketplace?.overview ? marketplace.overview.endingSoon : null}
            />
            <PendingRow
              icon={TrendingUp} label="Son 7 günde yeni ilan" href="/marketplace"
              value={!canSeeMarketplace(roles) ? undefined : marketplace?.overview ? marketplace.overview.newListingsLast7Days : null}
              neutral
            />
          </CardContent>
        </Card>
      </section>

      <section className="mt-4 grid gap-4 sm:grid-cols-2">
        <StatCard
          label="Anlık aktif kullanıcı" value="—" icon={Radio} tone="warning" unavailable
          badge="Servis yok"
          detail="Hiçbir serviste oturum/varlık takibi yok; sayının kaynağı olmadan kart doldurulamaz."
        />
        <StatCard
          label="Günlük işlem hacmi" value="—" icon={TrendingUp} tone="warning" unavailable
          badge="Servis yok"
          detail="Çip ya da cüzdan sistemi henüz yok. Bilet geliri, Etkinlikler ve Biletleme bitince buraya bağlanacak."
        />
      </section>

      <Card className="mt-4">
        <CardHeader>
          <div>
            <CardTitle>Bu konsolun uymak zorunda olduğu kurallar</CardTitle>
            <CardDescription>Tasarım değil, davranış: aşağıdakiler servis tarafında zorlanır.</CardDescription>
          </div>
        </CardHeader>
        <CardContent>
          <ul className="grid gap-2.5 text-sm text-ink-muted">
            {[
              'Gatework uygulama verilerini önbelleğe almaz.',
              'Yüksek riskli işlemler için step-up doğrulama zorunludur.',
              'Normal kullanıcı taklidi yerine resmî sistem hesapları kullanılır.',
              'Şikâyet edilen mesajlar yalnızca donmuş kanıt kopyası olarak görüntülenir; canlı özel konuşma okunamaz.',
              'Konum ekranları üyenin canlı konumunu değil, yalnızca kendi yayımladığı şehri toplulaştırır.',
            ].map((rule) => (
              <li key={rule} className="flex gap-2.5">
                <span className="mt-2 size-1.5 shrink-0 rounded-full bg-success" aria-hidden />
                {rule}
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>
    </>
  );
}

/**
 * `undefined` means the role may not see it, `null` means the service did not
 * answer, and a number means the service answered. Collapsing the first two
 * into "0" is exactly the failure this page exists to avoid.
 */
function PendingRow({ icon: Icon, label, value, href, neutral = false }: {
  icon: React.ComponentType<{ size?: number; className?: string }>;
  label: string;
  value: number | null | undefined;
  href: string;
  neutral?: boolean;
}) {
  const tone = value === undefined || value === null ? 'neutral' : neutral || value === 0 ? 'neutral' : 'warning';
  return (
    <a href={href} className="flex items-center justify-between gap-3 rounded-lg border border-hairline bg-surface-raised px-3.5 py-3 transition hover:border-brand-400/50">
      <span className="flex items-center gap-2.5 text-sm text-ink-muted">
        <Icon size={15} className="text-ink-faint" />
        {label}
      </span>
      <Badge tone={tone}>
        {value === undefined ? 'Gösterilmez' : value === null ? 'Ulaşılamadı' : value}
      </Badge>
    </a>
  );
}
