/**
 * The half of the moderation contract that is safe in the browser: types and
 * the Turkish labels for the codes the gateway stores.
 *
 * Kept apart from lib/moderation.ts because that module reads the session
 * cookie, and importing it from a client component pulls next/headers into the
 * browser bundle and fails the build. Splitting the file is what lets the queue
 * and the operations table share one vocabulary with the server.
 */

export const REPORT_CATEGORY_LABELS: Record<string, string> = {
  child_safety: 'Çocuk güvenliği',
  self_harm: 'Kendine zarar',
  violence_threat: 'Şiddet / tehdit',
  hate_speech: 'Nefret söylemi',
  harassment: 'Taciz',
  sexual_content: 'Cinsel içerik',
  scam_fraud: 'Dolandırıcılık',
  illegal_goods: 'Yasa dışı ürün',
  spam: 'Spam',
  other: 'Diğer',
};

export const REPORT_STATUS_LABELS: Record<string, string> = {
  open: 'Açık',
  in_review: 'İncelemede',
  actioned: 'İşlem yapıldı',
  dismissed: 'Reddedildi',
};

export const MODERATION_ACTION_LABELS: Record<string, string> = {
  message_removed: 'Mesaj kaldırıldı',
  user_muted: 'Kullanıcı susturuldu',
  user_suspended: 'Kullanıcı askıya alındı',
  removed_from_group: 'Gruptan çıkarıldı',
  restriction_lifted: 'Kısıtlama kaldırıldı',
  group_removed: 'Grup kapatıldı',
  report_actioned: 'Şikâyet sonuçlandırıldı',
  report_dismissed: 'Şikâyet reddedildi',
};

export type ReportSummary = {
  id: string;
  scope: 'direct' | 'group';
  category: string;
  priority: 'urgent' | 'standard';
  status: 'open' | 'in_review' | 'actioned' | 'dismissed';
  note: string | null;
  createdAt: string;
  dueAt: string;
  overdue: boolean;
  reporterId: string;
  reporterName: string | null;
  reportedUserId: string | null;
  reportedUserName: string | null;
  groupId: string | null;
  groupName: string | null;
  conversationId: string | null;
  messageEventId: string | null;
  assignedTo: string | null;
  resolution: string | null;
  resolvedBy: string | null;
  resolvedAt: string | null;
};

export type EvidenceMessage = { eventId: string; senderId: string | null; body: string; sentAt: string };

export type ReportDetail = ReportSummary & {
  evidence: { capturedAt?: string; kind?: string; unavailable?: boolean; reported?: EvidenceMessage | null; before?: EvidenceMessage[]; after?: EvidenceMessage[] };
  priorReports: { id: string; category: string; status: string; createdAt: string }[];
  actions: { action: string; reason: string; actorId: string; createdAt: string }[];
  activeRestriction: { restriction: string; reason: string; expiresAt: string | null } | null;
};

export type ModerationOverview = {
  openReports: number;
  urgentReports: number;
  overdueReports: number;
  resolvedLast7Days: number;
  filedLast7Days: number;
  medianResolutionMinutes: number | null;
  activeRestrictions: number;
  slaHours: { urgent: number; standard: number };
};

export type RestrictionRow = {
  userId: string;
  displayName: string | null;
  restriction: 'muted' | 'suspended';
  reason: string;
  expiresAt: string | null;
  createdBy: string;
  createdAt: string;
};

export type ModeratedGroup = {
  id: string;
  name: string;
  city: string;
  privacy: 'public' | 'private';
  memberCount: number;
  openReports: number;
  ownerId: string;
  ownerName: string | null;
  createdAt: string;
  lastMessageAt: string;
  removedAt: string | null;
  removedReason: string | null;
};

export type AuditRow = {
  id: string;
  reportId: string | null;
  actorId: string;
  actorRoles: string[];
  action: string;
  targetType: string;
  targetId: string;
  reason: string;
  createdAt: string;
};
