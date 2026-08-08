-- DOCUMENT_VAULT_DATABASE only. This isolated database is not reachable from
-- the community or marketplace services. File bytes remain in a private object
-- store bucket; this table contains encrypted metadata and immutable audit rows.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE verification_document_status AS ENUM (
  'uploaded', 'scanning', 'pending_review', 'approved', 'rejected', 'deleted'
);

CREATE TABLE verification_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id UUID NOT NULL,
  purpose TEXT NOT NULL CHECK (purpose IN ('identity', 'membership', 'business')),
  status verification_document_status NOT NULL DEFAULT 'uploaded',
  object_key TEXT NOT NULL UNIQUE,
  object_version TEXT NOT NULL,
  content_sha256 BYTEA NOT NULL CHECK (octet_length(content_sha256) = 32),
  wrapped_data_key BYTEA NOT NULL,
  kms_key_reference TEXT NOT NULL,
  mime_type TEXT NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png', 'application/pdf')),
  size_bytes BIGINT NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 26214400),
  retention_until TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE verification_document_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL REFERENCES verification_documents(id),
  actor_id UUID,
  action TEXT NOT NULL CHECK (action IN ('uploaded', 'scanned', 'viewed', 'approved', 'rejected', 'deleted')),
  request_id UUID NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  details JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX verification_document_subject_idx ON verification_documents(subject_id, created_at DESC);
CREATE INDEX verification_document_audit_idx ON verification_document_audit(document_id, occurred_at DESC);

-- Vault service grants reviewers time-limited, watermarked render access only
-- after policy authorization. It never issues a public object URL.
