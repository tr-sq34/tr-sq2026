-- Listing photos. Until now a listing had no way to carry one: the app drew a
-- stock photo of someone else's kitchen on every card in the marketplace.
--
-- Same shape as post_media_refs: the listing points at a scanned media_assets
-- row, and ordinal decides which photo is the cover.
CREATE TABLE marketplace_listing_media (
  listing_id UUID NOT NULL REFERENCES marketplace_listings(id) ON DELETE CASCADE,
  media_id UUID NOT NULL REFERENCES media_assets(id),
  ordinal SMALLINT NOT NULL,
  PRIMARY KEY (listing_id, media_id)
);
CREATE UNIQUE INDEX marketplace_listing_media_order_idx
  ON marketplace_listing_media(listing_id, ordinal);
