-- A media object has one durable security-processing job per stage. This
-- keeps repeated client completion calls idempotent and prevents duplicate
-- processors from publishing the same object twice.
CREATE UNIQUE INDEX IF NOT EXISTS media_processing_jobs_media_stage_unique
  ON media_processing_jobs (media_id, job_type);
