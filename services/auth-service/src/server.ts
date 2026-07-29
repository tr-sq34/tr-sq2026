import { createHash, createHmac, createPublicKey, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';
import argon2 from 'argon2';
import Fastify from 'fastify';
import helmet from '@fastify/helmet';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import { GetPublicKeyCommand, KMSClient, SignCommand } from '@aws-sdk/client-kms';
import { InvokeCommand, LambdaClient } from '@aws-sdk/client-lambda';
import { SendMessageCommand, SQSClient } from '@aws-sdk/client-sqs';
import { exportJWK, importSPKI, jwtVerify } from 'jose';
import { generateAuthenticationOptions, generateRegistrationOptions, verifyAuthenticationResponse, verifyRegistrationResponse } from '@simplewebauthn/server';
import type { AuthenticationResponseJSON, RegistrationResponseJSON } from '@simplewebauthn/server';
import pg from 'pg';
import { z } from 'zod';
import { databaseConnectionString, databaseSslOptions } from './database.js';

const required = (name: string) => {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
};

const db = new pg.Pool({ connectionString: databaseConnectionString(), max: 10, ssl: databaseSslOptions() });
const issuer = required('JWT_ISSUER');
const audience = required('JWT_AUDIENCE');
const jwtSigningKeyId = required('JWT_SIGNING_KMS_KEY_ID');
const jwtKeyId = required('JWT_KEY_ID');
const emailCodeHmacKey = required('EMAIL_CODE_HMAC_SECRET');
const rpID = required('WEBAUTHN_RP_ID');
const expectedOrigin = required('WEBAUTHN_ORIGIN');
const emailFrom = required('EMAIL_FROM');
const authActionBaseUrl = required('AUTH_ACTION_BASE_URL');
const emailRelayFunctionName = required('EMAIL_RELAY_FUNCTION_NAME');
const passwordSafetyFunctionName = required('PASSWORD_SAFETY_FUNCTION_NAME');
const emailRelay = new LambdaClient({});
const kms = new KMSClient({});
const communityProjectionQueueUrl = process.env.COMMUNITY_PROFILE_PROJECTION_QUEUE_URL;
const communityOutbox = new SQSClient({});
const app = Fastify({ logger: { redact: ['req.headers.authorization', 'req.body.password', 'req.body.refreshToken'] } });

const registerSchema = z.object({ name: z.string().trim().min(2).max(100), email: z.string().trim().email().max(254), password: z.string().min(12).max(128) });
const loginSchema = z.object({ email: z.string().trim().email().max(254), password: z.string().min(1).max(128) });
const refreshSchema = z.object({ refreshToken: z.string().min(32).max(512) });
const logoutSchema = z.object({ refreshToken: z.string().min(32).max(512) });
const actionSchema = z.object({ token: z.string().min(32).max(512) });
const emailSchema = z.object({ email: z.string().trim().email().max(254) });
const emailVerificationCodeSchema = emailSchema.extend({ code: z.string().regex(/^\d{6}$/) });
const resetSchema = actionSchema.extend({ password: z.string().min(12).max(128) });
const webauthnSchema = z.object({ credential: z.record(z.unknown()) });
const onboardingSchema = z.object({
  city: z.string().trim().min(2).max(100),
  regionCode: z.string().trim().regex(/^[A-Za-z]{2}$/),
  interests: z.array(z.string().trim().min(2).max(40)).min(1).max(8).transform((values) => [...new Set(values.map((value) => value.toLocaleLowerCase('tr-TR')))]),
  primaryIntent: z.enum(['community', 'marketplace', 'networking', 'events']),
});

const opaqueToken = () => randomBytes(48).toString('base64url');
const hashOpaque = (token: string) => createHash('sha256').update(token).digest('hex');
const createEmailVerificationCode = () => randomInt(0, 1000000).toString().padStart(6, '0');
const hashEmailVerificationCode = (userId: string, code: string) =>
  createHmac('sha256', emailCodeHmacKey).update(`${userId}:${code}`).digest('hex');
let dummyPasswordHash: Promise<string> | undefined;

function passwordError(password: string, identity: { email: string; name: string }) {
  if (password.length < 12 || password.length > 128) return 'Parola 12–128 karakter olmalıdır.';
  const normalizedPassword = password.toLocaleLowerCase('en-US');
  const localPart = identity.email.split('@')[0]?.toLocaleLowerCase('en-US') ?? '';
  const normalizedName = identity.name.replaceAll(/\s+/g, '').toLocaleLowerCase('en-US');
  if ((localPart.length >= 3 && normalizedPassword.includes(localPart)) ||
      (normalizedName.length >= 3 && normalizedPassword.includes(normalizedName))) {
    return 'Parola e-posta veya ad bilgisini içeremez.';
  }
  return null;
}

async function hashPassword(password: string) {
  return argon2.hash(password, { type: argon2.argon2id, memoryCost: 19456, timeCost: 2, parallelism: 1 });
}

async function verifyPassword(password: string, storedHash?: string) {
  // Avoid a measurable user-exists timing branch. The dummy hash is generated
  // once and is never persisted or logged.
  dummyPasswordHash ??= hashPassword('not-a-real-password-used-only-for-timing');
  return argon2.verify(storedHash ?? await dummyPasswordHash, password);
}

type BreachCheckResult = 'safe' | 'breached' | 'unavailable';

async function checkBreachedPassword(password: string): Promise<BreachCheckResult> {
  const mode = process.env.PWNED_PASSWORDS_MODE ??
    (process.env.NODE_ENV === 'production' ? 'required' : 'off');
  if (mode === 'off') return 'safe';
  const digest = createHash('sha1').update(password, 'utf8').digest('hex').toUpperCase();
  const prefix = digest.slice(0, 5);
  const suffix = digest.slice(5);
  try {
    const result = await emailRelay.send(new InvokeCommand({ FunctionName: passwordSafetyFunctionName, InvocationType: 'RequestResponse', Payload: new TextEncoder().encode(JSON.stringify({ prefix, suffix })) }));
    if (result.FunctionError || !result.Payload) {
      app.log.error(
        {
          passwordSafetyFunctionName,
          functionError: result.FunctionError,
          statusCode: result.StatusCode,
        },
        'Password safety Lambda returned an error',
      );
      return 'unavailable';
    }
    const payload = JSON.parse(new TextDecoder().decode(result.Payload)) as { breached?: boolean };
    return payload.breached === true ? 'breached' : 'safe';
  } catch (error) {
    app.log.error(
      { err: error, passwordSafetyFunctionName },
      'Password safety Lambda invocation failed',
    );
    return 'unavailable';
  }
}

async function validateNewPassword(password: string, identity: { email: string; name: string }) {
  const policyError = passwordError(password, identity);
  if (policyError) return { code: 'WEAK_PASSWORD', message: policyError };
  const breachResult = await checkBreachedPassword(password);
  if (breachResult === 'breached') return { code: 'WEAK_PASSWORD', message: 'Bu parola bilinen veri sızıntılarında yer alıyor.' };
  if (breachResult === 'unavailable') return { code: 'PASSWORD_CHECK_UNAVAILABLE', message: 'Parola güvenlik kontrolü şu anda tamamlanamadı.' };
  return null;
}
const kmsPublicKey = await (async () => {
  const response = await kms.send(new GetPublicKeyCommand({ KeyId: jwtSigningKeyId }));
  if (!response.PublicKey) throw new Error('KMS signing key has no public key');
  const key = createPublicKey({ key: Buffer.from(response.PublicKey), format: 'der', type: 'spki' });
  return importSPKI(key.export({ format: 'pem', type: 'spki' }).toString(), 'RS256');
})();

const jwk = await exportJWK(kmsPublicKey);
const publicJwk = { ...jwk, kid: jwtKeyId, use: 'sig', alg: 'RS256' };

async function signAccessToken(user: { id: string }) {
  const now = Math.floor(Date.now() / 1000);
  const protectedHeader = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT', kid: jwtKeyId })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({
    sub: user.id,
    iss: issuer,
    aud: audience,
    iat: now,
    exp: now + (15 * 60),
  })).toString('base64url');
  const signingInput = `${protectedHeader}.${payload}`;
  const signature = await kms.send(new SignCommand({
    KeyId: jwtSigningKeyId,
    Message: Buffer.from(signingInput),
    MessageType: 'RAW',
    SigningAlgorithm: 'RSASSA_PKCS1_V1_5_SHA_256',
  }));
  if (!signature.Signature) throw new Error('KMS did not return a JWT signature');
  return `${signingInput}.${Buffer.from(signature.Signature).toString('base64url')}`;
}

