-- Locality is a chosen city/state preference, never a continuous exact trail.
ALTER TABLE community_profile_projection
  ADD COLUMN IF NOT EXISTS city TEXT,
  ADD COLUMN IF NOT EXISTS region_code TEXT CHECK (region_code ~ '^[A-Z]{2}$'),
  ADD COLUMN IF NOT EXISTS interests TEXT[] NOT NULL DEFAULT '{}';

ALTER TABLE community_posts
  ADD COLUMN IF NOT EXISTS region_code TEXT CHECK (region_code ~ '^[A-Z]{2}$');

CREATE INDEX IF NOT EXISTS community_posts_region_created_idx
  ON community_posts(region_code, created_at DESC)
  WHERE deleted_at IS NULL AND moderation_state = 'active';
