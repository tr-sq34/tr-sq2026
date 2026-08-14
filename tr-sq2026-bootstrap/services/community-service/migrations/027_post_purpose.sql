-- What a post is for.
--
-- "Bavulda Yer Var" and "Destek İste" have been in the composer since the first
-- build. A member picks the suitcase, fills in Istanbul -> New York, 5 kg, the
-- date, publishes - and the server stores a plain post. The purpose and every
-- detail of the trip were dropped on the way out of the app, so the banner and
-- the "send a match request" button never appeared on anybody else's screen.
-- The feature existed entirely inside the phone that wrote it.
--
-- purpose is a column on the post rather than a separate table because every
-- post has exactly one and the feed reads it on every row.
ALTER TABLE community_posts
  ADD COLUMN purpose TEXT NOT NULL DEFAULT 'standard'
    CHECK (purpose IN ('standard','imece_help','traveler_match'));

-- 'anonymous_advice' is deliberately not in that list. The app enum carries it
-- but no button reaches it, and accepting it here would mean storing a post
-- labelled "anonim" while the feed keeps printing the author's name next to it.
-- Anonymity is a contract about who can be identified, not a caption; it needs
-- its own decision about the author column, moderation and reporting.

-- Only traveller posts have a trip, so the trip is its own table rather than
-- four columns that are NULL on almost every row.
CREATE TABLE post_traveler_details (
  post_id UUID PRIMARY KEY REFERENCES community_posts(id) ON DELETE CASCADE,
  from_place TEXT NOT NULL,
  to_place TEXT NOT NULL,
  travel_at TIMESTAMPTZ NOT NULL,
  package_details TEXT NOT NULL,
  note TEXT
);