// The database is the source of truth: an onboarding update first commits an
// outbox record, then this publisher delivers it to Community. A crash between
// those two operations is safe because pending records are retried. Consumers
// use the event id as their idempotency key, so duplicate SQS delivery is safe.
async function publishCommunityProfileOutbox() {
  if (!communityProjectionQueueUrl) return;
  const pending = await db.query<{ id: string; payload: unknown }>(
    `SELECT id,payload FROM identity_outbox_events
     WHERE published_at IS NULL AND event_type='community.profile_upserted'
     ORDER BY created_at ASC LIMIT 20`,
  );
  for (const event of pending.rows) {
    try {
      await communityOutbox.send(new SendMessageCommand({
        QueueUrl: communityProjectionQueueUrl,
        MessageBody: JSON.stringify({ eventId: event.id, eventType: 'community.profile_upserted', payload: event.payload }),
      }));
      await db.query('UPDATE identity_outbox_events SET published_at=now(),attempts=attempts+1 WHERE id=$1 AND published_at IS NULL', [event.id]);
    } catch (error) {
      await db.query('UPDATE identity_outbox_events SET attempts=attempts+1 WHERE id=$1', [event.id]);
      app.log.warn({ err: error, eventId: event.id }, 'Community profile outbox delivery deferred');
    }
  }
}

