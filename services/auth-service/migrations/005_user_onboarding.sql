-- Identity owns the user-controlled onboarding preferences. Community receives
-- an explicit, minimal projection later; it never queries Identity directly.
CREATE TABLE user_onboarding (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  city TEXT NOT NULL CHECK (char_length(city) BETWEEN 2 AND 100),
  region_code TEXT NOT NULL CHECK (region_code ~ '^[A-Z]{2}$'),
  interests TEXT[] NOT NULL CHECK (cardinality(interests) BETWEEN 1 AND 8),
  primary_intent TEXT NOT NULL CHECK (primary_intent IN ('community', 'marketplace', 'networking', 'events')),
  completed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
