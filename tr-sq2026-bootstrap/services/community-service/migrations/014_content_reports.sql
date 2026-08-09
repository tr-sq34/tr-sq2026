-- Reporting for feed content: posts, comments and stories.
--
-- Messaging already had this (messaging-gateway migration 004). The feed did
-- not: the app's "Raporla" menu item showed a snackbar reading "Rapor alindi.
-- Inceleme ekibimiz degerlendirecek." and made no call at all, so nothing was
-- ever recorded and no moderator ever saw it. Apple guideline 1.2 and Google
-- Play's UGC policy ask for one mechanism covering all user content, not just
-- private messages, and a button that lies is worse than no button.
--
-- The shape deliberately mirrors messaging_reports - same categories, same
-- priorities, same SLA clock - so the console can put both queues on one screen
-- and a moderator does not have to learn two vocabularies.

CREATE TABLE IF NOT EXISTS content_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL,
  -- Resolved from the target when the report is filed rather than joined later:
  -- the author is what a moderator acts on, and a deleted post must not take
  -- that information with it.
  reported_user_id UUID NOT NULL,
  target_type TEXT NOT NULL CHECK (target_type IN ('post', 'comment', 'story')),
  -- No foreign key on purpose. The target is polymorphic, and more importantly a
  -- report has to outlive the content it is about: ON DELETE CASCADE would erase
  -- the evidence for the very takedown that caused the delete, and the audit
  -- trail is what proves the 24-hour promise was kept.
  target_id UUID NOT NULL,
  category TEXT NOT NULL CHECK (category IN (
    'child_safety', 'self_harm', 'violence_threat', 'hate_speech', 'harassment',
    'sexual_content', 'scam_fraud', 'illegal_goods', 'spam', 'other'
  )),
  note TEXT CHECK (note IS NULL OR char_length(note) <= 500),
  -- Frozen copy of the reported content taken at report time: body text, author,
  -- and the media ids attached to it. Without it, an author could silence a
  -- report by deleting the post a second after it was filed, and the reviewer
  -- would open an empty case.
  evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
  priority TEXT NOT NULL CHECK (priority IN ('urgent', 'standard')),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_review', 'actioned', 'dismissed')),
  -- Stored, not computed by the console: a reviewer sorts by it and an auditor
  -- has to be able to prove after the fact what the deadline was when the report
  -- arrived, which a recomputation from changing SLA settings cannot do.
  due_at TIMESTAMPTZ NOT NULL,
  assigned_to UUID,
  resolution TEXT CHECK (resolution IS NULL OR char_length(resolution) <= 500),
  resolved_by UUID,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (reporter_id <> reported_user_id)
);

-- The queue is always "unresolved, nearest deadline first", so the index carries
-- that ordering instead of leaving it to a sort over the whole table.
CREATE INDEX IF NOT EXISTS content_reports_queue_idx
  ON content_reports (due_at ASC, id ASC)
  WHERE status IN ('open', 'in_review');

-- "What else has this author been reported for" is the first thing a reviewer
-- asks, and it decides whether a case is a one-off or a pattern.
CREATE INDEX IF NOT EXISTS content_reports_reported_user_idx
  ON content_reports (reported_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS content_reports_target_idx
  ON content_reports (target_type, target_id, created_at DESC);

-- One person may have one unresolved report per piece of content. Filing again
-- after a decision is allowed on purpose: a dismissal that turns out to be wrong
-- has to be re-openable through the same door as any other report.
CREATE UNIQUE INDEX IF NOT EXISTS content_reports_open_dedup_idx
  ON content_reports (reporter_id, target_type, target_id)
  WHERE status IN ('open', 'in_review');

-- Every decision, including the ones that changed nothing. An audit of takedowns
-- is only worth something if "we looked and left it up" is in the same table.
CREATE TABLE IF NOT EXISTS content_moderation_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id UUID REFERENCES content_reports(id) ON DELETE SET NULL,
  actor_id UUID NOT NULL,
  actor_roles TEXT[] NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('claim', 'dismiss', 'remove_content', 'restrict_author', 'lift_restriction')),
  target_type TEXT NOT NULL CHECK (target_type IN ('report', 'post', 'comment', 'story', 'user')),
  target_id TEXT NOT NULL,
  reason TEXT NOT NULL CHECK (char_length(reason) BETWEEN 5 AND 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS content_moderation_actions_recent_idx
  ON content_moderation_actions (created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS content_moderation_actions_report_idx
  ON content_moderation_actions (report_id, created_at DESC);

-- Guideline 1.2 asks for a way to eject an abusive user, not only to delete what
-- they wrote. Removing the post and leaving the account free to post the same
-- thing again is the gap this closes.
--
-- One row per user rather than a history table: the question asked on every
-- write is "is this account restricted right now", and an expired or lifted
-- restriction stays visible in content_moderation_actions, which is where the
-- history belongs.
CREATE TABLE IF NOT EXISTS content_author_restrictions (
  user_id UUID PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('muted', 'suspended')),
  reason TEXT NOT NULL CHECK (char_length(reason) BETWEEN 5 AND 500),
  -- NULL means indefinite. A suspension with no end date is a decision someone
  -- has to take back by hand, which is the intent for the worst cases.
  expires_at TIMESTAMPTZ,
  created_by UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS content_author_restrictions_active_idx
  ON content_author_restrictions (expires_at)
  WHERE expires_at IS NOT NULL;
