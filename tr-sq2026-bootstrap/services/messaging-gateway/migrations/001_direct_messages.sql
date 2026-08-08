CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS direct_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  participant_low UUID NOT NULL,
  participant_high UUID NOT NULL,
  matrix_room_id TEXT NOT NULL UNIQUE,
  created_by UUID NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('profile', 'auction')),
  auction_id UUID NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (participant_low < participant_high),
  UNIQUE (participant_low, participant_high)
);

CREATE INDEX IF NOT EXISTS direct_conversations_low_idx ON direct_conversations (participant_low, created_at DESC);
CREATE INDEX IF NOT EXISTS direct_conversations_high_idx ON direct_conversations (participant_high, created_at DESC);

-- Projections are filled by identity/community outbox consumers. They are not
-- a second identity database and deliberately contain no password or document data.
CREATE TABLE IF NOT EXISTS messaging_user_projection (
  user_id UUID PRIMARY KEY,
  display_name TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS messaging_block_projection (
  blocker_id UUID NOT NULL,
  blocked_id UUID NOT NULL,
  active BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

CREATE TABLE IF NOT EXISTS messaging_audit_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id UUID NULL,
  conversation_id UUID NULL REFERENCES direct_conversations(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS messaging_audit_events_conversation_idx ON messaging_audit_events (conversation_id, created_at DESC);