async function issueSession(user: { id: string; email: string }, existingFamilyId?: string) {
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const familyId = existingFamilyId ?? (await client.query<{ id: string }>('INSERT INTO refresh_token_families(user_id) VALUES($1) RETURNING id', [user.id])).rows[0]!.id;
    const refreshToken = opaqueToken();
    await client.query('INSERT INTO refresh_tokens(family_id, token_hash, expires_at) VALUES($1,$2,now() + interval \'30 days\')', [familyId, hashOpaque(refreshToken)]);
    await client.query('COMMIT');
    return { accessToken: await signAccessToken(user), refreshToken };
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}

async function createActionToken(userId: string, kind: 'verify_email' | 'reset_password', ttl: string) {
  const token = opaqueToken();
  await db.query('INSERT INTO account_action_tokens(user_id, kind, token_hash, expires_at) VALUES($1,$2,$3,now() + $4::interval)', [userId, kind, hashOpaque(token), ttl]);
  // Send through a queue-backed transactional email provider. Never log or
  // return the raw token in API responses; this event carries it only to the
  // delivery boundary in a production deployment.
  return token;
}

async function deliverActionLink(email: string, kind: 'verify_email' | 'reset_password', token: string) {
  const url = new URL(authActionBaseUrl);
  url.searchParams.set('action', kind);
  url.searchParams.set('token', token);
  const subject = kind === 'verify_email'
    ? 'TurkSquare e-posta doğrulaması'
    : 'TurkSquare parola sıfırlama';
  const instruction = kind === 'verify_email'
    ? 'E-posta adresinizi doğrulamak için bağlantıyı açın.'
    : 'Parolanızı sıfırlamak için bağlantıyı açın.';
  try {
    await emailRelay.send(new InvokeCommand({
      FunctionName: emailRelayFunctionName,
      InvocationType: 'Event',
      Payload: new TextEncoder().encode(JSON.stringify({
        recipient: email,
        from: emailFrom,
        subject,
        text: `${instruction}\n\n${url.toString()}\n\nBu isteği siz yapmadıysanız bu e-postayı yok sayın.`,
        category: kind,
        idempotencyKey: `${kind}:${hashOpaque(token)}`,
      })),
    }));
  } catch (error) {
    // Tokens and recipient addresses must never be added to application logs.
    app.log.error({ err: error, kind }, 'Identity transactional email delivery failed');
    throw new Error('Email delivery failed');
  }
}

async function deliverEmailVerificationCode(email: string, code: string) {
  try {
    await emailRelay.send(new InvokeCommand({
      FunctionName: emailRelayFunctionName,
      InvocationType: 'Event',
      Payload: new TextEncoder().encode(JSON.stringify({
        recipient: email,
        from: emailFrom,
        subject: 'TurkSquare doğrulama kodunuz',
        text: `TurkSquare doğrulama kodunuz: ${code}\n\nBu kod 59 saniye geçerlidir. Kodu kimseyle paylaşmayın. Bu isteği siz yapmadıysanız bu e-postayı yok sayın.`,
        category: 'verify_email_code',
        idempotencyKey: `verify_email_code:${hashEmailVerificationCode(email, code)}`,
      })),
    }));
  } catch (error) {
    app.log.error({ err: error, category: 'verify_email_code' }, 'Identity verification code delivery failed');
    throw new Error('Email delivery failed');
  }
}

async function issueEmailVerificationCode(user: { id: string; email: string }) {
  const code = createEmailVerificationCode();
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      'UPDATE email_verification_codes SET consumed_at=now() WHERE user_id=$1 AND consumed_at IS NULL',
      [user.id],
    );
    await client.query(
      "INSERT INTO email_verification_codes(user_id, code_hash, expires_at) VALUES($1,$2,now() + interval '59 seconds')",
      [user.id, hashEmailVerificationCode(user.id, code)],
    );
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
  await deliverEmailVerificationCode(user.email, code);
}

type EmailCodeVerificationResult = 'verified' | 'invalid' | 'expired';

