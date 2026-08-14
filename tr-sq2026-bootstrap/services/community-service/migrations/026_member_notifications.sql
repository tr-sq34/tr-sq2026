-- The bell.
--
-- Until now the bell was wired to EmptyNotificationRepository, which returned
-- an empty list on purpose: nothing in this system published notifications, so
-- an empty list was the only honest answer. This table is the source it was
-- waiting for.
--
-- One row per (member, kind, subject), not per tap. Ten people liking the same
-- post is one line in the bell, and the tenth like does not bury the first
-- comment underneath nine copies of itself.
--
-- There is deliberately no count column. The number of people is read live from
-- the table the act actually lives in, which means unliking takes the number
-- back down, a deleted post takes the whole line away, and nobody can inflate
-- their own notification by tapping like on and off two hundred times. A stored
-- counter would have recorded all two hundred.
--
-- read_at goes back to NULL when new activity lands on the same subject. A line
-- you already read becoming unread again is correct: something new happened.
--
-- Who is named follows the rule the rest of the service already follows. A
-- comment is public writing, so the commenter is named. A like and a save are
-- not: the seller learns how many people saved the sofa, never which ones, and
-- the same goes for the post author. That is why last_actor_id exists but the
-- read route only surfaces it for comments.
--
-- Replies to comments are not here yet. They need the parent comment as the
-- subject and the post as the destination, which is a different shape from the
-- four below; doing it badly now would mean unpicking it later.
CREATE TABLE member_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  kind TEXT NOT NULL CHECK(kind IN ('post_comment','post_like','listing_save','listing_like')),
  subject_id UUID NOT NULL,
  last_actor_id UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at TIMESTAMPTZ,
  UNIQUE (user_id, kind, subject_id)
);

-- The bell asks exactly one question - "what is new for me" - and asks it on
-- every app open, so it gets the index.
CREATE INDEX member_notifications_inbox_idx
  ON member_notifications(user_id, updated_at DESC);
