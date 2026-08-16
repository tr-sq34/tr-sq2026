import type { GateworkRole } from './types';

/**
 * Browser-safe half of the Uyeler screen: row shapes and Turkish labels.
 *
 * Split from lib/members.ts for the same reason the moderation labels are split
 * from lib/content-moderation.ts - the screen is a client component, and the
 * server module reads the session cookie and mints delegation tokens. Importing
 * it from the browser bundle would either fail the build or ship code that has
 * no business being there.
 */

// Hesabin yasam dongusu. Uye kendi karariyla donduruyor ya da siliyor; panel
// bunu yalnizca goruyor, degistirmiyor. Silinmis bir hesap listede yine de
// duruyor cunku satiri duruyor - ama artik bir kisiyi gostermiyor ve ekranin
// bunu soylemesi gerekiyor.
export type AccountStatus = 'active' | 'frozen' | 'deletion_pending' | 'purged';

// Identity's view of the account: who they are and what they may do in Gatework.
export type IdentityMember = {
  id: string;
  email: string;
  displayName: string;
  emailVerified: boolean;
  createdAt: string;
  roles: GateworkRole[];
  accountStatus: AccountStatus;
  // Silme talebinin otuz gunu ne zaman doluyor. Yalnizca bekleyen hesapta dolu;
  // gecmis bir silme icin bu tarih artik bir sey ifade etmiyor.
  purgeAt: string | null;
  purgedAt: string | null;
};

// Community's view of the same person: what they have done and what has been
// decided about them. Deliberately a separate shape - one of the two services
// being down must leave the other half of the screen readable.
export type CommunityMember = {
  userId: string;
  displayName: string | null;
  city: string | null;
  regionCode: string | null;
  originCountry: string | null;
  identityVerified: boolean;
  auctionSellerEligible: boolean;
  activity: { posts: number; comments: number; forumTopics: number; forumReplies: number; listings: number };
  reports: { filedAgainst: number; upheld: number; open: number };
  restriction: { kind: string; reason: string; expiresAt: string | null } | null;
};

// Which buttons are worth drawing for this operator. Resolved on the server
// from the session roles; the services check the same rules again on every
// call, so this only decides what is offered, never what is allowed.
export type MemberPermissions = {
  manageRoles: boolean;
  revokeSessions: boolean;
  restrict: boolean;
  setCapabilities: boolean;
  seeAudit: boolean;
};

export const ROLE_LABELS: Record<GateworkRole, string> = {
  owner: 'Owner — tam yetki',
  security_admin: 'Güvenlik yöneticisi',
  operations_admin: 'Operasyon yöneticisi',
  content_editor: 'İçerik editörü',
  moderator: 'Moderatör',
  analyst: 'Analist',
  auditor: 'Denetçi',
};

// What each role is actually allowed to do, in one line, next to the checkbox
// that grants it. A role list without this is a list of words.
export const ROLE_HINTS: Record<GateworkRole, string> = {
  owner: 'Rol verir ve geri alır; her şeye erişir.',
  security_admin: 'Oturum iptali, şikâyet kararları, kısıtlamalar.',
  operations_admin: 'Kategoriler, tanıtımlar, üye yetkileri.',
  content_editor: 'Haber ve resmî paylaşım yayınlar.',
  moderator: 'Şikâyet kuyruğunu işler, içerik kaldırır.',
  analyst: 'Yalnızca toplulaştırılmış metrikleri görür.',
  auditor: 'Yalnızca okur; denetim kayıtlarına erişir.',
};

// Hesap durumunun karsiligi. "Kapali" demek yetmiyor: donduran uye geri
// donebilir, silinmeyi bekleyen uye giris yaparsa talebi iptal olur, silinmis
// olan icin yapilacak bir sey kalmamistir.
export const ACCOUNT_STATUS_LABELS: Record<AccountStatus, string> = {
  active: 'Etkin',
  frozen: 'Dondurulmuş — giriş yaparsa geri açılır',
  deletion_pending: 'Silinmeyi bekliyor',
  purged: 'Kimliği silindi',
};

export const RESTRICTION_LABELS: Record<string, string> = {
  muted: 'Susturulmuş — okuyabilir, paylaşamaz',
  suspended: 'Askıya alınmış',
};
