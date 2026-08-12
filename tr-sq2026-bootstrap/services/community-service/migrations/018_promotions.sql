-- Tanitim Yap: sponsored placements a member asks for and an operator approves.
--
-- The home screen has three slots that were hardcoded in `discover_screen.dart`
-- - the featured story card, the in-app banner and the "Sana Ozel One Cikanlar"
-- row. All three are the same thing wearing different clothes: a piece of media
-- with a title, a link, an audience and a date range, shown because somebody
-- decided it should be. So they are one table with a `placement` column rather
-- than three tables that would drift apart the first time one of them gained a
-- field.
--
-- No money changes hands in this migration and none is modelled: there is no
-- price, no invoice, no payment reference. A request is approved on its merits
-- and the pricing question is deliberately left to a later phase, because a
-- half-modelled payment column is worse than none at all.

CREATE TABLE IF NOT EXISTS promotions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- The member who asked for it, or the system account when an operator places
  -- one straight from the console. Same column for both: the audit trail should
  -- not have to look in two places to answer "whose promotion was this".
  owner_id UUID NOT NULL,
  placement TEXT NOT NULL CHECK (placement IN ('story_slot', 'app_banner', 'featured_card')),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 3 AND 120),
  -- One line under the title. Optional because a banner is often just an image;
  -- the featured cards are the ones that actually need it.
  subtitle TEXT CHECK (subtitle IS NULL OR char_length(subtitle) BETWEEN 1 AND 200),
  -- Media id, not a URL - the rule the whole service follows. The service
  -- resolves it through `media_assets` and only ever emits a scanned `safe_url`,
  -- so a promotion cannot smuggle an unscanned image onto the home screen.
  media_id UUID REFERENCES media_assets(id),
  -- Where the tap goes. Either somewhere inside the app (a post, a listing, an
  -- article) or out to the web; both are stored as a plain string plus a kind so
  -- the app never has to guess how to open it. NULL is a placement that is only
  -- there to be looked at.
  target_kind TEXT CHECK (target_kind IS NULL OR target_kind IN ('post', 'listing', 'news', 'event', 'external')),
  target_value TEXT CHECK (target_value IS NULL OR char_length(target_value) BETWEEN 1 AND 500),
  -- Audience. NULL region means everyone, which is the normal case; a city
  -- without a region is not, so the pair is checked together.
  region_code CHAR(2),
  city TEXT CHECK (city IS NULL OR char_length(city) BETWEEN 2 AND 80),
  CONSTRAINT promotions_city_needs_region CHECK (city IS NULL OR region_code IS NOT NULL),
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  CONSTRAINT promotions_window_ordered CHECK (ends_at > starts_at),
  -- Only three states, and every one of them is something a person did:
  -- 'pending' waits for a decision, 'approved' passed review, 'rejected' did
  -- not, 'ended' was pulled early. Whether an approved promotion is *live* is
  -- not stored, because it is entirely a function of the clock and the window
  -- above - a stored `live` flag would be a second source of truth that only
  -- something like a cron job could keep honest, and it would be wrong for the
  -- whole interval between the window opening and that job running.
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'ended')),
  -- Shown to the member verbatim on their own request list. A rejection nobody
  -- can read is how a member ends up submitting the same thing four times.
  decision_reason TEXT CHECK (decision_reason IS NULL OR char_length(decision_reason) BETWEEN 3 AND 500),
  decided_by UUID,
  decided_at TIMESTAMPTZ,
  -- Why the member wants it. Not shown in the app - it is what the reviewer
  -- reads before deciding.
  request_note TEXT CHECK (request_note IS NULL OR char_length(request_note) BETWEEN 3 AND 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The query the home screen runs on every open: approved placements whose
-- window contains now(). The partial index keeps the pending and rejected rows -
-- which will outnumber the approved ones - out of that path entirely.
CREATE INDEX IF NOT EXISTS promotions_active_idx
  ON promotions (placement, starts_at DESC)
  WHERE status = 'approved';

-- The console's queue: oldest waiting request first.
CREATE INDEX IF NOT EXISTS promotions_pending_idx
  ON promotions (created_at ASC)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS promotions_owner_idx
  ON promotions (owner_id, created_at DESC);

-- Counted per day, not per event. A row per impression would be the largest
-- table in the service within a week and would answer no question that
-- "how did this placement do on Tuesday" does not already answer. The daily
-- grain also means the owner's numbers cannot be turned back into a log of who
-- looked at what and when.
CREATE TABLE IF NOT EXISTS promotion_impressions (
  promotion_id UUID NOT NULL REFERENCES promotions(id) ON DELETE CASCADE,
  day DATE NOT NULL,
  impressions BIGINT NOT NULL DEFAULT 0,
  clicks BIGINT NOT NULL DEFAULT 0,
  PRIMARY KEY (promotion_id, day)
);
