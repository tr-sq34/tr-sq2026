-- Stories use only coarse profile regions; exact device location never leaves
-- the location service or appears in a Story response.
ALTER TABLE stories ADD COLUMN IF NOT EXISTS region_code TEXT;

CREATE TABLE IF NOT EXISTS community_system_accounts (
  user_id UUID PRIMARY KEY,
  role TEXT NOT NULL CHECK (role IN ('official')),
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS stories_region_created_idx
  ON stories (region_code, created_at DESC, id DESC);
