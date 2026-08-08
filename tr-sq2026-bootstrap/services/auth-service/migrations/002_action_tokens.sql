CREATE TYPE account_action_kind AS ENUM ('verify_email', 'reset_password');

CREATE TABLE account_action_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind account_action_kind NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX account_action_tokens_lookup_idx ON account_action_tokens(token_hash, kind);
