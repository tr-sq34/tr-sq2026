-- What a listing is.
--
-- marketplace_listings has had no category column since migration 010, so the
-- serializer had nothing to read and wrote the same constant on every card:
-- `category:'Diğer'`. Everything downstream is built on that field. Çarşı's
-- "Kategori" screen offers six categories, the filter chips compare against it,
-- and search matches on it - all of them against a value that is identical for
-- every listing in the database. Tapping "Araçlar" could only ever return
-- nothing or everything.
--
-- The one thing that did set it was the composer's "AI ile taslağı doldur"
-- button, which guessed a category (along with a title, a price and a
-- description) from the listing type and then handed it to a create endpoint
-- that dropped it. That button is gone in the same change; a seller picks the
-- category now.
--
-- The values are the app's keys, not its labels, for the same reason as the
-- event categories in migration 022: the Turkish wording on the chip can be
-- rewritten without a data migration, and a row cannot end up in a category no
-- screen opens.
ALTER TABLE marketplace_listings
  ADD COLUMN category TEXT NOT NULL DEFAULT 'other'
    CHECK (category IN ('vehicle','rental','home','electronics','collectible','art','other'));

-- Existing rows stay 'other'. Nobody chose a category for them and guessing one
-- from the title would put somebody's listing in a section they never picked.

CREATE INDEX marketplace_listings_active_category_created_idx
  ON marketplace_listings(category, created_at DESC) WHERE status = 'active';
