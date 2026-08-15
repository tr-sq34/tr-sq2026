/**
 * Browser-safe half of İçerik Stüdyosu and Haber Merkezi: row shapes and
 * Turkish labels, split from lib/content.ts for the same reason as the other
 * label modules - the screens are client components and the server module reads
 * the session cookie and mints delegation tokens.
 */

// An official account is what the platform publishes as. It cannot sign in;
// only Gatework writes on its behalf.
export type SystemAccount = {
  id: string;
  displayName: string | null;
  active: boolean;
  createdAt: string;
  newsCount: number;
  postCount: number;
};

// The console's view of an article. No body: this list decides which piece to
// act on, it is not where articles are read.
export type NewsSummary = {
  id: string;
  title: string;
  summary: string;
  category: string;
  authorId: string;
  authorName: string;
  regionCode: string | null;
  publishedAt: string;
  /** False while the publication time is still in the future. The public
      listing hides those rows entirely, so this is the only place a
      mis-dated article is visible before its date arrives. */
  live: boolean;
  headlineRank: number | null;
  commentsEnabled: boolean;
  imageUrl: string | null;
  commentCount: number;
  reactionCount: number;
};

// Yayında olan bir panel Story'si. Story 24 saatte kendiliğinden düştüğü için
// bu liste "yayınlananlar" değil "hâlâ yayında olanlar"; kalan süreyi gösteren
// başka bir ekran yok.
export type OfficialStory = {
  id: string;
  authorId: string;
  authorName: string;
  createdAt: string;
  expiresAt: string;
  imageUrl: string | null;
  viewCount: number;
  likeCount: number;
};

export const NEWS_CATEGORIES = [
  ['gundem', 'Gündem'],
  ['gocmenlik', 'Göçmenlik'],
  ['ekonomi', 'Ekonomi'],
  ['yasam', 'Yaşam'],
  ['spor', 'Spor'],
  ['kultur', 'Kültür'],
  ['topluluk', 'Topluluk'],
] as const;

export const NEWS_CATEGORY_LABELS: Record<string, string> = Object.fromEntries(NEWS_CATEGORIES);

export const VISIBILITY_LABELS: Record<string, string> = {
  public: 'Herkese açık',
  friends_only: 'Sadece arkadaşlar',
};