async function verifyEmailVerificationCode(userId: string, code: string): Promise<EmailCodeVerificationResult> {
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query<{ id: string; code_hash: string; expires_at: Date; attempts: number }>(
      'SELECT id,code_hash,expires_at,attempts FROM email_verification_codes WHERE user_id=$1 AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1 FOR UPDATE',
      [userId],
    );
    const record = result.rows[0];
    if (!record || record.expires_at <= new Date()) {
      if (record) await client.query('UPDATE email_verification_codes SET consumed_at=now() WHERE id=$1', [record.id]);
      await client.query('COMMIT');
      return 'expired';
    }
    const valid = timingSafeEqual(
      Buffer.from(record.code_hash, 'hex'),
      Buffer.from(hashEmailVerificationCode(userId, code), 'hex'),
    );
    if (!valid) {
      const attempts = record.attempts + 1;
      await client.query(
        'UPDATE email_verification_codes SET attempts=$2, consumed_at=CASE WHEN $2 >= 5 THEN now() ELSE NULL END WHERE id=$1',
        [record.id, attempts],
      );
      await client.query('COMMIT');
      return 'invalid';
    }
    await client.query('UPDATE email_verification_codes SET consumed_at=now() WHERE id=$1', [record.id]);
    await client.query('UPDATE users SET email_verified_at=COALESCE(email_verified_at, now()), updated_at=now() WHERE id=$1', [userId]);
    await client.query('COMMIT');
    return 'verified';
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function consumeActionToken(token: string, kind: 'verify_email' | 'reset_password') {
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query<{ id: string; user_id: string }>('SELECT id,user_id FROM account_action_tokens WHERE token_hash=$1 AND kind=$2 AND consumed_at IS NULL AND expires_at > now() FOR UPDATE', [hashOpaque(token), kind]);
    const row = result.rows[0];
    if (!row) { await client.query('ROLLBACK'); return null; }
    await client.query('UPDATE account_action_tokens SET consumed_at=now() WHERE id=$1', [row.id]);
    await client.query('COMMIT');
    return row.user_id;
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
}

async function requireUser(request: { headers: { authorization?: string } }) {
  const token = request.headers.authorization?.replace(/^Bearer\s+/i, '');
  if (!token) throw new Error('UNAUTHORIZED');
  const verified = await jwtVerify(token, kmsPublicKey, { issuer, audience, algorithms: ['RS256'] });
  const userId = verified.payload.sub;
  if (!userId) throw new Error('UNAUTHORIZED');
  const result = await db.query<{ id: string; email: string; display_name: string }>('SELECT id,email,display_name FROM users WHERE id=$1 AND email_verified_at IS NOT NULL', [userId]);
  if (!result.rows[0]) throw new Error('UNAUTHORIZED');
  return result.rows[0];
}

async function createWebAuthnChallenge(userId: string | null, purpose: 'registration' | 'authentication', challenge: string) {
  await db.query('INSERT INTO webauthn_challenges(user_id,purpose,challenge,expires_at) VALUES($1,$2,$3,now() + interval \'5 minutes\')', [userId, purpose, challenge]);
}

async function consumeWebAuthnChallenge(challenge: string, purpose: 'registration' | 'authentication') {
  const result = await db.query<{ id: string; user_id: string | null }>('UPDATE webauthn_challenges SET consumed_at=now() WHERE challenge=$1 AND purpose=$2 AND consumed_at IS NULL AND expires_at > now() RETURNING id,user_id', [challenge, purpose]);
  return result.rows[0] ?? null;
}

await app.register(helmet, { global: true });
await app.register(cors, {
  origin: (origin, callback) => {
    // Native clients do not send Origin. Browser access is restricted to the
    // public site and local Flutter web development, never wildcarded.
    if (!origin || origin === 'https://turksquare.com' || origin === 'https://www.turksquare.com' || /^http:\/\/localhost:\d+$/.test(origin)) {
      callback(null, true);
      return;
    }
    callback(null, false);
  },
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type'],
  maxAge: 600,
});
await app.register(rateLimit, { global: true, max: 120, timeWindow: '1 minute', keyGenerator: (request) => request.ip });

// This is intentionally public. It contains only the RSA public key and lets
// Community, Matrix and future OIDC relying parties verify access tokens
// without receiving an Identity secret or calling the Identity database.
app.get('/.well-known/jwks.json', { config: { rateLimit: false } }, async (_request, reply) => {
  reply.header('cache-control', 'public, max-age=300, stale-while-revalidate=300');
  return { keys: [publicJwk] };
});

app.get('/.well-known/openid-configuration', { config: { rateLimit: false } }, async () => ({
  issuer,
  jwks_uri: new URL('/.well-known/jwks.json', issuer).toString(),
  response_types_supported: ['token'],
  subject_types_supported: ['public'],
  id_token_signing_alg_values_supported: ['RS256'],
}));

// This endpoint intentionally discloses no infrastructure details. The ALB
// uses it to route traffic only to tasks that can reach the Identity database.
app.get('/health', { config: { rateLimit: false } }, async (_request, reply) => {
  try {
    await db.query('SELECT 1');
    return { status: 'ok' };
  } catch (error) {
    app.log.warn({ err: error }, 'Identity health check failed');
    return reply.code(503).send({ status: 'unavailable' });
  }
});

app.get('/v1/auth/onboarding', async (request, reply) => {
  try {
    const user = await requireUser(request);
    const result = await db.query<{ city: string; region_code: string; interests: string[]; primary_intent: string; completed_at: Date }>(
      'SELECT city,region_code,interests,primary_intent,completed_at FROM user_onboarding WHERE user_id=$1',
      [user.id],
    );
    const value = result.rows[0];
    return { data: value ? { completed: true, city: value.city, regionCode: value.region_code, interests: value.interests, primaryIntent: value.primary_intent, completedAt: value.completed_at.toISOString() } : { completed: false } };
  } catch {
    return reply.code(401).send({ error: { code: 'UNAUTHENTICATED', message: 'Oturum doğrulanamadı.' } });
  }
});

app.put('/v1/auth/onboarding', { config: { rateLimit: { max: 10, timeWindow: '1 hour' } } }, async (request, reply) => {
  try {
    const user = await requireUser(request);
    const input = onboardingSchema.parse(request.body);
    const regionCode = input.regionCode.toUpperCase();
    const client = await db.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `INSERT INTO user_onboarding(user_id,city,region_code,interests,primary_intent)
         VALUES($1,$2,$3,$4,$5)
         ON CONFLICT(user_id) DO UPDATE SET city=EXCLUDED.city,region_code=EXCLUDED.region_code,interests=EXCLUDED.interests,primary_intent=EXCLUDED.primary_intent,updated_at=now()`,
        [user.id, input.city, regionCode, input.interests, input.primaryIntent],
      );
      await client.query(
        `INSERT INTO identity_outbox_events(aggregate_type,aggregate_id,event_type,payload)
         VALUES('user_onboarding',$1,'community.profile_upserted',$2::jsonb)`,
        [user.id, JSON.stringify({ userId: user.id, displayName: user.display_name, city: input.city, regionCode, interests: input.interests })],
      );
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
    return reply.code(204).send();
  } catch (error) {
    if (error instanceof z.ZodError) return reply.code(400).send({ error: { code: 'INVALID_ONBOARDING', message: 'Onboarding bilgileri geçersiz.' } });
    return reply.code(401).send({ error: { code: 'UNAUTHENTICATED', message: 'Oturum doğrulanamadı.' } });
  }
});

