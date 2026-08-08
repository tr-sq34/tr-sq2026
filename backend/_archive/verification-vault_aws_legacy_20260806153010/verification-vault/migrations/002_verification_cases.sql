CREATE TYPE verification_case_status AS ENUM ('draft', 'uploading', 'scanning', 'ready_for_review', 'approved', 'rejected', 'expired');
CREATE TYPE verification_document_kind AS ENUM ('passport', 'us_driver_license', 'government_id', 'selfie');

CREATE TABLE verification_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id UUID NOT NULL,
  status verification_case_status NOT NULL DEFAULT 'draft',
  consent_version TEXT NOT NULL,
  consented_at TIMESTAMPTZ NOT NULL,
  retention_expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + interval '30 days',
  decision_reason_code TEXT,
  reviewed_by UUID,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX verification_case_one_open_idx ON verification_cases(subject_id)
  WHERE status IN ('draft', 'uploading', 'scanning', 'ready_for_review');

CREATE TABLE verification_uploads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES verification_cases(id) ON DELETE CASCADE,
  document_kind verification_document_kind NOT NULL,
  object_key TEXT NOT NULL UNIQUE,
  expected_sha256 BYTEA NOT NULL CHECK (octet_length(expected_sha256) = 32),
  expected_size_bytes BIGINT NOT NULL CHECK (expected_size_bytes BETWEEN 1024 AND 26214400),
  content_type TEXT NOT NULL CHECK (content_type IN ('image/jpeg', 'image/png', 'application/pdf')),
  uploaded_at TIMESTAMPTZ,
  scan_state TEXT NOT NULL DEFAULT 'awaiting_upload' CHECK (scan_state IN ('awaiting_upload', 'queued', 'clean', 'rejected')),
  idempotency_key UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (case_id, document_kind),
  UNIQUE (case_id, idempotency_key)
);

CREATE TABLE verification_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  topic TEXT NOT NULL,
  payload JSONB NOT NULL,
  available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX verification_outbox_pending_idx ON verification_outbox(available_at) WHERE published_at IS NULL;
