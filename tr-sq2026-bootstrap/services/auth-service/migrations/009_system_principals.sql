CREATE TABLE IF NOT EXISTS system_principals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name TEXT NOT NULL CHECK (char_length(display_name) BETWEEN 2 AND 100),
  handle CITEXT UNIQUE NOT NULL CHECK (handle ~ '^[a-z0-9][a-z0-9_-]{2,39}$'),
  kind TEXT NOT NULL DEFAULT 'official' CHECK (kind IN ('official')),
  active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deactivated_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS system_principals_active_idx ON system_principals(active, created_at DESC);
