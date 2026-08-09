-- Identity becomes the source of the messaging user projection.
--
-- The messaging gateway refuses to open a conversation unless both participants
-- exist and are active in `messaging_user_projection`. Nothing produced those
-- rows, so every direct message failed with USER_NOT_AVAILABLE. Identity owns
-- the display name and the account lifecycle, so it owns this event.
--
-- The existing outbox table is reused rather than duplicated: one publisher
-- loop, one delivery guarantee, one place where a crash between the domain
-- write and the publish is recovered.

ALTER TABLE identity_outbox_events DROP CONSTRAINT IF EXISTS identity_outbox_events_aggregate_type_check;
ALTER TABLE identity_outbox_events ADD CONSTRAINT identity_outbox_events_aggregate_type_check
  CHECK (aggregate_type IN ('user_onboarding', 'user'));

ALTER TABLE identity_outbox_events DROP CONSTRAINT IF EXISTS identity_outbox_events_event_type_check;
ALTER TABLE identity_outbox_events ADD CONSTRAINT identity_outbox_events_event_type_check
  CHECK (event_type IN ('community.profile_upserted', 'messaging.user_upserted'));

-- The pending index was partial on created_at only. The publisher now filters
-- by event_type as well, so without this the messaging drain scans every
-- pending community event on each poll.
DROP INDEX IF EXISTS identity_outbox_events_pending_idx;
CREATE INDEX IF NOT EXISTS identity_outbox_events_pending_idx
  ON identity_outbox_events(event_type, created_at)
  WHERE published_at IS NULL;

-- Backfill: existing verified accounts predate this event type and would
-- otherwise never appear in the projection, leaving current users unable to
-- message each other.
--
-- The consumer's ordering key is the outbox row's created_at, which is the
-- Identity transaction time. These backfilled rows are the first messaging
-- event any of these users ever produced, so a genuine later change always
-- carries a higher timestamp and wins.
INSERT INTO identity_outbox_events(aggregate_type, aggregate_id, event_type, payload)
SELECT
  'user',
  u.id,
  'messaging.user_upserted',
  jsonb_build_object('userId', u.id, 'displayName', u.display_name, 'active', true)
FROM users u
WHERE u.email_verified_at IS NOT NULL;
