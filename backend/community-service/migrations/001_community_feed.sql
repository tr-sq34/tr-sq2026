-- COMMUNITY_DATABASE only. Identity data lives in IDENTITY_DATABASE; the
-- service receives user UUIDs from verified access tokens and never stores
-- password hashes, refresh tokens, passkeys, or identity documents.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TYPE post_visibility AS ENUM ('public', 'friends_only');
CREATE TYPE post_kind AS ENUM ('standard', 'poll', 'marketplace_listing');

CREATE TABLE community_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id UUID NOT NULL,
  kind post_kind NOT NULL DEFAULT 'standard',
  visibility post_visibility NOT NULL DEFAULT 'public',
  body TEXT NOT NULL CHECK (char_length(body) <= 5000),
  location_cell geography(Point, 4326),
  location_label TEXT CHECK (char_length(location_label) <= 120),
  comments_enabled BOOLEAN NOT NULL DEFAULT true,
  moderation_state TEXT NOT NULL DEFAULT 'active'
    CHECK (moderation_state IN ('active', 'pending_review', 'removed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE INDEX community_posts_created_idx ON community_posts(created_at DESC)
  WHERE deleted_at IS NULL AND moderation_state = 'active';
CREATE INDEX community_posts_location_idx ON community_posts USING GIST(location_cell)
  WHERE deleted_at IS NULL AND moderation_state = 'active';

-- Object keys refer to the media service's private bucket. No binary media,
-- EXIF, original filename, or presigned upload URL is stored here.
CREATE TABLE post_media_refs (
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  media_id UUID NOT NULL,
  ordinal SMALLINT NOT NULL CHECK (ordinal BETWEEN 0 AND 9),
  PRIMARY KEY (post_id, media_id),
  UNIQUE (post_id, ordinal)
);

CREATE TABLE post_reactions (
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  actor_id UUID NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('like', 'save')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, actor_id, kind)
);

CREATE TABLE post_polls (
  post_id UUID PRIMARY KEY REFERENCES community_posts(id) ON DELETE CASCADE,
  selection_mode TEXT NOT NULL CHECK (selection_mode IN ('single', 'multiple')),
  closes_at TIMESTAMPTZ
);
CREATE TABLE post_poll_options (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES post_polls(post_id) ON DELETE CASCADE,
  ordinal SMALLINT NOT NULL CHECK (ordinal BETWEEN 0 AND 3),
  label TEXT NOT NULL CHECK (char_length(label) BETWEEN 1 AND 160),
  UNIQUE (post_id, ordinal)
);
CREATE TABLE post_poll_votes (
  option_id UUID NOT NULL REFERENCES post_poll_options(id) ON DELETE CASCADE,
  voter_id UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (option_id, voter_id)
);

-- Feed service must perform visibility checks against a relationship snapshot
-- or relationship service before returning friends-only rows. Application DB
-- credentials have no permission on IDENTITY_DATABASE or DOCUMENT_VAULT.
