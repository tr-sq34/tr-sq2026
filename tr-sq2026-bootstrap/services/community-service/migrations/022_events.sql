-- Etkinlikler: the tab the app has shipped with since day one, against a
-- repository that was hardcoded to `MockEventsRepository` in `main.dart`.
--
-- Every member has been looking at the same four invented meetups. There is no
-- table behind them, no route (`GET /v1/events` has never existed) and no way
-- for anybody at TurkSquare to publish a real one. This migration is the table.
--
-- Events are published from the console, not from the app. The app has no
-- composer for them and inventing one here would mean shipping a moderation
-- queue in the same breath; an operator publishing under a known name is the
-- honest version of "official event" and it is what the panel is for. When
-- members get to host their own, this table gains a `host_id` and a review
-- state - not a second table.
CREATE TABLE IF NOT EXISTS community_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 3 AND 140),
  description TEXT NOT NULL DEFAULT '' CHECK (char_length(description) <= 4000),
  -- A short label the app groups by ("Buluşma", "Kültür", "Spor"). Free text
  -- rather than an enum: the categories that matter are the ones the community
  -- turns out to want, and a CHECK list would need a migration to learn one.
  category TEXT NOT NULL DEFAULT 'Etkinlik' CHECK (char_length(category) BETWEEN 2 AND 40),
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ,
  CONSTRAINT community_events_window_ordered CHECK (ends_at IS NULL OR ends_at > starts_at),
  -- Where it is, as a place a person can read: a venue name and a city. No
  -- coordinates, for the reason migration 021 gives - locality here is what the
  -- publisher chose to write down, and an event that needs a map pin can put
  -- the address in `venue_label`.
  venue_label TEXT NOT NULL CHECK (char_length(venue_label) BETWEEN 2 AND 200),
  city TEXT NOT NULL CHECK (char_length(city) BETWEEN 2 AND 80),
  region_code CHAR(2) NOT NULL,
  -- Media id, never a URL: resolved through `media_assets` on the way out so an
  -- unscanned image cannot reach the app. NULL is a perfectly good event.
  media_id UUID REFERENCES media_assets(id),
  -- What it costs, as text, because no money changes hands in this phase and a
  -- numeric price column with no payment behind it is a promise the service
  -- cannot keep. "Ücretsiz", "Kapıda 20$", "Bağış" are all honest answers.
  price_label TEXT NOT NULL DEFAULT 'Ücretsiz' CHECK (char_length(price_label) BETWEEN 1 AND 60),
  -- Where to sign up when the sign-up is not here. NULL means the RSVP below is
  -- the whole story.
  external_url TEXT CHECK (external_url IS NULL OR external_url ~ '^https://'),
  -- Optional ceiling. Enforced when somebody says they are going; NULL is an
  -- event with no door count.
  capacity INTEGER CHECK (capacity IS NULL OR capacity > 0),
  -- 'draft' is being written, 'published' is visible in the app, 'cancelled'
  -- happened and then did not. Cancelled rows stay: people planned around them,
  -- and deleting the row would silently empty their calendar.
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'cancelled')),
  cancellation_reason TEXT CHECK (cancellation_reason IS NULL OR char_length(cancellation_reason) BETWEEN 3 AND 500),
  published_at TIMESTAMPTZ,
  -- The operator who published it. The audit trail answers "who", this column
  -- answers it without a join for the console's own list.
  created_by UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The query the app runs on every open: published events that have not started
-- yet, soonest first. Drafts and cancellations - which accumulate - stay out of
-- that path entirely.
CREATE INDEX IF NOT EXISTS community_events_upcoming_idx
  ON community_events (starts_at ASC, id ASC)
  WHERE status = 'published';

CREATE INDEX IF NOT EXISTS community_events_console_idx
  ON community_events (status, starts_at DESC);

-- One row per member per event, not an append-only log of attendance changes.
--
-- "Kimler geliyor" is a list of people who were somewhere at a known time, and
-- keeping every flip of that answer would be a movement history assembled out
-- of RSVPs. The current answer is the only one the app ever asks for, so it is
-- the only one stored; changing your mind overwrites, and withdrawing deletes.
CREATE TABLE IF NOT EXISTS event_rsvps (
  event_id UUID NOT NULL REFERENCES community_events(id) ON DELETE CASCADE,
  member_id UUID NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('going', 'interested')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, member_id)
);

-- Counting the going-list for a card, and answering "am I going" for the
-- viewer, are the only two reads. Both are this index.
CREATE INDEX IF NOT EXISTS event_rsvps_event_idx ON event_rsvps (event_id, status);
CREATE INDEX IF NOT EXISTS event_rsvps_member_idx ON event_rsvps (member_id, created_at DESC);