// This endpoint powers the two-step sign-in experience. It deliberately
// returns only a boolean, never account metadata or verification state. It is
// rate-limited more aggressively than general auth endpoints because the UX
// decision to branch on account existence carries an enumeration risk.
app.post('/v1/auth/email/status', { config: { rateLimit: { max: 8, timeWindow: '15 minutes' } } }, async (request) => {
  const input = emailSchema.parse(request.body);
  const result = await db.query<{ exists: boolean }>(
    'SELECT EXISTS(SELECT 1 FROM users WHERE email=$1) AS exists',
    [input.email.toLowerCase()],
  );
  const exists = result.rows[0]?.exists === true;
  app.log.info({ event: 'email_status_checked' }, 'Email status checked');
  return { data: { exists } };
});

app.post('/v1/auth/register', { config: { rateLimit: { max: 5, timeWindow: '1 hour' } } }, async (request, reply) => {
  const input = registerSchema.parse(request.body);
  const passwordValidation = await validateNewPassword(input.password, { email: input.email, name: input.name });
  if (passwordValidation) return reply.code(passwordValidation.code === 'PASSWORD_CHECK_UNAVAILABLE' ? 503 : 400).send({ error: passwordValidation });
  const passwordHash = await hashPassword(input.password);
  try {
    const result = await db.query<{ id: string; email: string }>('INSERT INTO users(email, display_name, password_hash) VALUES($1,$2,$3) RETURNING id,email', [input.email.toLowerCase(), input.name, passwordHash]);
    await issueEmailVerificationCode(result.rows[0]!);
    // Delivery is intentionally asynchronous and the code is never returned.
    return reply.code(202).send({ data: { user: result.rows[0], verificationRequired: true } });
  } catch (error: unknown) {
    if ((error as { code?: string }).code === '23505') return reply.code(202).send({ data: { verificationRequired: true } });
    throw error;
  }
});

app.post('/v1/auth/email/verify', { config: { rateLimit: { max: 10, timeWindow: '15 minutes' } } }, async (request, reply) => {
  const input = actionSchema.parse(request.body);
  const userId = await consumeActionToken(input.token, 'verify_email');
  if (!userId) return reply.code(400).send({ error: { code: 'INVALID_OR_EXPIRED_TOKEN', message: 'Doğrulama bağlantısı geçersiz veya süresi dolmuş.' } });
  await db.query('UPDATE users SET email_verified_at=COALESCE(email_verified_at, now()), updated_at=now() WHERE id=$1', [userId]);
  return reply.code(204).send();
});

