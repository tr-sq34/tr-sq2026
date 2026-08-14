-- Yorum beğenisi: the heart under a comment, which until now was drawn from
-- nothing.
--
-- The comment sheet has always had a like button. It flipped a field in memory,
-- counted up, and forgot everything the moment the sheet closed - a number that
-- was only ever true for the one person tapping it. Now that comments themselves
-- are real (022 shipped the routes, the app was wired in the change before this
-- one), the heart is the last invented thing left on that screen.
--
-- Two tables rather than one with a `scope` column, because feed comments and
-- news comments are two tables and a single reaction table could not point at
-- both. A foreign key that deletes the reactions along with the comment is worth
-- more than the duplication it costs.
CREATE TABLE IF NOT EXISTS comment_reactions (
  comment_id UUID NOT NULL REFERENCES community_comments(id) ON DELETE CASCADE,
  actor_id UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (comment_id, actor_id)
);

CREATE TABLE IF NOT EXISTS news_comment_reactions (
  comment_id UUID NOT NULL REFERENCES news_comments(id) ON DELETE CASCADE,
  actor_id UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (comment_id, actor_id)
);

-- Only one thing is ever asked of these rows: how many are there for this
-- comment, and is the reader one of them. The primary key answers both, so
-- there is no second index here on purpose.
--
-- There is also no "who liked this comment" route, and this schema is not the
-- place to add one: a list of names under every sentence is a map of who agrees
-- with whom, and counting is all the screen needs.
