CREATE TABLE IF NOT EXISTS gatework_command_dedup (
  actor_id UUID NOT NULL,
  idempotency_key UUID NOT NULL,
  command_type TEXT NOT NULL,
  result_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (actor_id, idempotency_key, command_type)
);

CREATE TABLE IF NOT EXISTS gatework_operation_audit_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id UUID NOT NULL,
  actor_roles TEXT[] NOT NULL,
  action TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  reason TEXT,
  request_id TEXT,
  cloudflare_ray_id TEXT,
  outcome TEXT NOT NULL CHECK (outcome IN ('succeeded','denied','failed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gatework_operation_audit_created_idx ON gatework_operation_audit_events(created_at DESC, id DESC);
