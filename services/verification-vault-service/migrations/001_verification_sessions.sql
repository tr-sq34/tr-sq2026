CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE verification_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID NOT NULL, stripe_session_id TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL CHECK(status IN ('created','requires_input','verified','canceled','redacted')),
  policy_version TEXT NOT NULL, expires_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), redacted_at TIMESTAMPTZ
);
CREATE TABLE processed_stripe_webhooks (stripe_event_id TEXT PRIMARY KEY, processed_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE verification_outbox_events (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), event_type TEXT NOT NULL, payload JSONB NOT NULL, published_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
