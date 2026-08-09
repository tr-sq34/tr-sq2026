-- Blocking, and the outbox that feeds it to messaging.
--
-- `messaging_block_projection` existed in the messaging database with no
-- producer, so the gateway's block check was permanently a no-op. Community
-- owns the social graph, so it owns the block edge and publishes it.

CREATE TABLE IF NOT EXISTS user_blocks (
  blocker_id UUID NOT NULL,
  blocked_id UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

-- "Who has blocked me" is needed to filter a viewer's feed, which is the
-- reverse of the primary key's leading column.
CREATE INDEX IF NOT EXISTS user_blocks_blocked_idx ON user_blocks (blocked_id);

-- Community had no outbox of its own; it was only a consumer of Identity's.
-- Mirroring the Identity table keeps one recovery story across both services:
-- the domain write and the outbox row commit together, and an unpublished row
-- is retried until the broker accepts it.
CREATE TABLE IF NOT EXISTS community_outbox_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  aggregate_type TEXT NOT NULL CHECK (aggregate_type IN ('user_block')),
  aggregate_id UUID NOT NULL,
  event_type TEXT NOT NULL CHECK (event_type IN ('messaging.user_blocked', 'messaging.user_unblocked')),
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at TIMESTAMPTZ,
  attempts SMALLINT NOT NULL DEFAULT 0 CHECK (attempts >= 0 AND attempts < 100)
);

CREATE INDEX IF NOT EXISTS community_outbox_events_pending_idx
  ON community_outbox_events (event_type, created_at)
  WHERE published_at IS NULL;
