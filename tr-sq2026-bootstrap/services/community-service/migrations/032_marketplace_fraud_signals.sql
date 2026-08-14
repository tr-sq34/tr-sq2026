-- Indexes for the Çarşı risk signals.
--
-- The operator console now asks three questions about every listing it shows,
-- and none of them had an index to answer with:
--
--   * "has this exact title been posted by another account?" - the copy-paste
--     listing ring is the single most common scam pattern in a member-to-member
--     marketplace, and it is invisible one listing at a time. Matching is
--     case-insensitive, so a plain index on `title` would not be used.
--   * "how many listings did this seller open in the last day?" - the same
--     account posting a dozen items in an hour is either a shop or a burner.
--   * "what is the going rate in this category?" - a median over the active
--     listings of one category, computed per page of the queue.
--
-- All three are read-side only. Nothing here changes what a listing is, and no
-- row is scored or flagged in the database: the thresholds live in the console,
-- next to the sentence the operator reads, so a rule can be re-argued without a
-- migration.
CREATE INDEX IF NOT EXISTS marketplace_listings_title_lower_idx
  ON marketplace_listings (lower(title));

CREATE INDEX IF NOT EXISTS marketplace_listings_owner_created_idx
  ON marketplace_listings (owner_id, created_at DESC);

-- The median is taken over active listings of one category; the existing
-- category index carries created_at, which this query does not order by.
CREATE INDEX IF NOT EXISTS marketplace_listings_active_category_price_idx
  ON marketplace_listings (category, price) WHERE status = 'active';
