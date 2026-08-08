-- Transactional outbox: Community never reads Identity tables directly.
CREATE TABLE identity_outbox_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  aggregate_type TEXT NOT NULL CHECK (aggregate_type IN ('user_onboarding')),
  aggregate_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN ('community.profile_upserted')),
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at TIMESTAMPTZ,
  attempts SMALLINT NOT NULL DEFAULT 0 CHECK (attempts >= 0 AND attempts < 100)
);
CREATE INDEX identity_outbox_events_pending_idx ON identity_outbox_events(created_at)
  WHERE published_at IS NULL;
