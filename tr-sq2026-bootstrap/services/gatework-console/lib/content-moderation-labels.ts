/**
 * Browser-safe half of the feed moderation contract, split from
 * lib/content-moderation.ts for the same reason lib/moderation-labels.ts is
 * split from lib/moderation.ts: the client module reads the session cookie, and
 * importing it from a client component drags next/headers into the browser
 * bundle and breaks the build.
 *
 * Report categories and statuses are deliberately absent here - they are
 * identical to messaging's and are imported from moderation-labels, so a
 * category renamed in one queue cannot silently disagree with the other.
 */

export const CONTENT_TARGET_LABELS: Record<string, string> = {
  post: 'Paylaşım',
  comment: 'Yorum',
  story: 'Story',
};

export const CONTENT_STATE_LABELS: Record<string, string> = {
  active: 'Yayında',
  pending_review: 'İncelemede',
  removed: 'Kaldırıldı',
  deleted: 'Yazar silmiş',
  expired: 'Süresi doldu',
};

export const CONTENT_ACTION_LABELS: Record<string, string> = {
  claim: 'İncelemeye alındı',
  dismiss: 'Şikâyet reddedildi',
  remove_content: 'İçerik kaldırıldı',
  restrict_author: 'Yazar kısıtlandı',
  lift_restriction: 'Kısıtlama kaldırıldı',
};

export type ContentReportSummary = {
  id: string;
  source: 'content';
  targetType: 'post' | 'comment' | 'story';
  targetId: string;
  category: string;
  note: string | null;
  priority: 'urgent' | 'standard';
  status: 'open' | 'in_review' | 'actioned' | 'dismissed';
  dueAt: string;
  overdue: boolean;
  createdAt: string;
  reporterId: string;
  reporterName: string | null;
  reportedUserId: string;
  reportedUserName: string | null;
  activeRestriction: string | null;
  assignedTo: string | null;
  resolution: string | null;
  resolvedBy: string | null;
  resolvedAt: string | null;
};

/**
 * The frozen copy of the reported content. Shapes differ by target: a story has
 * no body text, a comment carries the post it hangs off. Optional fields rather
 * than a union because the reviewer's panel renders whatever is present, and a
 * report filed by an older client must not fail to open.
 */
export type ContentEvidence = {
  targetType?: string;
  body?: string;
  createdAt?: string;
  mediaIds?: string[];
  postId?: string;
  mediaId?: string;
  mediaKey?: string | null;
};

export type ContentReportDetail = ContentReportSummary & {
  evidence: ContentEvidence;
  // Whether the reported content is still standing. A reviewer should not have
  // to infer this from the evidence timestamp.
  targetState: string;
  authorHistory: { id: string; category: string; status: string; createdAt: string }[];
  actions: { action: string; reason: string; actorId: string; createdAt: string }[];
};

export type ContentOverview = {
  openReports: number;
  urgentReports: number;
  overdueReports: number;
  filedLast7Days: number;
  resolvedLast7Days: number;
  medianResolutionMinutes: number | null;
  activeRestrictions: number;
  slaHours: { urgent: number; standard: number };
};
