/**
 * Browser-safe half of the Doğrulama screen.
 *
 * Split from lib/verification.ts like every other label module here: the screen
 * is a client component and the server module reads the session cookie.
 */

// Everything this screen can know about a verification. There is no document
// field, no name-off-the-ID field and no Stripe detail field, because the vault
// stores none of them - it keeps the status and the timestamps and nothing else.
export type VerificationSession = {
  id: string;
  userId: string;
  memberName: string | null;
  memberEmail: string | null;
  status: string;
  policyVersion: string;
  createdAt: string;
  updatedAt: string;
  expiresAt: string | null;
  redactedAt: string | null;
};

export type VerificationOverview = {
  counts: Record<string, number>;
  total: number;
  outbox: { pending: number; oldestPendingAt: string | null; queueConfigured: boolean };
};

export const VERIFICATION_STATUS_LABELS: Record<string, string> = {
  created: 'Başlatıldı',
  requires_input: 'Eksik bilgi',
  verified: 'Onaylandı',
  canceled: 'İptal edildi',
  redacted: 'Silindi',
};

// What each status means for the member, in the member's terms. "requires_input"
// is the one that matters: it is not a failure, it is a flow the member can
// finish, and an operator who reads it as rejected answers the wrong question.
export const VERIFICATION_STATUS_HINTS: Record<string, string> = {
  created: 'Akış açıldı, üye henüz tamamlamadı.',
  requires_input: 'Stripe ek belge veya yeni çekim istedi; üye kaldığı yerden devam edebilir.',
  verified: 'Onaylandı; Onaylı Hesap rozeti ve ihale yetkisi bu kayda bağlı.',
  canceled: 'Üye vazgeçti ya da oturum düştü; yeniden başlatılabilir.',
  redacted: 'Stripe tarafındaki veri silindi; kayıt yalnızca iz olarak duruyor.',
};
