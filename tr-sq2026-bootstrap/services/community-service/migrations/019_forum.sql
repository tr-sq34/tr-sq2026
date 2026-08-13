-- Forum: categories, topics, replies and reactions.
--
-- The drawer had a "Forum" entry carrying a "yakinda" tag that led nowhere, and
-- the home screen showed a hardcoded "Forumda trend tartismalar" card - a title,
-- a reply count and a "Son yanit: Burak K. (8 dk once)" line that were literal
-- strings in `discover_screen.dart`. This is the data behind both.
--
-- Separate tables from the feed rather than a `kind` column on community_posts,
-- because the two have different lifetimes and different rules. The feed is
-- today's conversation: it scrolls past, it is deletable, it has no title. The
-- forum is an archive meant to be found by search a year later, so it has a
-- title, a category, a pin, a lock and an accepted answer - none of which the
-- feed wants, and all of which would sit NULL on every feed row.

CREATE TABLE IF NOT EXISTS forum_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- The stable name. Titles get edited from the console; a URL and a saved
  -- filter should not break when someone fixes a typo.
  slug TEXT NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9-]{2,48}$'),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 2 AND 80),
  -- The icon travels with the row rather than living in a client-side lookup
  -- table: a category opened from the console has to be able to show up in the
  -- app without shipping a new build.
  emoji TEXT NOT NULL DEFAULT '💬' CHECK (char_length(emoji) BETWEEN 1 AND 8),
  description TEXT NOT NULL DEFAULT '' CHECK (char_length(description) <= 240),
  ordinal INT NOT NULL DEFAULT 0,
  -- Deactivated, not deleted. A closed category still owns the topics written in
  -- it, and those have to stay readable.
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS forum_categories_order_idx
  ON forum_categories (ordinal, title)
  WHERE is_active;

CREATE TABLE IF NOT EXISTS forum_topics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- RESTRICT, not CASCADE: deleting a category must not take a year of answers
  -- with it. Emptying one is a deliberate operation, not a side effect.
  category_id UUID NOT NULL REFERENCES forum_categories(id) ON DELETE RESTRICT,
  author_id UUID NOT NULL,
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 8 AND 160),
  body TEXT NOT NULL CHECK (char_length(body) BETWEEN 20 AND 8000),
  -- Derivable from forum_replies, kept here anyway. Both default orderings -
  -- "son hareket" and "en cok yanit" - sort by these, and recomputing them per
  -- request means counting every reply in the forum to draw one page. They are
  -- written in the same transaction as the reply, so they cannot drift.
  reply_count INT NOT NULL DEFAULT 0 CHECK (reply_count >= 0),
  view_count BIGINT NOT NULL DEFAULT 0 CHECK (view_count >= 0),
  is_pinned BOOLEAN NOT NULL DEFAULT false,
  -- Locked is not hidden: a settled thread keeps being read, it just stops
  -- taking replies. That is what the rules topic is for.
  is_locked BOOLEAN NOT NULL DEFAULT false,
  -- Same vocabulary the feed uses, so one moderation decision path covers both.
  moderation_state TEXT NOT NULL DEFAULT 'active' CHECK (moderation_state IN ('active', 'hidden', 'removed')),
  last_reply_at TIMESTAMPTZ,
  last_reply_author_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

-- The list's default order, carried by the index instead of sorted per request:
-- pinned first, then most recent activity.
CREATE INDEX IF NOT EXISTS forum_topics_activity_idx
  ON forum_topics (is_pinned DESC, COALESCE(last_reply_at, created_at) DESC, id DESC)
  WHERE deleted_at IS NULL AND moderation_state = 'active';

CREATE INDEX IF NOT EXISTS forum_topics_category_idx
  ON forum_topics (category_id, COALESCE(last_reply_at, created_at) DESC, id DESC)
  WHERE deleted_at IS NULL AND moderation_state = 'active';

CREATE INDEX IF NOT EXISTS forum_topics_replies_idx
  ON forum_topics (reply_count DESC, id DESC)
  WHERE deleted_at IS NULL AND moderation_state = 'active';

