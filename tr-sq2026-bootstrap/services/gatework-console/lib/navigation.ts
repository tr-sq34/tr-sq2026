import { canSeeAnalytics } from './analytics';
import { canSeeAudit } from './audit';
import { canSeeEvents } from './events';
import { canSeeForum } from './forum';
import { canSeeServiceHealth } from './health';
import { canSeeMarketplace } from './marketplace';
import { canSeeMembers } from './members';
import { canReviewReports } from './moderation';
import { canSeeSafety } from './safety';
import { canSeeVerification } from './verification';
import type { GateworkRole } from './types';

/**
 * The sidebar, grouped.
 *
 * Two problems with the flat list this replaces. The first is length: fourteen
 * equally-weighted entries in one column, so "Güvenlik ve SOS" - the one with a
 * person waiting at the other end - sat between "Mesajlar" and "Analitik" with
 * nothing to say it mattered more. The second is that it showed every entry to
 * everybody: an analyst clicked "Moderasyon" and got a page explaining that
 * their role may not see moderation data. The gate already existed on the page
 * and on the API; it just was not reflected in the menu.
 *
 * Visibility is computed here, on the server, using the same `canSee*` helpers
 * the pages enforce with - not a second copy of the role lists that would drift
 * from them. The sidebar itself is a client component and receives only the
 * resolved labels and hrefs.
 *
 * İçerik Stüdyosu, Haber Merkezi and Tanıtımlar carry no gate because the
 * console has none for them: the community service decides per role what a
 * delegation token may write. Hiding them here would invent a restriction that
 * does not exist.
 */
export type NavItem = {
  /** Stable key; the sidebar maps it to an icon so no component crosses the
      server/client boundary. */
  key: string;
  label: string;
  href: string;
  /** Shown as a pill next to the label. Used only for modules that are
      genuinely unfinished, never as decoration. */
  note?: string;
};

export type NavGroup = { key: string; label: string; items: NavItem[] };

export function navigationFor(roles: GateworkRole[]): NavGroup[] {
  const groups: NavGroup[] = [
    {
      key: 'overview',
      label: 'Sistem ve Genel Bakış',
      items: [
        { key: 'command-center', label: 'Komuta Merkezi', href: '/command-center' },
        // Aynı ad sayfanın başlığında da yazıyor: menüde bir şey arayan kişi,
        // bakımla ilgili her şeyin tek yerde olduğunu adından anlamalı.
        canSeeServiceHealth(roles) ? { key: 'health', label: 'Sistem Sağlığı ve Bakım', href: '/health' } : null,
        canSeeAnalytics(roles) ? { key: 'analytics', label: 'Analitik ve Konum', href: '/analytics' } : null,
        canSeeAudit(roles) ? { key: 'system', label: 'Sistem ve Denetim', href: '/system' } : null,
      ].filter(Boolean) as NavItem[],
    },
    {
      key: 'content',
      label: 'Topluluk ve İçerik',
      items: [
        { key: 'content', label: 'İçerik Stüdyosu', href: '/content' },
        { key: 'news', label: 'Haber Merkezi', href: '/news' },
        canSeeForum(roles) ? { key: 'forum', label: 'Forum', href: '/forum' } : null,
        canSeeEvents(roles)
          ? { key: 'events', label: 'Etkinlikler ve Biletleme', href: '/events', note: 'Yapım aşamasında' }
          : null,
      ].filter(Boolean) as NavItem[],
    },
    {
      key: 'commerce',
      label: 'Kullanıcılar ve Ticaret',
      items: [
        canSeeMembers(roles) ? { key: 'members', label: 'Üyeler', href: '/members' } : null,
        canSeeMarketplace(roles) ? { key: 'marketplace', label: 'Çarşı ve İhaleler', href: '/marketplace' } : null,
        { key: 'promotions', label: 'Tanıtımlar', href: '/promotions' },
        canSeeVerification(roles) ? { key: 'verification', label: 'Doğrulama ve KYC', href: '/verification' } : null,
      ].filter(Boolean) as NavItem[],
    },
    {
      key: 'safety',
      label: 'Güvenlik ve Destek',
      items: [
        canReviewReports(roles) ? { key: 'moderation', label: 'Moderasyon Merkezi', href: '/moderation' } : null,
        canReviewReports(roles) ? { key: 'communications', label: 'Mesajlar ve Gruplar', href: '/communications' } : null,
        canSeeSafety(roles) ? { key: 'safety', label: 'Güvenlik ve SOS', href: '/safety' } : null,
      ].filter(Boolean) as NavItem[],
    },
  ];

  // A heading with nothing under it tells the operator a section exists that
  // they cannot reach, which is worse than not naming it at all.
  return groups.filter((group) => group.items.length > 0);
}

export const ROLE_LABELS: Record<GateworkRole, string> = {
  owner: 'Sahip',
  security_admin: 'Güvenlik Yöneticisi',
  operations_admin: 'Operasyon Yöneticisi',
  content_editor: 'İçerik Editörü',
  moderator: 'Moderatör',
  analyst: 'Analist',
  auditor: 'Denetçi',
};
