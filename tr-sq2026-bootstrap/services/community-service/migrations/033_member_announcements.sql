-- The console has had a "Global duyuru geç" button since the command centre was
-- built, and it has been disabled the whole time: nothing in any service could
-- write a sentence to every member. This is that table.
--
-- The text lives here rather than in member_notifications because a single
-- announcement is one editorial act with one author, not one per recipient.
-- The notification rows point at this row; the copy is stored once.
CREATE TABLE member_announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 3 AND 120),
  body TEXT NOT NULL CHECK (char_length(body) BETWEEN 3 AND 2000),
  -- The operator who sent it. Kept for the same reason an event keeps
  -- created_by: a message that reaches every member should be attributable to
  -- a person, not to "the system".
  created_by UUID NOT NULL,
  -- How many inboxes it actually landed in, counted at send time. Recounting it
  -- later would answer a different question - members join and leave - and the
  -- console reports what the send did, not what the membership is today.
  recipient_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX member_announcements_recent_idx ON member_announcements(created_at DESC);

-- 'announcement' is the first kind whose subject is not something a member did.
-- Every other kind counts actors against a post or a listing; this one has an
-- audience of everybody and an actor count of exactly one, and the row's whole
-- content is the announcement it points at.
ALTER TABLE member_notifications DROP CONSTRAINT member_notifications_kind_check;
ALTER TABLE member_notifications ADD CONSTRAINT member_notifications_kind_check
  CHECK (kind IN ('post_comment','post_like','listing_save','listing_like','special_request','friend_request','announcement'));