CREATE INDEX IF NOT EXISTS forum_topics_author_idx
  ON forum_topics (author_id, created_at DESC);

CREATE TABLE IF NOT EXISTS forum_replies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id UUID NOT NULL REFERENCES forum_topics(id) ON DELETE CASCADE,
  author_id UUID NOT NULL,
  body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 4000),
  is_accepted_answer BOOLEAN NOT NULL DEFAULT false,
  moderation_state TEXT NOT NULL DEFAULT 'active' CHECK (moderation_state IN ('active', 'hidden', 'removed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

-- Oldest first: a thread is read top to bottom, unlike the feed.
CREATE INDEX IF NOT EXISTS forum_replies_topic_idx
  ON forum_replies (topic_id, created_at, id)
  WHERE deleted_at IS NULL AND moderation_state = 'active';

-- A question has one answer marked as the one that worked. Enforced here rather
-- than in the service, because two concurrent accepts would otherwise both win.
CREATE UNIQUE INDEX IF NOT EXISTS forum_replies_accepted_idx
  ON forum_replies (topic_id)
  WHERE is_accepted_answer AND deleted_at IS NULL;

-- One table for both targets. Two would mean writing the same count query twice
-- and keeping two copies of it correct.
CREATE TABLE IF NOT EXISTS forum_reactions (
  target_type TEXT NOT NULL CHECK (target_type IN ('topic', 'reply')),
  target_id UUID NOT NULL,
  actor_id UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- The primary key is the idempotency: liking twice is one row, so a retried
  -- request cannot inflate a counter.
  PRIMARY KEY (target_type, target_id, actor_id)
);

CREATE INDEX IF NOT EXISTS forum_reactions_target_idx
  ON forum_reactions (target_type, target_id);

-- The read counter is not a tap counter: reopening a topic does not make it look
-- more read than it is. The number itself lives on forum_topics.view_count; this
-- table only answers "has this member opened this before".
CREATE TABLE IF NOT EXISTS forum_topic_views (
  topic_id UUID NOT NULL REFERENCES forum_topics(id) ON DELETE CASCADE,
  viewer_id UUID NOT NULL,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (topic_id, viewer_id)
);

-- Forum content reaches the queue that already exists (migration 014) instead of
-- getting one of its own: a moderator should see a reported topic in the same
-- list as a reported post, with the same categories and the same SLA clock.
ALTER TABLE content_reports DROP CONSTRAINT IF EXISTS content_reports_target_type_check;
ALTER TABLE content_reports ADD CONSTRAINT content_reports_target_type_check
  CHECK (target_type IN ('post', 'comment', 'story', 'forum_topic', 'forum_reply'));

ALTER TABLE content_moderation_actions DROP CONSTRAINT IF EXISTS content_moderation_actions_target_type_check;
ALTER TABLE content_moderation_actions ADD CONSTRAINT content_moderation_actions_target_type_check
  CHECK (target_type IN ('report', 'post', 'comment', 'story', 'forum_topic', 'forum_reply', 'user'));

-- The five categories the app ships with. Seeded rather than left to the console
-- so a fresh environment has a forum with somewhere to write on first boot.
INSERT INTO forum_categories (slug, title, emoji, description, ordinal) VALUES
  ('vize-gocmenlik', 'Vize & Göçmenlik', '🎓', 'Vize türleri, yeşil kart, vatandaşlık ve randevular', 1),
  ('emlak-yasam', 'Emlak & Yaşam', '🏠', 'Kiralama, ev alma, mahalleler ve taşınma', 2),
  ('is-kurma-yatirim', 'İş Kurma & Yatırım', '💼', 'Şirket kurma, vergi, işletme devri ve yatırım', 3),
  ('egitim-okul', 'Eğitim & Okul', '📚', 'Okul kayıtları, üniversite ve çocuklar için Türkçe', 4),
  ('gunluk-hayat', 'Günlük Hayat', '🛒', 'Ehliyet, sağlık, alışveriş ve şehirdeki pratik bilgiler', 5)
ON CONFLICT (slug) DO NOTHING;
