-- Password reset gets its own code table rather than borrowing
-- email_verification_codes. Sharing one table would make a signup code
-- redeemable as a password reset, which turns "verify your email" into
-- "take over this account".
CREATE TABLE password_reset_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  attempts SMALLINT NOT NULL DEFAULT 0 CHECK (attempts >= 0 AND attempts <= 5),
  consumed_at TIMESTAMPTZ,
  -- Redeeming the code mints a ticket, and the ticket — not the code — is what
  -- authorises the password write. Otherwise the 59-second window would also
  -- have to cover the time a person spends choosing and confirming a password,
  -- and the only way to make that work would be to lengthen the code's life.
  ticket_hash TEXT UNIQUE,
  ticket_expires_at TIMESTAMPTZ,
  ticket_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX password_reset_codes_active_idx
  ON password_reset_codes(user_id, expires_at DESC)
  WHERE consumed_at IS NULL;

-- The confirm step looks a ticket up by hash alone, so it needs its own index;
-- the partial predicate keeps spent tickets out of the hot path.
CREATE INDEX password_reset_codes_open_ticket_idx
  ON password_reset_codes(ticket_hash)
  WHERE ticket_hash IS NOT NULL AND ticket_used_at IS NULL;
