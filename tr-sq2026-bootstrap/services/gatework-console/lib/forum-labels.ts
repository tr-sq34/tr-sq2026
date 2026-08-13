/**
 * Browser-safe half of the Forum screen: row shapes and Turkish labels.
 * Split from lib/forum.ts for the same reason as the member labels - the screen
 * is a client component and the server module reads the session cookie.
 */

export type ForumCategory = {
  id: string;
  slug: string;
  title: string;
  emoji: string;
  description: string;
  ordinal: number;
  isActive: boolean;
  topicCount: number;
  replyCount: number;
  lastActivityAt: string | null;
};

export type ForumTopicRow = {
  id: string;
  title: string;
  categoryTitle: string;
  authorId: string;
  authorName: string | null;
  replyCount: number;
  viewCount: number;
  isPinned: boolean;
  isLocked: boolean;
  moderationState: string;
  createdAt: string;
  lastActivityAt: string;
};

export const FORUM_STATE_LABELS: Record<string, string> = {
  active: 'Yayında',
  hidden: 'Gizlenmiş',
  removed: 'Kaldırılmış',
};
