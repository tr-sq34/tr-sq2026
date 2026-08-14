-- Hand ordering for live promotions.
--
-- Until now the home screen showed approved promotions newest-start-first, so
-- the only way to move a placement up was to end it and place it again with a
-- later start time - which resets its impression counters and loses the reason
-- it was approved for. An operator who has three live featured cards has an
-- opinion about which one goes first, and that opinion had nowhere to live.
--
-- NULL means "not hand-ordered", and those rows keep the old behaviour behind
-- the ordered ones. That is deliberate: adding this column must not silently
-- reshuffle placements that are already running.
ALTER TABLE promotions ADD COLUMN IF NOT EXISTS display_order INT;

-- The read path filters on status and window first, so the order column only
-- earns an index alongside them.
CREATE INDEX IF NOT EXISTS promotions_live_order_idx
  ON promotions (status, display_order NULLS LAST, starts_at DESC)
  WHERE status = 'approved';