app.post('/v1/auth/email/verification/confirm', { config: { rateLimit: { max: 8, timeWindow: '15 minutes' } } }, async (request, reply) => {
  const input = emailVerificationCodeSchema.parse(request.body);
  const user = await db.query<{ id: string }>(
    'SELECT id FROM users WHERE email=$1 AND email_verified_at IS NULL',
    [input.email.toLowerCase()],
  );
  const userId = user.rows[0]?.id;
  if (!userId) {
    return reply.code(400).send({ error: { code: 'INVALID_OR_EXPIRED_CODE', message: 'Kod geçersiz veya süresi dolmuş.' } });
  }
  const result = await verifyEmailVerificationCode(userId, input.code);
  if (result !== 'verified') {
    return reply.code(400).send({ error: { code: 'INVALID_OR_EXPIRED_CODE', message: 'Kod geçersiz veya süresi dolmuş.' } });
  }
  return reply.code(204).send();
});

// Always return the same response to prevent account enumeration.  For an
// existing unverified account, invalidate prior codes and issue a fresh one.
app.post('/v1/auth/email/verification/resend', { config: { rateLimit: { max: 3, timeWindow: '1 hour' } } }, async (request, reply) => {
  const input = emailSchema.parse(request.body);
  const result = await db.query<{ id: string; email: string }>('SELECT id,email FROM users WHERE email=$1 AND email_verified_at IS NULL', [input.email.toLowerCase()]);
  const user = result.rows[0];
  if (user) {
    await issueEmailVerificationCode(user);
  }
  return reply.code(202).send({ data: { accepted: true } });
});

// Email links open in a browser, so verification is completed here rather than
// depending on an unrelated website host.  The token remains single-use.
app.get('/v1/auth/action', { config: { rateLimit: { max: 10, timeWindow: '15 minutes' } } }, async (request, reply) => {
  const query = request.query as { action?: string; token?: string };
  if (query.action !== 'verify_email' || !query.token) {
    return reply.code(400).type('text/html').send('<!doctype html><title>TurkSquare</title><main><h1>Invalid link</h1></main>');
  }
  // A GET must not consume the one-time token: mailbox security scanners often
  // pre-open links.  The user explicitly confirms with the POST below.
  return reply.type('text/html').send(`<!doctype html><title>TurkSquare</title><meta name="viewport" content="width=device-width,initial-scale=1"><main style="font-family:system-ui;max-width:420px;margin:12vh auto;padding:32px"><h1>TurkSquare</h1><h2>E-postanı doğrula</h2><p>Hesabını etkinleştirmek için aşağıdaki düğmeye dokun.</p><form method="post" action="/v1/auth/action?action=verify_email&amp;token=${encodeURIComponent(query.token)}"><button style="padding:14px 20px;border:0;border-radius:10px;background:#7057ee;color:white;font-weight:700">E-postamı Doğrula</button></form></main>`);
});

app.post('/v1/auth/action', { config: { rateLimit: { max: 10, timeWindow: '15 minutes' } } }, async (request, reply) => {
  const query = request.query as { action?: string; token?: string };
  if (query.action !== 'verify_email' || !query.token) return reply.code(400).type('text/html').send('<!doctype html><title>TurkSquare</title><main><h1>Invalid link</h1></main>');
  const userId = await consumeActionToken(query.token, 'verify_email');
  if (!userId) return reply.code(400).type('text/html').send('<h1>Link expired or already used</h1>');
  await db.query('UPDATE users SET email_verified_at=COALESCE(email_verified_at, now()), updated_at=now() WHERE id=$1', [userId]);
  return reply.type('text/html').send('<!doctype html><title>TurkSquare</title><main><h1>Email verified</h1><p>You can return to TurkSquare and sign in.</p></main>');
});

app.post('/v1/auth/password-reset/request', { config: { rateLimit: { max: 5, timeWindow: '1 hour' } } }, async (request, reply) => {
  const input = emailSchema.parse(request.body);
  const result = await db.query<{ id: string }>('SELECT id FROM users WHERE email=$1', [input.email.toLowerCase()]);
  if (result.rows[0]) {
    const token = await createActionToken(result.rows[0].id, 'reset_password', '15 minutes');
    await deliverActionLink(input.email.toLowerCase(), 'reset_password', token);
  }
  // Generic response prevents account enumeration.
  return reply.code(202).send({ data: { accepted: true } });
});

