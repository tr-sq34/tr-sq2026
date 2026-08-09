-- Community groups.
--
-- A group is a Matrix room like a direct conversation is, so message reading and
-- sending reuse the same code path. What differs is who may be in the room:
-- membership is decided here, not in Matrix, because a public group must be
-- joinable without an invite while a private one needs an owner's approval, and
-- both states have to be queryable for a member list the client can render.

CREATE TABLE IF NOT EXISTS messaging_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  matrix_room_id TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  city TEXT NOT NULL,
  privacy TEXT NOT NULL CHECK (privacy IN ('public', 'private')),
  image_url TEXT NULL,
  created_by UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_message_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Discovery lists every group by recent activity, the same ordering the inbox
-- uses, so the same (activity, id) cursor works for both.
CREATE INDEX IF NOT EXISTS messaging_groups_activity_idx
  ON messaging_groups (last_message_at DESC, id DESC);

-- `requested` rows exist only for private groups: the user is not in the Matrix
-- room yet and cannot read anything until an owner approves. Declining removes
-- the row rather than storing a third state, so a user may ask again later.
CREATE TABLE IF NOT EXISTS messaging_group_members (
  group_id UUID NOT NULL REFERENCES messaging_groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('owner', 'member')),
  status TEXT NOT NULL CHECK (status IN ('joined', 'requested')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

CREATE INDEX IF NOT EXISTS messaging_group_members_user_idx
  ON messaging_group_members (user_id, status);

-- The audit trail already covers direct conversations. Group events need their
-- own column because conversation_id is a foreign key into a different table;
-- reusing it would either break the constraint or silently drop the reference.
ALTER TABLE messaging_audit_events
  ADD COLUMN IF NOT EXISTS group_id UUID NULL REFERENCES messaging_groups(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS messaging_audit_events_group_idx
  ON messaging_audit_events (group_id, created_at DESC);
