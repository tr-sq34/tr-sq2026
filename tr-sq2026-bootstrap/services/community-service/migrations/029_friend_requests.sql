-- Arkadaşlık.
--
-- relationship_projection has been in the schema since migration 002 and every
-- important question in this service reads it: which posts a member may see,
-- whose Stories appear, what the "Takip ettiklerin" tab contains, how many
-- friends a profile has, and whether two people may message each other.
--
-- Nothing has ever written a row into it. The only statement that touches it is
-- the one that deactivates rows on a block. So in production every friends-only
-- post is invisible to everybody, the following tab is empty for everybody,
-- every profile says 0 arkadaş, and no two members can open a conversation -
-- messaging is friends-only. The profile screen said so plainly: "Arkadaşlık
-- istekleri bir sonraki güncellemede açılıyor."
--
-- This is that update. The projection was always meant to be fed from an
-- outbox; there is no such producer and inventing one would mean a second
-- service before the first feature works. The request lives here, and accepting
-- it writes the projection in the same transaction.
CREATE TABLE friend_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID NOT NULL,
  addressee_id UUID NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','accepted','declined')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (requester_id <> addressee_id),
  -- One ask per direction. A declined request cannot be sent again by the same
  -- person: asking twice after a no is the thing this constraint exists to make
  -- impossible. Whoever declined can still send their own request the other way
  -- if they change their mind, so a mistaken no is not permanent.
  UNIQUE (requester_id, addressee_id)
);

-- The inbox: "who is waiting for an answer from me", newest first.
CREATE INDEX friend_requests_inbox_idx
  ON friend_requests(addressee_id, created_at DESC) WHERE status = 'pending';

-- Cancelling your own request and unfriending both delete the row rather than
-- marking it, so either side may ask again later. Only a decline is remembered.

-- Friendship is mutual, so the projection gets both directions on accept.
-- 'following' stays in the CHECK from 002 and is still unused: a one-way follow
-- is a different feature with different consent, not a half-finished friendship.

ALTER TABLE member_notifications DROP CONSTRAINT member_notifications_kind_check;
ALTER TABLE member_notifications ADD CONSTRAINT member_notifications_kind_check
  CHECK (kind IN ('post_comment','post_like','listing_save','listing_like','special_request','friend_request'));
