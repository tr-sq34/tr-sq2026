CREATE TABLE IF NOT EXISTS admin_roles (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('owner','security_admin','operations_admin','content_editor','moderator','analyst','auditor')),
  granted_by UUID REFERENCES users(id) ON DELETE SET NULL,
  granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, role)
);

CREATE INDEX IF NOT EXISTS admin_roles_active_idx ON admin_roles(user_id) WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS gatework_audit_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  actor_roles TEXT[] NOT NULL,
  action TEXT NOT NULL CHECK (char_length(action) BETWEEN 3 AND 140),
  target_type TEXT NOT NULL CHECK (char_length(target_type) BETWEEN 2 AND 80),
  target_id TEXT NOT NULL CHECK (char_length(target_id) BETWEEN 1 AND 180),
  reason TEXT,
  request_id TEXT,
  cloudflare_ray_id TEXT,
  outcome TEXT NOT NULL CHECK (outcome IN ('succeeded','denied','failed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS gatework_audit_created_idx ON gatework_audit_events(created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS gatework_audit_actor_idx ON gatework_audit_events(actor_id, created_at DESC);
