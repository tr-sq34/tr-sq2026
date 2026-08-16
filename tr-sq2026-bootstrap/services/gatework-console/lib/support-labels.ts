/**
 * Browser-safe half of the Destek Talepleri screen.
 *
 * Split from lib/support.ts for the same reason as the other label modules: the
 * desk is a client component and the server module reads the session cookie and
 * mints a delegation token.
 */

export type SupportStatus = 'open' | 'answered' | 'closed';
export type SupportTopic = 'account' | 'safety' | 'marketplace' | 'content' | 'technical' | 'other';

export type SupportRequest = {
  id: string;
  memberId: string;
  memberName: string | null;
  topic: string;
  subject: string;
  status: SupportStatus;
  appVersion: string | null;
  platform: string | null;
  createdAt: string;
  updatedAt: string;
  /** Üyenin en son yazdığı an. Kuyruğun sırası buradan çıkıyor. */
  lastMemberAt: string;
  lastStaffAt: string | null;
  closedAt: string | null;
  closureReason: string | null;
  lastMessage: string | null;
  messageCount: number;
};

export type SupportMessage = {
  id: string;
  authorKind: 'member' | 'staff';
  authorId: string;
  authorRoles: string[];
  body: string;
  createdAt: string;
};

export type SupportThread = Omit<SupportRequest, 'lastMessage' | 'messageCount'> & { messages: SupportMessage[] };

export const SUPPORT_TOPIC_LABELS: Record<string, string> = {
  account: 'Hesap ve giriş',
  safety: 'Güvenlik ve taciz',
  marketplace: 'Çarşı ve ödeme',
  content: 'İçerik ve moderasyon',
  technical: 'Teknik sorun',
  other: 'Diğer',
};

// Durum adlari, sirada kimin oldugunu soyluyor. "Acik / kapali" ikilisi bunu
// gizliyordu: cevaplanmis ama kapanmamis bir talep de "acik" gorunurdu ve
// operator ayni talebi ikinci kez cevaplardi.
export const SUPPORT_STATUS_LABELS: Record<SupportStatus, string> = {
  open: 'Yanıt bekliyor',
  answered: 'Yanıtlandı — üyede',
  closed: 'Kapandı',
};

export const SUPPORT_STATUS_TONE: Record<SupportStatus, 'danger' | 'warning' | 'success' | 'neutral'> = {
  open: 'warning',
  answered: 'neutral',
  closed: 'success',
};

export const supportMemberLabel = (request: { memberName: string | null; memberId: string }) =>
  request.memberName ?? `${request.memberId.slice(0, 8)}…`;

export const supportTime = (value: string) => new Date(value).toLocaleString('tr-TR', { dateStyle: 'short', timeStyle: 'short' });

/**
 * Ne kadardır cevap beklediği. Bu ekranda kimse bakmazken kötüleşen tek sayı;
 * bu yüzden listede de, üstteki kutuda da o duruyor.
 */
export function waitingFor(iso: string, now: number) {
  const minutes = Math.max(0, Math.round((now - new Date(iso).getTime()) / 60000));
  if (minutes < 60) return `${minutes} dk`;
  const hours = Math.floor(minutes / 60);
  return hours < 24 ? `${hours} sa` : `${Math.floor(hours / 24)} gün`;
}

// Uygulamanin surumu ve platformu, teknik bir sikayette ilk sorulacak sey.
// Gelmediyse "bilinmiyor" yaziyoruz: bos birakmak, sorunun sorulmadigi
// izlenimi birakiyor.
export function clientLabel(request: { platform: string | null; appVersion: string | null }) {
  const platform = request.platform === 'android' ? 'Android' : request.platform === 'ios' ? 'iOS' : request.platform === 'web' ? 'Web' : null;
  if (!platform && !request.appVersion) return 'Uygulama bilgisi gelmedi';
  return [platform ?? 'Platform bilinmiyor', request.appVersion ?? 'sürüm bilinmiyor'].join(' · ');
}
