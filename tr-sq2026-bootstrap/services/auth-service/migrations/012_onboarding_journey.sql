-- Onboarding grew from "city + interests" into a three-step journey: where you
-- live, when you arrived in the US and who you are here.  Everything added here
-- is additive so a client that still speaks the old contract keeps working.
ALTER TABLE user_onboarding
  ADD COLUMN IF NOT EXISTS country_code   CHAR(2) NOT NULL DEFAULT 'US',
  ADD COLUMN IF NOT EXISTS born_in_us     BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS arrived_month  SMALLINT,
  ADD COLUMN IF NOT EXISTS arrived_year   SMALLINT,
  ADD COLUMN IF NOT EXISTS origin_country CHAR(2),
  ADD COLUMN IF NOT EXISTS origin_city    TEXT;

ALTER TABLE user_onboarding
  DROP CONSTRAINT IF EXISTS user_onboarding_arrived_month_check;
ALTER TABLE user_onboarding
  ADD CONSTRAINT user_onboarding_arrived_month_check
  CHECK (arrived_month IS NULL OR arrived_month BETWEEN 1 AND 12);

ALTER TABLE user_onboarding
  DROP CONSTRAINT IF EXISTS user_onboarding_arrived_year_check;
ALTER TABLE user_onboarding
  ADD CONSTRAINT user_onboarding_arrived_year_check
  CHECK (arrived_year IS NULL OR arrived_year BETWEEN 1950 AND 2100);

ALTER TABLE user_onboarding
  DROP CONSTRAINT IF EXISTS user_onboarding_origin_city_check;
ALTER TABLE user_onboarding
  ADD CONSTRAINT user_onboarding_origin_city_check
  CHECK (origin_city IS NULL OR char_length(origin_city) BETWEEN 2 AND 100);

-- region_code stays a two-letter US state everywhere it is consumed (community
-- locality ranking, story discovery, marketplace).  A member living outside the
-- US has no state, so the column becomes nullable rather than gaining a
-- sentinel value that downstream ranking would have to special-case.
ALTER TABLE user_onboarding ALTER COLUMN region_code DROP NOT NULL;

ALTER TABLE user_onboarding
  DROP CONSTRAINT IF EXISTS user_onboarding_region_requires_us;
ALTER TABLE user_onboarding
  ADD CONSTRAINT user_onboarding_region_requires_us
  CHECK (country_code <> 'US' OR region_code IS NOT NULL);

-- The interest step is now persona based: an employer promoting a business, a
-- boss hiring, a doctor or engineer, a newcomer, someone after legal support, a
-- consultant, a student.  primary_intent is read only inside identity, so
-- widening it does not touch any projection.
ALTER TABLE user_onboarding
  DROP CONSTRAINT IF EXISTS user_onboarding_primary_intent_check;
ALTER TABLE user_onboarding
  ADD CONSTRAINT user_onboarding_primary_intent_check
  CHECK (primary_intent IN (
    'community', 'marketplace', 'networking', 'events',
    'business', 'hiring', 'job_seeking', 'professional_services',
    'newcomer', 'legal_support', 'advisory', 'education'));
