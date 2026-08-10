-- The profile becomes a real object instead of a mock.
--
-- Until now `community_profile_projection` carried a name, a city and a list of
-- interests, and the app filled everything else in from `MockProfileRepository`:
-- a hardcoded "Ahmet Yilmaz", a hardcoded origin city, invented badges and two
-- invented favourite restaurants. The member's arrival date and country of
-- origin were already collected during onboarding, but they lived in
-- IDENTITY_DATABASE and the outbox payload never carried them, so Community had
-- no way to show them.
--
-- Two kinds of data with two different owners, hence two tables:
--   * the projection stays a read model of what Identity knows (name, locality,
--     onboarding answers) and is only ever written by the projection worker;
--   * `member_profiles` holds what the member types into Community itself (bio,
--     avatar, visibility, showcased badges) and is written by the member.
-- Copying the onboarding answers into `member_profiles` would have created two
-- sources of truth for the same fact, so the projection is widened instead.

ALTER TABLE community_profile_projection
  ADD COLUMN IF NOT EXISTS born_in_us     BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS arrived_month  SMALLINT,
  ADD COLUMN IF NOT EXISTS arrived_year   SMALLINT,
  ADD COLUMN IF NOT EXISTS origin_country CHAR(2),
  ADD COLUMN IF NOT EXISTS origin_city    TEXT,
  ADD COLUMN IF NOT EXISTS primary_intent TEXT;

-- Same bounds identity enforces (auth-service migration 012), restated here
-- because a projection that trusts its producer to have validated is a
-- projection that silently stores 1823 as an arrival year the first time an
-- event is replayed from a bad payload.
ALTER TABLE community_profile_projection
  DROP CONSTRAINT IF EXISTS community_profile_projection_arrived_month_check;
ALTER TABLE community_profile_projection
  ADD CONSTRAINT community_profile_projection_arrived_month_check
  CHECK (arrived_month IS NULL OR arrived_month BETWEEN 1 AND 12);

ALTER TABLE community_profile_projection
  DROP CONSTRAINT IF EXISTS community_profile_projection_arrived_year_check;
ALTER TABLE community_profile_projection
  ADD CONSTRAINT community_profile_projection_arrived_year_check
  CHECK (arrived_year IS NULL OR arrived_year BETWEEN 1950 AND 2100);

ALTER TABLE community_profile_projection
  DROP CONSTRAINT IF EXISTS community_profile_projection_origin_city_check;
ALTER TABLE community_profile_projection
  ADD CONSTRAINT community_profile_projection_origin_city_check
  CHECK (origin_city IS NULL OR char_length(origin_city) BETWEEN 2 AND 100);

-- What the member writes about themselves. One row per member, created lazily
-- on the first PATCH: a member who never opens the editor should not need a row
-- to have a profile.
CREATE TABLE IF NOT EXISTS member_profiles (
  user_id UUID PRIMARY KEY,
  bio TEXT CHECK (bio IS NULL OR char_length(bio) <= 280),
  -- The avatar goes through the existing quarantine -> scan -> ready media
  -- pipeline like every other image. Referencing media_assets rather than
  -- storing a URL means an avatar can never point at an unscanned blob, and the
  -- read SAS is minted per request as it is everywhere else.
  avatar_media_id UUID REFERENCES media_assets(id) ON DELETE SET NULL,
  -- Defaults closed. A member who has not chosen yet is not implicitly
  -- publishing their friend list to the whole app.
  visibility TEXT NOT NULL DEFAULT 'friends_only'
    CHECK (visibility IN ('public', 'friends_only')),
  -- At most three, enforced here so a client bug cannot turn the showcase into
  -- an unbounded array. Codes are validated against badge_definitions in 016.
  showcased_badges TEXT[] NOT NULL DEFAULT '{}'
    CHECK (array_length(showcased_badges, 1) IS NULL OR array_length(showcased_badges, 1) <= 3),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Archiving is not deleting. The member's grid hides the post and the feed stops
-- serving it, but the row, its comments and its reactions stay exactly where
-- they were so un-archiving is a single UPDATE and a moderation report filed
-- against the post still resolves.
ALTER TABLE community_posts
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;

-- The partial indexes from 001 and 008 exclude deleted and removed rows; an
-- archived post has to leave the feed through the same door, so the predicate
-- is repeated in a fresh index rather than the old ones being redefined (they
-- are still correct, just less selective than they could be).
CREATE INDEX IF NOT EXISTS community_posts_visible_idx
  ON community_posts (created_at DESC, id DESC)
  WHERE deleted_at IS NULL AND archived_at IS NULL AND moderation_state = 'active';

-- The profile grid asks "this author's posts, newest first, active or archived",
-- which is a different question from anything the feed asks.
CREATE INDEX IF NOT EXISTS community_posts_author_idx
  ON community_posts (author_id, created_at DESC, id DESC)
  WHERE deleted_at IS NULL;
