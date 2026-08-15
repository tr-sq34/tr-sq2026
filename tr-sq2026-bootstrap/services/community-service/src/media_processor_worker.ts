import { createHash, timingSafeEqual } from 'node:crypto';
import sharp from 'sharp';
import { createDatabasePool } from './database.js';
import { downloadMediaBlob, uploadMediaBlob, deleteMediaBlob } from './infrastructure/azureBlob.js';

const required = (key: string) => {
  const value = process.env[key];
  if (!value) throw new Error(`Missing ${key}`);
  return value;
};

required('AZURE_STORAGE_ACCOUNT_NAME');
required('AZURE_STORAGE_ACCOUNT_KEY');
required('AZURE_MEDIA_CONTAINER_NAME');

const db = createDatabasePool();
const pollMilliseconds = Number(process.env.MEDIA_PROCESSOR_POLL_MS ?? 3000);
const maxPixels = 40_000_000;

type Job = {
  jobId: string;
  mediaId: string;
  quarantineKey: string;
  contentType: string;
  expectedSizeBytes: string;
  expectedSha256: Buffer;
};

async function claimJob(): Promise<Job | null> {
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    // The joins hang off n, not j. Postgres builds the FROM list before the
    // update target is in scope, so `JOIN ... ON s.media_id=j.media_id` is
    // rejected outright with `invalid reference to FROM-clause entry for table
    // "j"` - the worker threw that on its first poll and never started. The CTE
    // carries media_id out so the joins have something legal to hang off.
    //
    // FOR UPDATE OF j, not a bare FOR UPDATE: the bare form also locks the
    // media_assets row this job happens to join to, which nothing here is
    // claiming and which blocks unrelated writers.
    const result = await client.query<Job>(`
      WITH next_job AS (
        SELECT j.id, j.media_id
        FROM media_processing_jobs j
        JOIN media_assets m ON m.id=j.media_id
        WHERE j.job_type='scan'
          AND (j.status='queued' OR (j.status='running' AND j.created_at < now()-interval '15 minutes'))
          AND m.status='scanning'
        ORDER BY j.created_at
        FOR UPDATE OF j SKIP LOCKED
        LIMIT 1
      )
      UPDATE media_processing_jobs j
      SET status='running', attempts=j.attempts+1
      FROM next_job n
      JOIN media_upload_sessions s ON s.media_id=n.media_id
      JOIN media_assets m ON m.id=n.media_id
      WHERE j.id=n.id
      RETURNING j.id AS "jobId",m.id AS "mediaId",s.quarantine_key AS "quarantineKey",s.content_type AS "contentType",s.expected_size_bytes AS "expectedSizeBytes",s.expected_sha256 AS "expectedSha256"
    `);
    await client.query('COMMIT');
    return result.rows[0] ?? null;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function reject(job: Job, reason: string) {
  await db.query("UPDATE media_assets SET status='rejected' WHERE id=$1 AND status='scanning'", [job.mediaId]);
  await db.query("UPDATE media_processing_jobs SET status='failed',finished_at=now() WHERE id=$1", [job.jobId]);
  await deleteMediaBlob(job.quarantineKey).catch(() => undefined);
  console.warn(JSON.stringify({ event: 'media_rejected', reason, jobId: job.jobId }));
}

function isAllowedImage(buffer: Buffer, contentType: string) {
  const jpeg = buffer.subarray(0, 3).equals(Buffer.from([0xff, 0xd8, 0xff]));
  const png = buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  const webp = buffer.subarray(0, 4).toString('ascii') === 'RIFF' && buffer.subarray(8, 12).toString('ascii') === 'WEBP';
  return (contentType === 'image/jpeg' && jpeg) ||
    (contentType === 'image/png' && png) ||
    (contentType === 'image/webp' && webp);
}

/**
 * Depodaki baytlar, istemcinin yükleme izni isterken bildirdiği özetle aynı mı.
 *
 * Bu kontrol daha önce API tarafında, /media/uploads/complete içinde yapılmaya
 * çalışılıyordu; orada baytlar yok, yalnızca blobun özellikleri var ve Azure
 * oradan SHA-256 vermiyor. Kontrolün doğru yeri burası: dosyayı zaten indiren,
 * güvenli nesneyi üretmeden hemen önceki adım. Böylece taranan baytlarla beyan
 * edilen baytlar arasında boşluk kalmıyor.
 */
function matchesDeclaredDigest(source: Buffer, expected: Buffer) {
  const actual = createHash('sha256').update(source).digest();
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

async function processJob(job: Job) {
  try {
    const source = await downloadMediaBlob(job.quarantineKey);
    if (source.length !== Number(job.expectedSizeBytes)) {
      throw new Error('Stored object has an unexpected size');
    }
    if (!matchesDeclaredDigest(source, job.expectedSha256)) {
      throw new Error('Stored object does not match the declared SHA-256');
    }
    if (!isAllowedImage(source, job.contentType)) throw new Error('Magic bytes do not match declared image type');

    const image = sharp(source, { failOn: 'error', limitInputPixels: maxPixels }).rotate();
    const metadata = await image.metadata();
    if (!metadata.width || !metadata.height || metadata.width * metadata.height > maxPixels) {
      throw new Error('Image dimensions are unsafe');
    }
    const sanitized = await image
      .resize({ width: 2560, height: 2560, fit: 'inside', withoutEnlargement: true })
      .webp({ quality: 88, effort: 4 })
      .toBuffer();
    const safeKey = `uploads/safe/${job.mediaId}.webp`;
    await uploadMediaBlob(safeKey, sanitized, 'image/webp');

    const client = await db.connect();
    try {
      await client.query('BEGIN');
      await client.query("UPDATE media_assets SET status='ready',safe_url=$2,thumbnail_url=$2 WHERE id=$1 AND status='scanning'", [job.mediaId, safeKey]);
      await client.query("UPDATE media_processing_jobs SET status='succeeded',finished_at=now() WHERE id=$1", [job.jobId]);
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
    await deleteMediaBlob(job.quarantineKey);
    console.info(JSON.stringify({ event: 'media_sanitized', jobId: job.jobId }));
  } catch (error) {
    await reject(job, error instanceof Error ? error.message : 'unknown');
  }
}

async function run() {
  for (;;) {
    const job = await claimJob();
    if (job) await processJob(job);
    else await new Promise((resolve) => setTimeout(resolve, pollMilliseconds));
  }
}

run().catch((error) => {
  console.error(JSON.stringify({ event: 'media_processor_fatal', error: error instanceof Error ? error.message : 'unknown' }));
  process.exit(1);
});
