-- The onboarding UI offers a broad but bounded set of interests.  Keep the
-- database contract aligned with the API while limiting payload and ranking
-- cardinality to a predictable maximum.
ALTER TABLE user_onboarding
  DROP CONSTRAINT IF EXISTS user_onboarding_interests_check;

ALTER TABLE user_onboarding
  ADD CONSTRAINT user_onboarding_interests_check
  CHECK (cardinality(interests) BETWEEN 1 AND 12);
