CREATE TABLE media_upload_sessions (id UUID PRIMARY KEY DEFAULT gen_random_uuid(),media_id UUID NOT NULL UNIQUE REFERENCES media_assets(id) ON DELETE CASCADE,owner_id UUID NOT NULL,quarantine_key TEXT NOT NULL UNIQUE,expected_sha256 BYTEA NOT NULL CHECK(octet_length(expected_sha256)=32),expected_size_bytes BIGINT NOT NULL CHECK(expected_size_bytes BETWEEN 1 AND 104857600),content_type TEXT NOT NULL,expires_at TIMESTAMPTZ NOT NULL,completed_at TIMESTAMPTZ,created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX media_upload_sessions_expiry_idx ON media_upload_sessions(expires_at) WHERE completed_at IS NULL;


