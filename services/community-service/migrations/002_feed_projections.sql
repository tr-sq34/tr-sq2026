CREATE TABLE community_profile_projection (
  user_id UUID PRIMARY KEY,
  display_name TEXT NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 100),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE relationship_projection (
  viewer_id UUID NOT NULL,
  subject_id UUID NOT NULL,
  relationship TEXT NOT NULL CHECK (relationship IN ('following', 'friend')),
  active BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (viewer_id, subject_id, relationship)
);
CREATE INDEX relationship_projection_active_idx ON relationship_projection(viewer_id, subject_id)
  WHERE active;
CREATE TABLE viewer_location_projection (
  user_id UUID PRIMARY KEY,
  approximate_cell geography(Point, 4326) NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX viewer_location_projection_geo_idx ON viewer_location_projection USING GIST(approximate_cell);

-- Projection events are consumed from the identity/relationship outbox. The
-- community database never queries identity tables directly.


