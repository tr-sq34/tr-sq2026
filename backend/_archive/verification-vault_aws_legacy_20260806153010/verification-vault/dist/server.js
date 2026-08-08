import { randomUUID } from 'node:crypto';
import { HeadObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { SendMessageCommand, SQSClient } from '@aws-sdk/client-sqs';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import Fastify from 'fastify';
import { jwtVerify } from 'jose';
import pg from 'pg';
import { z } from 'zod';
const required = (name) => { const value = process.env[name]; if (!value)
    throw new Error(`Missing ${name}`); return value; };
const db = new pg.Pool({ connectionString: required('DATABASE_URL'), max: 10, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: true } : undefined });
const jwtKey = new TextEncoder().encode(required('JWT_SECRET'));
const issuer = required('JWT_ISSUER');
const audience = required('JWT_AUDIENCE');
const bucket = required('VERIFICATION_QUARANTINE_BUCKET');
const queueUrl = required('DOCUMENT_SCAN_QUEUE_URL');
const s3 = new S3Client({ region: required('AWS_REGION') });
const sqs = new SQSClient({ region: required('AWS_REGION') });
const app = Fastify({ logger: { redact: ['req.headers.authorization', 'req.body'] } });
const presignSchema = z.object({ documentKind: z.enum(['passport', 'us_driver_license', 'government_id', 'selfie']), contentType: z.enum(['image/jpeg', 'image/png', 'application/pdf']), sizeBytes: z.number().int().min(1024).max(26214400), sha256: z.string().regex(/^[A-Fa-f0-9]{64}$/), consentVersion: z.string().min(1).max(64), idempotencyKey: z.string().uuid() });
const completeSchema = z.object({ idempotencyKey: z.string().uuid() });
async function subjectId(headers) {
    const raw = headers.authorization?.replace(/^Bearer\s+/i, '');
    if (!raw)
        throw new Error('UNAUTHORIZED');
    const verified = await jwtVerify(raw, jwtKey, { issuer, audience });
    if (!verified.payload.sub)
        throw new Error('UNAUTHORIZED');
    return verified.payload.sub;
}
app.post('/v1/verification/documents/presign', async (request, reply) => {
    try {
        const subject = await subjectId(request.headers);
        const input = presignSchema.parse(request.body);
        const client = await db.connect();
        try {
            await client.query('BEGIN');
            const existing = await client.query('SELECT id,object_key FROM verification_uploads WHERE case_id IN (SELECT id FROM verification_cases WHERE subject_id=$1 AND status IN (\'draft\',\'uploading\')) AND idempotency_key=$2', [subject, input.idempotencyKey]);
            let upload = existing.rows[0];
            if (!upload) {
                const openCase = await client.query('SELECT id FROM verification_cases WHERE subject_id=$1 AND status IN (\'draft\',\'uploading\') ORDER BY created_at DESC LIMIT 1 FOR UPDATE', [subject]);
                const caseId = openCase.rows[0]?.id ?? (await client.query('INSERT INTO verification_cases(subject_id,status,consent_version,consented_at) VALUES($1,\'uploading\',$2,now()) RETURNING id', [subject, input.consentVersion])).rows[0].id;
                const id = randomUUID();
                const objectKey = `cases/${caseId}/${id}`;
                upload = (await client.query('INSERT INTO verification_uploads(id,case_id,document_kind,object_key,expected_sha256,expected_size_bytes,content_type,idempotency_key) VALUES($1,$2,$3,$4,decode($5,\'hex\'),$6,$7,$8) RETURNING id,object_key', [id, caseId, input.documentKind, objectKey, input.sha256, input.sizeBytes, input.contentType, input.idempotencyKey])).rows[0];
            }
            await client.query('COMMIT');
            const url = await getSignedUrl(s3, new PutObjectCommand({ Bucket: bucket, Key: upload.object_key, ContentType: input.contentType, ContentLength: input.sizeBytes, ChecksumSHA256: Buffer.from(input.sha256, 'hex').toString('base64'), ServerSideEncryption: 'aws:kms' }), { expiresIn: 300 });
            return { data: { documentId: upload.id, uploadUrl: url, expiresInSeconds: 300 } };
        }
        catch (error) {
            await client.query('ROLLBACK');
            throw error;
        }
        finally {
            client.release();
        }
    }
    catch {
        return reply.code(401).send({ error: { code: 'UNAUTHORIZED', message: 'İşlem doğrulanamadı.' } });
    }
});
app.post('/v1/verification/documents/:id/complete', async (request, reply) => {
    try {
        const subject = await subjectId(request.headers);
        const input = completeSchema.parse(request.body);
        const id = z.string().uuid().parse(request.params.id);
        const pending = await db.query('SELECT u.id,u.case_id,u.object_key,u.expected_size_bytes,u.content_type,u.expected_sha256 FROM verification_uploads u JOIN verification_cases c ON c.id=u.case_id WHERE u.id=$1 AND c.subject_id=$2 AND u.idempotency_key=$3', [id, subject, input.idempotencyKey]);
        const upload = pending.rows[0];
        if (!upload)
            return reply.code(404).send({ error: { code: 'UPLOAD_NOT_FOUND', message: 'Yükleme bulunamadı.' } });
        const object = await s3.send(new HeadObjectCommand({ Bucket: bucket, Key: upload.object_key, ChecksumMode: 'ENABLED' }));
        const expectedChecksum = upload.expected_sha256.toString('base64');
        if (object.ContentLength !== upload.expected_size_bytes || object.ContentType !== upload.content_type || object.ChecksumSHA256 !== expectedChecksum) {
            return reply.code(400).send({ error: { code: 'UPLOAD_INTEGRITY_FAILED', message: 'Yüklenen dosya doğrulanamadı.' } });
        }
        const updated = await db.query('UPDATE verification_uploads SET uploaded_at=COALESCE(uploaded_at,now()),scan_state=\'queued\' WHERE id=$1 RETURNING id,case_id', [upload.id]);
        const row = updated.rows[0];
        await sqs.send(new SendMessageCommand({ QueueUrl: queueUrl, MessageBody: JSON.stringify({ uploadId: row.id, caseId: row.case_id }) }));
        await db.query('UPDATE verification_cases SET status=\'scanning\',updated_at=now() WHERE id=$1 AND status IN (\'draft\',\'uploading\')', [row.case_id]);
        return reply.code(202).send({ data: { status: 'scanning' } });
    }
    catch {
        return reply.code(401).send({ error: { code: 'UNAUTHORIZED', message: 'İşlem doğrulanamadı.' } });
    }
});
app.get('/v1/verification/status', async (request, reply) => {
    try {
        const subject = await subjectId(request.headers);
        const result = await db.query('SELECT status,reviewed_at FROM verification_cases WHERE subject_id=$1 ORDER BY created_at DESC LIMIT 1', [subject]);
        return { data: result.rows[0] ?? { status: 'not_started' } };
    }
    catch {
        return reply.code(401).send({ error: { code: 'UNAUTHORIZED', message: 'İşlem doğrulanamadı.' } });
    }
});
await app.listen({ port: Number(process.env.PORT ?? 8090), host: '0.0.0.0' });
