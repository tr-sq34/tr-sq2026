-- Two coordinate stores that nothing has ever written.
--
-- community_posts.location_cell and viewer_location_projection came from the
-- first feed sketch, where "yakınındakiler" meant a 50km radius. Migration 008
-- settled the opposite rule - locality is a chosen city/state preference, never
-- a continuous exact trail - and the writers for these two were never built.
-- The feed query kept asking them for a radius, which is why that tab was empty
-- for everybody, for as long as it existed. The query now reads the chosen
-- state instead.
--
-- They are dropped rather than left empty because an unused coordinate column
-- is an invitation: the next person to open this schema reads it as permission
-- to start filling it. The one place this service keeps an exact point is
-- sos_alerts, where a member hands it over to ask for help and it is deleted
-- when the call closes.
--
-- Both are empty: community_posts.location_cell was never in any INSERT, and
-- viewer_location_projection has no writer at all. Nothing is lost here.
DROP INDEX IF EXISTS community_posts_location_idx;
ALTER TABLE community_posts DROP COLUMN IF EXISTS location_cell;
DROP TABLE IF EXISTS viewer_location_projection;
