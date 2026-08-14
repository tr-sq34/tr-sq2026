-- Saving, liking and sharing a listing.
--
-- The buttons have been on the listing card since the first screen and none of
-- them reached a table: the app flipped the icon, the repository threw
-- UnimplementedError, the catch put the icon back. A member who saved a listing
-- lost it the moment the list refreshed.
--
-- One table with a kind column rather than three tables, because these are the
-- same shape - one member, one listing, one act - and the counts are read
-- together on the same card.
--
-- There is no route that answers "who saved this listing" and there will not be
-- one. The seller sees how many, never who: interest in a used sofa is not an
-- introduction the buyer agreed to make.
CREATE TABLE marketplace_listing_reactions (
  listing_id UUID NOT NULL REFERENCES marketplace_listings(id) ON DELETE CASCADE,
  actor_id UUID NOT NULL,
  kind TEXT NOT NULL CHECK(kind IN ('save','like','share')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (listing_id, actor_id, kind)
);

-- The card asks for counts by listing, and the saved-listings shelf asks for
-- listings by member; the primary key serves the first, this index the second.
CREATE INDEX marketplace_listing_reactions_actor_idx
  ON marketplace_listing_reactions(actor_id, kind, created_at DESC);
