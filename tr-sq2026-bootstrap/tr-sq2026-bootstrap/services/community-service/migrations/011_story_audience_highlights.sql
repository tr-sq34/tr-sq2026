CREATE TABLE story_audience_exclusions (
  story_id UUID NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
  excluded_user_id UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (story_id, excluded_user_id)
);
CREATE INDEX story_audience_exclusions_viewer_idx
  ON story_audience_exclusions(excluded_user_id, story_id);

CREATE TABLE story_highlights (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL,
  title TEXT NOT NULL CHECK(char_length(title) BETWEEN 1 AND 40),
  visibility story_visibility NOT NULL DEFAULT 'network',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX story_highlights_owner_idx
  ON story_highlights(owner_id, created_at DESC);

CREATE TABLE story_highlight_items (
  highlight_id UUID NOT NULL REFERENCES story_highlights(id) ON DELETE CASCADE,
  story_id UUID NOT NULL REFERENCES stories(id) ON DELETE RESTRICT,
  position SMALLINT NOT NULL CHECK(position BETWEEN 0 AND 99),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(highlight_id, story_id),
  UNIQUE(highlight_id, position)
);
CREATE INDEX story_highlight_items_story_idx
  ON story_highlight_items(story_id);