app.post('/v1/auth/password-reset/confirm', { config: { rateLimit: { max: 8, timeWindow: '15 minutes' } } }, async (request, reply) => {
  const input = resetSchema.parse(request.body);
  const userId = await consumeActionToken(input.token, 'reset_password');
  if (!userId) return reply.code(400).send({ error: { code: 'INVALID_OR_EXPIRED_TOKEN', message: 'Sıfırlama bağlantısı geçersiz veya süresi dolmuş.' } });
  const account = await db.query<{ email: string; display_name: string }>('SELECT email,display_name FROM users WHERE id=$1', [userId]);
  const identity = account.rows[0];
  const passwordValidation = identity && await validateNewPassword(input.password, { email: identity.email, name: identity.display_name });
  if (passwordValidation) return reply.code(passwordValidation.code === 'PASSWORD_CHECK_UNAVAILABLE' ? 503 : 400).send({ error: passwordValidation });
  const passwordHash = await hashPassword(input.password);
  const client = await db.connect();
  try { await client.query('BEGIN'); await client.query('UPDATE users SET password_hash=$1, updated_at=now() WHERE id=$2', [passwordHash, userId]); await client.query('UPDATE refresh_token_families SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL', [userId]); await client.query('COMMIT'); } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
  return reply.code(204).send();
});

app.post('/v1/auth/login', { config: { rateLimit: { max: 8, timeWindow: '15 minutes' } } }, async (request, reply) => {
  const input = loginSchema.parse(request.body);
  const result = await db.query<{ id: string; email: string; password_hash: string; email_verified_at: Date | null }>('SELECT id,email,password_hash,email_verified_at FROM users WHERE email=$1', [input.email.toLowerCase()]);
  const user = result.rows[0];
  const valid = await verifyPassword(input.password, user?.password_hash);
  if (!valid) return reply.code(401).send({ error: { code: 'INVALID_CREDENTIALS', message: 'E-posta veya şifre hatalı.' } });
  if (!user.email_verified_at) return reply.code(403).send({ error: { code: 'EMAIL_VERIFICATION_REQUIRED', message: 'E-posta doğrulaması gerekli.' } });
  const session = await issueSession(user);
  return { data: { user: { id: user.id, email: user.email }, ...session } };
});

app.post('/v1/auth/refresh', { config: { rateLimit: { max: 30, timeWindow: '15 minutes' } } }, async (request, reply) => {
  const input = refreshSchema.parse(request.body);
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const token = await client.query<{ id: string; family_id: string; user_id: string; email: string; consumed_at: Date | null; expires_at: Date; revoked_at: Date | null }>('SELECT t.id,t.family_id,u.id AS user_id,u.email,t.consumed_at,t.expires_at,f.revoked_at FROM refresh_tokens t JOIN refresh_token_families f ON f.id=t.family_id JOIN users u ON u.id=f.user_id WHERE t.token_hash=$1 FOR UPDATE', [hashOpaque(input.refreshToken)]);
    const row = token.rows[0];
    if (!row || row.consumed_at || row.revoked_at || row.expires_at <= new Date()) {
      if (row) await client.query('UPDATE refresh_token_families SET revoked_at=now() WHERE id=$1', [row.family_id]);
      await client.query('COMMIT');
      return reply.code(401).send({ error: { code: 'SESSION_EXPIRED', message: 'Oturum yenilenemedi.' } });
    }
    await client.query('UPDATE refresh_tokens SET consumed_at=now() WHERE id=$1', [row.id]);
    const replacement = opaqueToken();
    await client.query('INSERT INTO refresh_tokens(family_id, token_hash, expires_at) VALUES($1,$2,now() + interval \'30 days\')', [row.family_id, hashOpaque(replacement)]);
    await client.query('COMMIT');
    return { data: { user: { id: row.user_id, email: row.email }, accessToken: await signAccessToken({ id: row.user_id }), refreshToken: replacement } };
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
});

app.post('/v1/auth/logout', async (request, reply) => {
  const input = logoutSchema.parse(request.body);
  // Idempotent by design. An invalid or already revoked token is indistinct
  // from a successful logout and reveals no session information.
  await db.query(
    `UPDATE refresh_token_families
       SET revoked_at=COALESCE(revoked_at, now())
     WHERE id = (
       SELECT family_id FROM refresh_tokens WHERE token_hash=$1
     )`,
    [hashOpaque(input.refreshToken)],
  );
  return reply.code(204).send();
});

app.post('/v1/auth/passkeys/registration/options', async (request, reply) => {
  try {
    const user = await requireUser(request);
    const existing = await db.query<{ credential_id: string; transports: string[] }>('SELECT credential_id,transports FROM webauthn_credentials WHERE user_id=$1', [user.id]);
    const options = await generateRegistrationOptions({ rpName: 'TurkSquare', rpID, userID: new TextEncoder().encode(user.id), userName: user.email, userDisplayName: user.display_name, attestationType: 'none', excludeCredentials: existing.rows.map((item) => ({ id: item.credential_id, transports: item.transports as never })), authenticatorSelection: { residentKey: 'required', userVerification: 'required' } });
    await createWebAuthnChallenge(user.id, 'registration', options.challenge);
    return { data: options };
  } catch (_) { return reply.code(401).send({ error: { code: 'UNAUTHORIZED', message: 'Oturum doğrulanamadı.' } }); }
});

