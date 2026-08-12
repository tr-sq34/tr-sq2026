-- Haber Merkezi: editorial articles the app reads, reacts to and comments on.
--
-- The app already had a news surface - the home screen's "Amerika'dan Mansetler"
-- block - but it was a hardcoded list inside `discover_screen.dart`: four
-- headlines that never changed, led nowhere and could not be corrected once a
-- build shipped. The drawer's "Haber Merkezi" is the same content read the long
-- way round, so both are served from this one table rather than from two.
--
-- Articles are written from the Gatework console, never by a member, which is
-- why there is no author-side workflow here: no drafts owned by members, no
-- report queue of their own. What members contribute is reactions and comments,
-- and those reuse the shapes the feed already established (005, 014) so that a
-- moderator sees one vocabulary and the app can reuse one comment editor.

CREATE TABLE IF NOT EXISTS news_articles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 3 AND 200),
  -- The one-paragraph version shown in the list and on the home screen. Kept as
  -- its own column instead of truncating the body: a headline block that cuts a
  -- sentence in half reads like a bug, and the editor is the one who should
  -- decide where the summary ends.
  summary TEXT NOT NULL CHECK (char_length(summary) BETWEEN 3 AND 500),
  body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 20000),
  -- Media id, not a URL. Same contract as posts and stories: the app is handed
  -- an id, the service resolves it through `media_assets` and only ever emits a
  -- scanned `safe_url`, so an article can never smuggle an unscanned image in.
  hero_media_id UUID REFERENCES media_assets(id),
  category TEXT NOT NULL CHECK (category IN (
    'gundem', 'gocmenlik', 'ekonomi', 'yasam', 'spor', 'kultur', 'topluluk'
  )),
  -- The system account the article is published as, plus a frozen copy of the
  -- name at publish time. The console can rename an account; a story published
  -- last month should keep the byline it went out with.
  author_id UUID NOT NULL,
  author_name TEXT NOT NULL CHECK (char_length(author_name) BETWEEN 2 AND 120),
  -- Optional state scope, for when a piece only matters in one place. NULL is
  -- "everyone", which is the normal case; the app filters on it rather than
  -- hiding nationwide news from anybody.
  region_code CHAR(2),
  -- NULL means it is written but not out yet, and a future timestamp means it
  -- is scheduled. Every read path asks for `published_at <= now()`, so there is
  -- one rule for both cases instead of a separate status column that can drift
  -- out of step with the date.
  published_at TIMESTAMPTZ,
  -- NULL keeps the article out of the home screen's headline strip. A small
  -- integer rather than a boolean because the strip is ordered, and "which of
  -- these four comes first" is an editorial decision, not an accident of
  -- publish time.
  headline_rank SMALLINT CHECK (headline_rank IS NULL OR headline_rank BETWEEN 1 AND 20),
  comments_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Soft delete, as everywhere else in this service: an unpublished article
  -- still has comments and reports pointing at it, and those have to keep
  -- resolving to something after a takedown.
  deleted_at TIMESTAMPTZ
);

-- The list endpoint is always "published, newest first", so the index carries
-- the filter and the ordering together and the pager never sorts the table.
CREATE INDEX IF NOT EXISTS news_articles_published_idx
  ON news_articles (published_at DESC, id DESC)
  WHERE deleted_at IS NULL AND published_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS news_articles_category_idx
  ON news_articles (category, published_at DESC, id DESC)
  WHERE deleted_at IS NULL AND published_at IS NOT NULL;

-- The home screen asks for a handful of rows and asks often; this is the whole
-- query it runs.
CREATE INDEX IF NOT EXISTS news_articles_headline_idx
  ON news_articles (headline_rank ASC, published_at DESC)
  WHERE deleted_at IS NULL AND published_at IS NOT NULL AND headline_rank IS NOT NULL;

-- One row per person per article, so a second tap is an update and not a second
-- vote. Switching from like to dislike is the same write as casting the first
-- one, and removing a reaction is a delete - the app never has to reason about
-- which of the two counters it is currently in.
CREATE TABLE IF NOT EXISTS news_reactions (
  article_id UUID NOT NULL REFERENCES news_articles(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  value TEXT NOT NULL CHECK (value IN ('like', 'dislike')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (article_id, user_id)
);

-- Both counters on the detail screen come from one grouped scan of this.
CREATE INDEX IF NOT EXISTS news_reactions_tally_idx
  ON news_reactions (article_id, value);

-- Deliberately the same columns and the same constraints as
-- `community_comments` (005): same body bounds, same `moderation_state`, same
-- soft delete. The app reuses the feed's comment editor here, and the report
-- queue in 014 already knows how to act on a row of this shape.
CREATE TABLE IF NOT EXISTS news_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id UUID NOT NULL REFERENCES news_articles(id) ON DELETE CASCADE,
  author_id UUID NOT NULL,
  parent_id UUID REFERENCES news_comments(id),
  body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 1000),
  moderation_state TEXT NOT NULL DEFAULT 'active' CHECK (moderation_state IN ('active', 'removed', 'pending_review')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS news_comments_page_idx
  ON news_comments (article_id, created_at DESC)
  WHERE deleted_at IS NULL AND moderation_state = 'active';

CREATE INDEX IF NOT EXISTS news_comments_author_idx
  ON news_comments (author_id, created_at DESC);
