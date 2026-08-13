-- SOS: the one place a member's exact location is allowed to exist.
--
-- Everything else in this database is built on the opposite rule. Migration 008
-- says it plainly - locality is a chosen city/state preference, never a
-- continuous exact trail - and the Analitik screen goes as far as suppressing
-- small city buckets so a count cannot name a person. This table is the
-- deliberate exception, and it is narrow on purpose:
--
--   * the member sends the point themselves, at the moment they ask for help,
--     and only then. Nothing here is a background trail; there is no second row
--     per member and no history to walk.
--   * the point sits sealed. An operator listing alerts does not receive it.
--     Reading it takes a separate, reasoned, time-boxed grant (sos_location_grants),
--     which expires on its own and is revoked the moment the alert closes.
--   * cancelling is the member's right and it is destructive: the point is
--     deleted, not hidden. A member who says "I am fine" should not leave their
--     coordinates behind in an operations console.

CREATE TABLE IF NOT EXISTS sos_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id UUID NOT NULL,
  -- What kind of help is being asked for. Not a severity: an operator cannot
  -- rank someone else's emergency, and a queue sorted by our guess at severity
  -- is a queue that answers the wrong person first.
  kind TEXT NOT NULL CHECK (kind IN ('personal_safety', 'medical', 'harassment', 'accident', 'other')),
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'acknowledged', 'resolved', 'cancelled')),
  -- The member's own words, optional. Free text and short: this is typed with
  -- shaking hands, not composed.
  note TEXT CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 500),
  -- Sealed until a grant exists. NULL is a legitimate state and always was:
  -- the member may refuse location permission and still need help, so no part
  -- of the flow may require this column to be set.
  location_cell geography(Point, 4326),
  location_accuracy_m INT CHECK (location_accuracy_m IS NULL OR location_accuracy_m BETWEEN 0 AND 100000),
  location_captured_at TIMESTAMPTZ,
  -- A place the member typed, if any. Unlike the point, this is never sealed:
  -- it is what they chose to say out loud.
  location_note TEXT CHECK (location_note IS NULL OR char_length(location_note) <= 200),
  acknowledged_at TIMESTAMPTZ,
  acknowledged_by UUID,
  closed_at TIMESTAMPTZ,
  closed_by UUID,
  closure_reason TEXT CHECK (closure_reason IS NULL OR char_length(closure_reason) BETWEEN 5 AND 1000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- An open alert must have no closing marks and a closed one must carry them.
  -- Written as a constraint because "closed but still on the operator's queue"
  -- is the failure that gets somebody hurt.
  CONSTRAINT sos_alerts_closure_consistent CHECK (
    (status IN ('active', 'acknowledged') AND closed_at IS NULL AND closed_by IS NULL)
    OR (status IN ('resolved', 'cancelled') AND closed_at IS NOT NULL)
  )
);

-- One open alert per member. A panic button pressed four times is one
-- emergency, and four rows would split the response across four cards.
CREATE UNIQUE INDEX IF NOT EXISTS sos_alerts_one_open_per_member
  ON sos_alerts (member_id)
  WHERE status IN ('active', 'acknowledged');

-- The operator queue: open first, oldest first. Oldest rather than newest,
-- because the person who has been waiting longest is the one being failed.
CREATE INDEX IF NOT EXISTS sos_alerts_queue_idx
  ON sos_alerts (created_at)
  WHERE status IN ('active', 'acknowledged');

CREATE INDEX IF NOT EXISTS sos_alerts_member_idx ON sos_alerts (member_id, created_at DESC);

-- The seal. A row here is one operator being able to read one alert's point for
-- a bounded time, with a written reason.
--
-- Not deleted when it expires: the expired row is the record that somebody
-- looked, which is the entire point of making them ask. Reads test
-- `expires_at > now() AND revoked_at IS NULL`, never the row's existence.
CREATE TABLE IF NOT EXISTS sos_location_grants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id UUID NOT NULL REFERENCES sos_alerts(id) ON DELETE CASCADE,
  operator_id UUID NOT NULL,
  operator_roles TEXT[] NOT NULL,
  reason TEXT NOT NULL CHECK (char_length(reason) BETWEEN 5 AND 500),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT sos_location_grants_bounded CHECK (expires_at > created_at)
);

CREATE INDEX IF NOT EXISTS sos_location_grants_live_idx
  ON sos_location_grants (alert_id, operator_id, expires_at DESC)
  WHERE revoked_at IS NULL;
