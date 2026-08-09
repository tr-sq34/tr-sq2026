-- Projection ingest support.
--
-- 001 created the projection tables but nothing wrote to them, so every
-- ensureConversation() call failed with USER_NOT_AVAILABLE. This migration adds
-- the two guarantees a Service Bus consumer needs to be safe:
--
--   1. Idempotency. Service Bus is at-least-once; the same event id can be
--      delivered more than once (redelivery after a lock expiry, or a crash
--      between the projection write and completeMessage).
--   2. Ordering. Service Bus does not guarantee ordering across competing
--      consumers, so a stale `user_upserted` can arrive after a newer one.
--      Every projection row therefore records the producer-side timestamp of
--      the event that last wrote it, and writes older than that are dropped.

CREATE TABLE IF NOT EXISTS processed_messaging_events (
  event_id UUID PRIMARY KEY,
  event_type TEXT NOT NULL,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Retention: the consumer prunes rows older than the Service Bus message TTL
-- (P14D). Anything older can no longer be redelivered, so keeping it would only
-- grow the table.
CREATE INDEX IF NOT EXISTS processed_messaging_events_processed_idx
  ON processed_messaging_events (processed_at);

-- '-infinity' means "never written by an event", so the first event of any age
-- wins for rows that predate this migration.
ALTER TABLE messaging_user_projection
  ADD COLUMN IF NOT EXISTS source_event_at TIMESTAMPTZ NOT NULL DEFAULT '-infinity';

ALTER TABLE messaging_block_projection
  ADD COLUMN IF NOT EXISTS source_event_at TIMESTAMPTZ NOT NULL DEFAULT '-infinity';

-- The inbox is ordered by conversation activity, not by creation date. Without
-- this column a user's newest conversation sinks to the bottom of the list as
-- soon as an older conversation receives a reply.
ALTER TABLE direct_conversations
  ADD COLUMN IF NOT EXISTS last_message_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- The DEFAULT would stamp every pre-existing conversation with the migration
-- time and collapse the inbox into one arbitrary order. Message bodies live in
-- Matrix, not here, so creation time is the best activity estimate available.
UPDATE direct_conversations SET last_message_at = created_at WHERE last_message_at > created_at;

DROP INDEX IF EXISTS direct_conversations_low_idx;
DROP INDEX IF EXISTS direct_conversations_high_idx;

CREATE INDEX IF NOT EXISTS direct_conversations_low_activity_idx
  ON direct_conversations (participant_low, last_message_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS direct_conversations_high_activity_idx
  ON direct_conversations (participant_high, last_message_at DESC, id DESC);
