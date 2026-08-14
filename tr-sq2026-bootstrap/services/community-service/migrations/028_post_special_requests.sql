-- "Eşleşme isteği gönder" / "Destek teklif et".
--
-- The sheet has always ended with the snackbar "İsteğin gönderildi." and it has
-- always been a lie: MockCommunitySpecialRequestRepository was wired on both
-- sides of the mock flag, so the request went into a Dart list in the sender's
-- own process and died with it. The post owner was never told anything. The
-- read method existed and nothing ever called it, because there was nowhere for
-- an owner to look.
--
-- This is the table those requests were always supposed to land in.
--
-- One request per member per post. Somebody who wants to say more edits what
-- they already sent instead of stacking five copies in the owner's list, and -
-- more importantly - a declined request cannot be sent again. Re-asking after a
-- no is exactly the behaviour a UNIQUE constraint should make impossible rather
-- than something the owner has to keep declining.
--
-- Unlike a like or a save, this is an introduction the sender is deliberately
-- making: they wrote a message and asked to be put in touch. So the owner sees
-- who it is. That is not a break with the counts-only rule elsewhere; it is the
-- same rule, applied to an act that means the opposite thing.
CREATE TABLE post_special_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('imece_offer','traveler_match')),
  message TEXT NOT NULL CHECK (char_length(message) BETWEEN 1 AND 500),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','accepted','declined','cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (post_id, sender_id)
);

-- The owner opens one post and reads its requests newest first; that is the
-- only question this table is asked.
CREATE INDEX post_special_requests_post_idx
  ON post_special_requests(post_id, created_at DESC);

-- Requests are their own notification kind: an offer to carry something in a
-- suitcase is not a like, and burying it in the same aggregate line would be
-- the one notification a member actually needs to act on, counted.
ALTER TABLE member_notifications DROP CONSTRAINT member_notifications_kind_check;
ALTER TABLE member_notifications ADD CONSTRAINT member_notifications_kind_check
  CHECK (kind IN ('post_comment','post_like','listing_save','listing_like','special_request'));
