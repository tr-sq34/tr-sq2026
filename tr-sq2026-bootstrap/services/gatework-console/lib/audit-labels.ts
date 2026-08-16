/**
 * Browser-safe half of the Sistem ve Denetim screen.
 *
 * Split from lib/audit.ts for the same reason as the other label modules: the
 * screen is a client component and the server module reads the session cookie.
 */

// One row shape for three services. `service` is which log it came from and
// `stream` is which log inside that service - Community keeps operator commands
// and moderation decisions apart, and flattening that distinction here would
// make "removed a post" and "opened a category" look like the same kind of act.
export type AuditRow = {
  id: string;
  service: 'identity' | 'community' | 'messaging';
  stream: string;
  actorId: string;
  actorName: string | null;
  actorEmail: string | null;
  actorRoles: string[];
  action: string;
  targetType: string;
  targetId: string;
  reason: string | null;
  outcome: string;
  createdAt: string;
};

export const SERVICE_LABELS: Record<AuditRow['service'], string> = {
  identity: 'Kimlik',
  community: 'Topluluk',
  messaging: 'Mesajlaşma',
};

export const OUTCOME_LABELS: Record<string, string> = {
  succeeded: 'Uygulandı',
  denied: 'Reddedildi',
  failed: 'Başarısız',
};

// The action is stored as a machine key so it stays stable across releases;
// this is the only place it becomes a sentence. An unknown key falls back to
// the key itself rather than to a blank, so a newly added action is readable
// the day it ships instead of the day someone remembers to add it here.
export const ACTION_LABELS: Record<string, string> = {
  'members.list': 'Üye listesini görüntüledi',
  'member.sessions.list': 'Üyenin açık oturumlarını görüntüledi',
  'member.sessions.revoke': 'Oturumları sonlandırdı',
  'role.grant': 'Rol verdi',
  'role.revoke': 'Rolü geri aldı',
  'delegation.mint': 'Yetki jetonu aldı',
  'system_principal.create': 'Sistem hesabı açtı',
  'system_account.activate': 'Sistem hesabını etkinleştirdi',
  claim: 'Şikâyeti üstlendi',
  dismiss: 'Şikâyeti reddetti',
  remove_content: 'İçeriği kaldırdı',
  message_removed: 'Mesajı kaldırdı',
  restrict_author: 'Üyeyi kısıtladı',
  removed_from_group: 'Gruptan çıkardı',
  group_removed: 'Grubu kapattı',
  lift_restriction: 'Kısıtlamayı kaldırdı',
  restriction_lifted: 'Kısıtlamayı kaldırdı',
  'content_restriction.lift': 'Kısıtlamayı kaldırdı',
  'member.restrict': 'Üyeyi kısıtladı',
  'member.capability.grant': 'Üyeye yetki verdi',
  'member.capability.revoke': 'Üye yetkisini geri aldı',
  'forum_category.create': 'Forum kategorisi açtı',
  'forum_category.update': 'Forum kategorisini güncelledi',
  'forum_category.deactivate': 'Forum kategorisini kapattı',
  'forum_topic.state': 'Forum konusunu düzenledi',
  'sos.acknowledge': 'Yardım çağrısını üstlendi',
  'sos.location_access': 'SOS konumunu görmek için yetki aldı',
  'sos.close': 'Yardım çağrısını kapattı',
  'marketplace_listing.status': 'İlan durumunu değiştirdi',
  'marketplace_auction.cancel': 'İhaleyi iptal etti',
  'news_article.publish': 'Haber yayınladı',
  'news_article.retract': 'Haberi geri çekti',
  'official_post.publish': 'Resmî paylaşım yaptı',
  'promotion.place': 'Tanıtım yerleştirdi',
  'event.draft': 'Etkinlik taslağı yazdı',
  'event.publish': 'Etkinlik yayınladı',
  'event.cancel': 'Etkinliği iptal etti',
};

export const actionLabel = (action: string) => ACTION_LABELS[action] ?? action;
// A row is about somebody, and the id is the only field guaranteed to be there.
// Name first, then email, then a short id - long enough to tell two operators
// apart, short enough not to take the width of the column.
export const actorLabel = (row: AuditRow) => row.actorName ?? row.actorEmail ?? `${row.actorId.slice(0, 8)}…`;
