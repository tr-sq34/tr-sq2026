-- Messaging moderation.
--
-- Apple's App Review guideline 1.2 and Google Play's user-generated content
-- policy both require the same three things from any app that carries user
-- messages: an in-app way to report content, a way to block a user, and acting
-- on a report within 24 hours. Blocking already exists in community-service.
-- These tables are the other two: the report itself, the decision taken on it,
-- and the restriction that decision may produce.
--
-- The 24-hour promise is why due_at is a stored column rather than something the
-- console computes. A reviewer needs to sort by it, an auditor needs to prove it
-- was met after the fact, and both have to agree with what the clock said when
-- the report was filed.

CREATE TABLE IF NOT EXISTS messaging_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL,
  -- Null when a whole thread is reported and the client could not attribute it
  -- to one sender; the reviewer resolves it from the evidence.
  reported_user_id UUID NULL,
  scope TEXT NOT NULL CHECK (scope IN ('direct', 'group')),
  conversation_id UUID NULL REFERENCES direct_conversations(id) ON DELETE SET NULL,
  group_id UUID NULL REFERENCES messaging_groups(id) ON DELETE SET NULL,
  -- Kept even when the row above is nulled by a delete: it is what a moderator
  -- needs to redact the event in Matrix.
  matrix_room_id TEXT NOT NULL,
  matrix_event_id TEXT NULL,
  category TEXT NOT NULL CHECK (category IN (
    'child_safety', 'self_harm', 'violence_threat', 'hate_speech', 'harassment',
    'sexual_content', 'scam_fraud', 'illegal_goods', 'spam', 'other'
  )),
  note TEXT NULL,
  -- Frozen copy of the reported message and a few around it, taken at report
  -- time. Without it a reporter could be silenced by the sender deleting the
  -- message, and a moderator would be reviewing an empty room. It is also what
  -- lets the console show evidence without granting anyone the ability to read
  -- live private conversations.
  evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
  priority TEXT NOT NULL CHECK (priority IN ('urgent', 'standard')),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_review', 'actioned', 'dismissed')),
  due_at TIMESTAMPTZ NOT NULL,
  assigned_to UUID NULL,
  resolution TEXT NULL,
  resolved_by UUID NULL,
  resolved_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The review queue is always "unresolved, most urgent deadline first", so the
-- index carries the ordering rather than leaving it to a sort of the whole
-- table.
CREATE INDEX IF NOT EXISTS messaging_reports_queue_idx
  ON messaging_reports (due_at ASC, id ASC)
  WHERE status IN ('open', 'in_review');

CREATE INDEX IF NOT EXISTS messaging_reports_reported_user_idx
  ON messaging_reports (reported_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS messaging_reports_created_idx
  ON messaging_reports (created_at DESC, id DESC);

-- One person may report the same message once while it is unresolved. Reporting
-- it again after a decision is allowed on purpose: a dismissal that turns out to
-- be wrong should be re-openable by the same route as any other report.
CREATE UNIQUE INDEX IF NOT EXISTS messaging_reports_open_dedup_idx
  ON messaging_reports (reporter_id, matrix_room_id, matrix_event_id)
  WHERE status IN ('open', 'in_review') AND matrix_event_id IS NOT NULL;

-- Every moderator decision, including the ones that changed nothing. An audit of
-- a takedown is only worth something if the "we looked and left it up" cases are
-- in the same table.
CREATE TABLE IF NOT EXISTS messaging_moderation_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id UUID NULL REFERENCES messaging_reports(id) ON DELETE SET NULL,
  actor_id UUID NOT NULL,
  actor_roles TEXT[] NOT NULL,
  action TEXT NOT NULL,
  target_type TEXT NOT NULL CHECK (target_type IN ('report', 'message', 'user', 'group')),
  target_id TEXT NOT NULL,
  reason TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS messaging_moderation_actions_created_idx
  ON messaging_moderation_actions (created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS messaging_moderation_actions_target_idx
  ON messaging_moderation_actions (target_type, target_id, created_at DESC);

-- A restriction stops a user from writing without removing what they already
-- wrote or destroying their account. Guideline 1.2 asks for the offending user
-- to be ejected; in practice most cases deserve a bounded mute first, and the
-- permanent case is the same row with no expiry.
CREATE TABLE IF NOT EXISTS messaging_user_restrictions (
  user_id UUID PRIMARY KEY,
  restriction TEXT NOT NULL CHECK (restriction IN ('muted', 'suspended')),
  reason TEXT NOT NULL,
  -- Null means indefinite. An expired row is left in place rather than deleted
  -- so a repeat offender's history stays visible to the next reviewer.
  expires_at TIMESTAMPTZ NULL,
  created_by UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS messaging_user_restrictions_active_idx
  ON messaging_user_restrictions (expires_at);

-- A group taken down is hidden, not deleted. The reports that caused the
-- takedown reference it, a wrongly removed group has to be restorable, and the
-- Matrix room keeps the history a later legal request may ask for.
ALTER TABLE messaging_groups
  ADD COLUMN IF NOT EXISTS removed_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS removed_reason TEXT NULL;

-- Mirrors community-service's table of the same name. The console talks to two
-- services and an auditor has to be able to reconstruct one timeline from both,
-- so the shape is deliberately identical.
CREATE TABLE IF NOT EXISTS gatework_command_dedup (
  actor_id UUID NOT NULL,
  idempotency_key UUID NOT NULL,
  command_type TEXT NOT NULL,
  result_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (actor_id, idempotency_key, command_type)
);