app.post('/v1/auth/passkeys/authentication/options', { config: { rateLimit: { max: 12, timeWindow: '15 minutes' } } }, async (_request, reply) => {
  const options = await generateAuthenticationOptions({ rpID, userVerification: 'required' });
  await createWebAuthnChallenge(null, 'authentication', options.challenge);
  return reply.send({ data: options });
});

app.post('/v1/auth/passkeys/registration/verify', async (request, reply) => {
  try {
    const user = await requireUser(request);
    const input = webauthnSchema.parse(request.body);
    const response = input.credential as unknown as RegistrationResponseJSON;
    const challenges = await db.query<{ challenge: string }>('SELECT challenge FROM webauthn_challenges WHERE user_id=$1 AND purpose=\'registration\' AND consumed_at IS NULL AND expires_at > now()', [user.id]);
    for (const item of challenges.rows) {
      try {
        const verified = await verifyRegistrationResponse({ response, expectedChallenge: item.challenge, expectedOrigin, expectedRPID: rpID, requireUserVerification: true });
        if (!verified.verified || !verified.registrationInfo) continue;
        if (!await consumeWebAuthnChallenge(item.challenge, 'registration')) break;
        const credential = verified.registrationInfo.credential;
        await db.query('INSERT INTO webauthn_credentials(user_id,credential_id,public_key,counter,transports) VALUES($1,$2,$3,$4,$5)', [user.id, credential.id, Buffer.from(credential.publicKey), credential.counter, credential.transports ?? []]);
        return reply.code(204).send();
      } catch { /* invalid credential or challenge */ }
    }
    return reply.code(400).send({ error: { code: 'PASSKEY_VERIFICATION_FAILED', message: 'Passkey doğrulanamadı.' } });
  } catch (_) { return reply.code(400).send({ error: { code: 'PASSKEY_VERIFICATION_FAILED', message: 'Passkey doğrulanamadı.' } }); }
});

app.post('/v1/auth/passkeys/authentication/verify', { config: { rateLimit: { max: 12, timeWindow: '15 minutes' } } }, async (request, reply) => {
  try {
    const input = webauthnSchema.parse(request.body);
    const response = input.credential as unknown as AuthenticationResponseJSON;
    const dbCredential = await db.query<{ user_id: string; email: string; credential_id: string; public_key: Buffer; counter: number; transports: string[] }>('SELECT c.user_id,u.email,c.credential_id,c.public_key,c.counter,c.transports FROM webauthn_credentials c JOIN users u ON u.id=c.user_id WHERE c.credential_id=$1 AND u.email_verified_at IS NOT NULL', [response.id]);
    const credential = dbCredential.rows[0];
    if (!credential) return reply.code(401).send({ error: { code: 'PASSKEY_FAILED', message: 'Passkey doğrulanamadı.' } });
    const challenges = await db.query<{ challenge: string }>('SELECT challenge FROM webauthn_challenges WHERE purpose=\'authentication\' AND consumed_at IS NULL AND expires_at > now()');
    for (const item of challenges.rows) {
      try {
        const verified = await verifyAuthenticationResponse({ response, expectedChallenge: item.challenge, expectedOrigin, expectedRPID: rpID, requireUserVerification: true, credential: { id: credential.credential_id, publicKey: new Uint8Array(credential.public_key), counter: credential.counter, transports: credential.transports as never } });
        if (!verified.verified) continue;
        if (!await consumeWebAuthnChallenge(item.challenge, 'authentication')) break;
        await db.query('UPDATE webauthn_credentials SET counter=$1,last_used_at=now() WHERE credential_id=$2 AND counter <= $1', [verified.authenticationInfo.newCounter, credential.credential_id]);
        const session = await issueSession({ id: credential.user_id, email: credential.email });
        return { data: { user: { id: credential.user_id, email: credential.email }, ...session } };
      } catch { /* challenge mismatch or invalid signature */ }
    }
    return reply.code(401).send({ error: { code: 'PASSKEY_FAILED', message: 'Passkey doğrulanamadı.' } });
  } catch (_) { return reply.code(401).send({ error: { code: 'PASSKEY_FAILED', message: 'Passkey doğrulanamadı.' } }); }
});

await app.listen({ port: Number(process.env.PORT ?? 8080), host: '0.0.0.0' });

if (communityProjectionQueueUrl) {
  void publishCommunityProfileOutbox();
  const outboxTimer = setInterval(() => void publishCommunityProfileOutbox(), 5000);
  outboxTimer.unref();
} else {
  app.log.warn('Community projection queue is not configured; onboarding events remain durable in the Identity outbox');
}

const shutdown = async (signal: string) => {
  app.log.info({ signal }, 'Identity service stopping');
  await app.close();
  await db.end();
  process.exit(0);
};

process.once('SIGTERM', () => void shutdown('SIGTERM'));
process.once('SIGINT', () => void shutdown('SIGINT'));
