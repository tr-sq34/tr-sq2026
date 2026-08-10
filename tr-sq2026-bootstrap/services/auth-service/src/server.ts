import { createHash, createHmac, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';

import argon2 from 'argon2';
import Fastify from 'fastify';
import helmet from '@fastify/helmet';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import { importJWK, jwtVerify } from 'jose';
import { keyClient, signWithKeyVault } from './infrastructure/azureKeyVault.js';
import { closeServiceBus, isQueueConfigured, sendOutboxEvent, type OutboxQueue } from './infrastructure/azureServiceBus.js';

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
const jwtSigningKeyName = process.env.AZURE_JWT_SIGNING_KEY_NAME ?? 'turksquare-identity-jwt-signing';
const jwtKeyId = required('JWT_KEY_ID');

const emailCodeHmacKey = required('EMAIL_CODE_HMAC_SECRET');
const rpID = required('WEBAUTHN_RP_ID');
const expectedOrigin = required('WEBAUTHN_ORIGIN');
const emailFrom = required('EMAIL_FROM');
const authActionBaseUrl = required('AUTH_ACTION_BASE_URL');
const emailRelayEndpoint = required('EMAIL_RELAY_FUNCTION_NAME');
const passwordSafetyEndpoint = required('PASSWORD_SAFETY_FUNCTION_NAME');

/**
 * Each outbox event type drains to its own queue. A queue that is not
 * configured is not an error: the events stay durable in
 * `identity_outbox_events` and are delivered once the variable is set.
 */
const OUTBOX_ROUTES: ReadonlyArray<{ queue: OutboxQueue; eventType: string }> = [
  { queue: 'community-profile', eventType: 'community.profile_upserted' },
  { queue: 'messaging-projection', eventType: 'messaging.user_upserted' },
];
const app = Fastify({ logger: { redact: ['req.headers.authorization', 'req.body.password', 'req.body.refreshToken'] } });

const registerSchema = z.object({ name: z.string().trim().min(2).max(100), email: z.string().trim().email().max(254), password: z.string().min(12).max(128) });
const loginSchema = z.object({ email: z.string().trim().email().max(254), password: z.string().min(1).max(128) });
const refreshSchema = z.object({ refreshToken: z.string().min(32).max(512) });
const logoutSchema = z.object({ refreshToken: z.string().min(32).max(512) });
const actionSchema = z.object({ token: z.string().min(32).max(512) });
const emailSchema = z.object({ email: z.string().trim().email().max(254) });
const emailVerificationCodeSchema = emailSchema.extend({ code: z.string().regex(/^\d{6}$/) });
const passwordResetVerifySchema = emailSchema.extend({ code: z.string().regex(/^\d{6}$/) });
const passwordResetConfirmSchema = z.object({ ticket: z.string().min(32).max(512), password: z.string().min(12).max(128) });
const webauthnSchema = z.object({ credential: z.record(z.unknown()) });
const onboardingSchema = z.object({
  city: z.string().trim().min(2).max(100),
  regionCode: z.string().trim().regex(/^[A-Za-z]{2}$/),
  interests: z.array(z.string().trim().min(2).max(40)).min(1).max(12).transform((values) => [...new Set(values.map((value) => value.toLocaleLowerCase('tr-TR')))]),
  primaryIntent: z.enum(['community', 'marketplace', 'networking', 'events']),
});
const gateworkMembersQuery = z.object({ cursor: z.string().uuid().optional(), limit: z.coerce.number().int().min(1).max(100).default(50) });
const gateworkRevokeSchema = z.object({ reason: z.string().trim().min(5).max(500), idempotencyKey: z.string().uuid() });
const gateworkRoleSchema = z.object({ userId: z.string().uuid(), role: z.enum(['owner','security_admin','operations_admin','content_editor','moderator','analyst','auditor']), reason: z.string().trim().min(5).max(500), idempotencyKey: z.string().uuid() });
const systemPrincipalSchema = z.object({ displayName: z.string().trim().min(2).max(100), handle: z.string().trim().toLowerCase().regex(/^[a-z0-9][a-z0-9_-]{2,39}$/), reason: z.string().trim().min(5).max(500), idempotencyKey: z.string().uuid() });

const opaqueToken = () => randomBytes(48).toString('base64url');
const hashOpaque = (token: string) => createHash('sha256').update(token).digest('hex');
const createEmailVerificationCode = () => randomInt(0, 1000000).toString().padStart(6, '0');
const hashEmailVerificationCode = (userId: string, code: string) =>
  createHmac('sha256', emailCodeHmacKey).update(`${userId}:${code}`).digest('hex');
// The purpose is part of the signed input, so a six-digit string that is valid
// as a signup code hashes to something else entirely as a reset code. The two
// flows cannot be crossed even if a future change lets them share a table.
const hashPasswordResetCode = (userId: string, code: string) =>
  createHmac('sha256', emailCodeHmacKey).update(`reset_password:${userId}:${code}`).digest('hex');
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
    const response = await fetch(passwordSafetyEndpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefix, suffix }),
    });
    if (!response.ok) {
      app.log.error(
        { passwordSafetyEndpoint, statusCode: response.status },
        'Password safety function returned an error',
      );
      return 'unavailable';
    }
    const payload = (await response.json()) as { breached?: boolean };
    return payload.breached === true ? 'breached' : 'safe';
  } catch (error) {
    app.log.error(
      { err: error, passwordSafetyEndpoint },
      'Password safety function invocation failed',
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
  const key = await keyClient.getKey(jwtSigningKeyName);
  if (!key) throw new Error('Azure Key Vault signing key not found');
  const jwk = await importJWK(
    {
      kty: key.keyType === 'RSA' ? 'RSA' : 'EC',
      n: key.key?.n ? Buffer.from(key.key.n).toString('base64url') : undefined,
      e: key.key?.e ? Buffer.from(key.key.e).toString('base64url') : undefined,
      alg: 'RS256',
    } as any,
    'RS256'
  );
  return jwk;
})();

const publicJwk = await (async () => {
  const key = await keyClient.getKey(jwtSigningKeyName);
  const jwk: any = {
    kid: jwtKeyId,
    use: 'sig',
    alg: 'RS256',
    kty: key.keyType === 'RSA' ? 'RSA' : 'EC',
  };
  if (key.key?.n) jwk.n = Buffer.from(key.key.n).toString('base64url');
  if (key.key?.e) jwk.e = Buffer.from(key.key.e).toString('base64url');
  if (key.key?.x) jwk.x = Buffer.from(key.key.x).toString('base64url');
  if (key.key?.y) jwk.y = Buffer.from(key.key.y).toString('base64url');
  if (key.key?.crv) jwk.crv = key.key.crv;
  return jwk;
})();

async function signAccessToken(user: { id: string }, options: { audience?: string; ttlSeconds?: number; scope?: string[] } = {}) {
  const now = Math.floor(Date.now() / 1000);
  const protectedHeader = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT', kid: jwtKeyId })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({
    sub: user.id,
    iss: issuer,
    aud: options.audience ?? audience,
    iat: now,
    exp: now + (options.ttlSeconds ?? (15 * 60)),
    ...(options.scope ? { scope: options.scope } : {}),
  })).toString('base64url');
  const signingInput = `${protectedHeader}.${payload}`;
  const signature = await signWithKeyVault(jwtSigningKeyName, Buffer.from(signingInput));
  return `${signingInput}.${signature.toString('base64url')}`;
}


// The database is the source of truth: an onboarding update first commits an
// outbox record, then this publisher delivers it to Community. A crash between
// those two operations is safe because pending records are retried. Consumers
// use the event id as their idempotency key, so duplicate SQS delivery is safe.
async function publishOutbox(queue: OutboxQueue, eventType: string) {
  if (!isQueueConfigured(queue)) return;
  const pending = await db.query<{ id: string; payload: unknown; created_at: Date }>(
    `SELECT id,payload,created_at FROM identity_outbox_events
     WHERE published_at IS NULL AND event_type=$1
     ORDER BY created_at ASC LIMIT 20`,
    [eventType],
  );
  for (const event of pending.rows) {
    try {
      await sendOutboxEvent(queue, {
        eventId: event.id,
        eventType,
        // created_at is assigned inside the same transaction as the domain
        // write, so it is the moment the state actually changed. Using publish
        // time here would let a retried old event overwrite newer state.
        occurredAt: event.created_at.toISOString(),
        payload: event.payload,
      });
      await db.query('UPDATE identity_outbox_events SET published_at=now(),attempts=attempts+1 WHERE id=$1 AND published_at IS NULL', [event.id]);
    } catch (error) {
      await db.query('UPDATE identity_outbox_events SET attempts=attempts+1 WHERE id=$1', [event.id]);
      app.log.warn({ err: error, eventId: event.id, eventType }, 'Identity outbox delivery deferred');
    }
  }
}

async function publishAllOutboxes() {
  for (const route of OUTBOX_ROUTES) {
    await publishOutbox(route.queue, route.eventType).catch((error) => {
      app.log.warn({ err: error, queue: route.queue }, 'Identity outbox drain failed');
    });
  }
}

/**
 * Queues the messaging projection event for a user.
 *
 * Must be called with the same client as the domain write. The messaging
 * gateway refuses conversations for users missing from its projection, so an
 * event lost between the two writes would leave an account permanently unable
 * to receive messages.
 */
async function queueMessagingUserUpsert(
  client: pg.PoolClient,
  user: { id: string; displayName: string; active: boolean },
) {
  await client.query(
    `INSERT INTO identity_outbox_events(aggregate_type,aggregate_id,event_type,payload)
     VALUES('user',$1,'messaging.user_upserted',$2::jsonb)`,
    [user.id, JSON.stringify({ userId: user.id, displayName: user.displayName, active: user.active })],
  );
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

async function createActionToken(userId: string, kind: 'verify_email', ttl: string) {
  const token = opaqueToken();
  await db.query('INSERT INTO account_action_tokens(user_id, kind, token_hash, expires_at) VALUES($1,$2,$3,now() + $4::interval)', [userId, kind, hashOpaque(token), ttl]);
  // Send through a queue-backed transactional email provider. Never log or
  // return the raw token in API responses; this event carries it only to the
  // delivery boundary in a production deployment.
  return token;
}

/**
 * A Function App answers its own root URL with an HTML landing page and HTTP
 * 200. Trusting `response.ok` alone therefore reads a misrouted request as a
 * successful send, which is exactly how a misconfigured route once swallowed
 * every verification mail without producing a single error line. Delivery
 * counts here only when the relay answers with the JSON envelope it documents,
 * carrying a provider message id.
 */
async function postToEmailRelay(message: {
  recipient: string;
  from: string;
  subject: string;
  text: string;
  category: string;
  idempotencyKey: string;
}) {
  const response = await fetch(emailRelayEndpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(message),
  });
  if (!response.ok) throw new Error(`email relay responded with status ${response.status}`);
  const contentType = response.headers.get('content-type') ?? '';
  if (!contentType.includes('application/json')) {
    throw new Error(`email relay responded with "${contentType || 'no content-type'}" instead of JSON`);
  }
  const payload = (await response.json().catch(() => null)) as { data?: { id?: string } } | null;
  if (!payload?.data?.id) throw new Error('email relay response carried no provider message id');
}

async function deliverActionLink(email: string, kind: 'verify_email', token: string) {
  const url = new URL(authActionBaseUrl);
  url.searchParams.set('action', kind);
  url.searchParams.set('token', token);
  // Password reset no longer travels as a link: `GET /v1/auth/action` only ever
  // honoured `verify_email`, so a reset link was a dead end in the inbox. The
  // narrow `kind` keeps it from being wired back in.
  const subject = 'TurkSquare e-posta doğrulaması';
  const instruction = 'E-posta adresinizi doğrulamak için bağlantıyı açın.';
  try {
    await postToEmailRelay({
      recipient: email,
      from: emailFrom,
      subject,
      text: `${instruction}\n\n${url.toString()}\n\nBu isteği siz yapmadıysanız bu e-postayı yok sayın.`,
      category: kind,
      idempotencyKey: `${kind}:${hashOpaque(token)}`,
    });
  } catch (error) {
    // Tokens and recipient addresses must never be added to application logs.
    app.log.error({ err: error, kind }, 'Identity transactional email delivery failed');
    throw new Error('Email delivery failed');
  }
}

async function deliverEmailVerificationCode(email: string, code: string) {
  try {
    await postToEmailRelay({
      recipient: email,
      from: emailFrom,
      subject: 'TurkSquare doğrulama kodunuz',
      text: `TurkSquare doğrulama kodunuz: ${code}\n\nBu kod 59 saniye geçerlidir. Kodu kimseyle paylaşmayın. Bu isteği siz yapmadıysanız bu e-postayı yok sayın.`,
      category: 'verify_email_code',
      idempotencyKey: `verify_email_code:${hashEmailVerificationCode(email, code)}`,
    });
  } catch (error) {
    app.log.error({ err: error, category: 'verify_email_code' }, 'Identity verification code delivery failed');
    throw new Error('Email delivery failed');
  }
}

async function deliverPasswordResetCode(email: string, code: string) {
  try {
    await postToEmailRelay({
      recipient: email,
      from: emailFrom,
      subject: 'TurkSquare parola sıfırlama kodunuz',
      text: `TurkSquare parola sıfırlama kodunuz: ${code}\n\nBu kod 59 saniye geçerlidir. Kodu kimseyle paylaşmayın; TurkSquare çalışanları bu kodu asla istemez. Parola sıfırlama isteğini siz yapmadıysanız bu e-postayı yok sayın, parolanız değişmez.`,
      category: 'reset_password_code',
      // The email address is not part of the signed input anywhere else, but the
      // relay needs an idempotency key that is stable per (recipient, code) and
      // reveals neither. The user id is not in scope at the delivery boundary.
      idempotencyKey: `reset_password_code:${createHmac('sha256', emailCodeHmacKey).update(`${email}:${code}`).digest('hex')}`,
    });
  } catch (error) {
    app.log.error({ err: error, category: 'reset_password_code' }, 'Identity password reset code delivery failed');
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

/**
 * Issuing a fresh reset code retires everything that came before it: older
 * codes and any ticket already minted from one. A person who asks for a second
 * code because the first expired must not leave a usable first code behind, and
 * an attacker who redeemed a code must lose that ticket the moment the real
 * account holder starts the flow again.
 */
async function issuePasswordResetCode(user: { id: string; email: string }) {
  const code = createEmailVerificationCode();
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      'UPDATE password_reset_codes SET consumed_at=COALESCE(consumed_at, now()), ticket_used_at=COALESCE(ticket_used_at, now()) WHERE user_id=$1 AND (consumed_at IS NULL OR (ticket_hash IS NOT NULL AND ticket_used_at IS NULL))',
      [user.id],
    );
    await client.query(
      "INSERT INTO password_reset_codes(user_id, code_hash, expires_at) VALUES($1,$2,now() + interval '59 seconds')",
      [user.id, hashPasswordResetCode(user.id, code)],
    );
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
  await deliverPasswordResetCode(user.email, code);
}

/**
 * Redeems a reset code and, on success, returns the one-time ticket that
 * authorises the password write. The caller gets no way to tell an expired code
 * from a wrong one: distinguishing them would turn this endpoint into an oracle
 * for whether an address has an account. The client already knows when its own
 * 59-second timer ran out and can offer a resend without being told.
 */
async function redeemPasswordResetCode(userId: string, code: string): Promise<string | null> {
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query<{ id: string; code_hash: string; expires_at: Date; attempts: number }>(
      'SELECT id,code_hash,expires_at,attempts FROM password_reset_codes WHERE user_id=$1 AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1 FOR UPDATE',
      [userId],
    );
    const record = result.rows[0];
    if (!record || record.expires_at <= new Date()) {
      if (record) await client.query('UPDATE password_reset_codes SET consumed_at=now() WHERE id=$1', [record.id]);
      await client.query('COMMIT');
      return null;
    }
    const valid = timingSafeEqual(
      Buffer.from(record.code_hash, 'hex'),
      Buffer.from(hashPasswordResetCode(userId, code), 'hex'),
    );
    if (!valid) {
      // Five guesses burn the code outright. Six digits with a 59-second life
      // is already a small target; an unbounded retry budget would shrink it to
      // nothing.
      const attempts = record.attempts + 1;
      await client.query(
        'UPDATE password_reset_codes SET attempts=$2, consumed_at=CASE WHEN $2 >= 5 THEN now() ELSE NULL END WHERE id=$1',
        [record.id, attempts],
      );
      await client.query('COMMIT');
      return null;
    }
    const ticket = opaqueToken();
    await client.query(
      "UPDATE password_reset_codes SET consumed_at=now(), ticket_hash=$2, ticket_expires_at=now() + interval '10 minutes' WHERE id=$1",
      [record.id, hashOpaque(ticket)],
    );
    await client.query('COMMIT');
    return ticket;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function consumePasswordResetTicket(ticket: string) {
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query<{ id: string; user_id: string }>(
      'SELECT id,user_id FROM password_reset_codes WHERE ticket_hash=$1 AND ticket_used_at IS NULL AND ticket_expires_at > now() FOR UPDATE',
      [hashOpaque(ticket)],
    );
    const row = result.rows[0];
    if (!row) { await client.query('ROLLBACK'); return null; }
    await client.query('UPDATE password_reset_codes SET ticket_used_at=now() WHERE id=$1', [row.id]);
    await client.query('COMMIT');
    return row.user_id;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
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
    // The WHERE clause makes the transition observable: rowCount is 1 only the
    // first time the account is verified, so the messaging projection event is
    // queued exactly once rather than on every replayed verification.
    const verified = await client.query<{ display_name: string }>(
      'UPDATE users SET email_verified_at=now(), updated_at=now() WHERE id=$1 AND email_verified_at IS NULL RETURNING display_name',
      [userId],
    );
    if (verified.rowCount) {
      await queueMessagingUserUpsert(client, { id: userId, displayName: verified.rows[0]!.display_name, active: true });
    }
    await client.query('COMMIT');
    return 'verified';
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function consumeActionToken(token: string, kind: 'verify_email') {
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

type GateworkRole = 'owner' | 'security_admin' | 'operations_admin' | 'content_editor' | 'moderator' | 'analyst' | 'auditor';
const privilegedGateworkRoles: GateworkRole[] = ['owner', 'security_admin', 'operations_admin', 'content_editor', 'moderator', 'analyst', 'auditor'];

async function activeGateworkRoles(userId: string) {
  const roles = await db.query<{ role: GateworkRole }>('SELECT role FROM admin_roles WHERE user_id=$1 AND revoked_at IS NULL ORDER BY role', [userId]);
  return roles.rows.map((row) => row.role);
}

async function requireGateworkRole(request: { headers: { authorization?: string } }, allowed: GateworkRole[] = privilegedGateworkRoles) {
  const user = await requireUser(request);
  const roles = await activeGateworkRoles(user.id);
  if (!roles.some((role) => allowed.includes(role))) throw new Error('FORBIDDEN');
  return { user, roles };
}

async function auditGatework(input: { actorId: string; roles: GateworkRole[]; action: string; targetType: string; targetId: string; reason?: string; requestId?: string; rayId?: string; outcome: 'succeeded' | 'denied' | 'failed' }) {
  await db.query('INSERT INTO gatework_audit_events(actor_id,actor_roles,action,target_type,target_id,reason,request_id,cloudflare_ray_id,outcome) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)', [input.actorId, input.roles, input.action, input.targetType, input.targetId, input.reason ?? null, input.requestId ?? null, input.rayId ?? null, input.outcome]);
}

async function seedGateworkOwner() {
  const email = process.env.GATEWORK_BOOTSTRAP_OWNER_EMAIL?.trim().toLowerCase();
  if (!email) return;
  const owner = await db.query<{ id: string }>('SELECT id FROM users WHERE email=$1 AND email_verified_at IS NOT NULL', [email]);
  if (!owner.rows[0]) {
    app.log.warn({ bootstrapOwnerEmailConfigured: true }, 'Gatework owner bootstrap skipped because the verified account does not exist');
    return;
  }
  await db.query("INSERT INTO admin_roles(user_id,role,granted_by,revoked_at) VALUES($1,'owner',$1,NULL) ON CONFLICT(user_id,role) DO NOTHING", [owner.rows[0].id]);
  app.log.info({ ownerId: owner.rows[0].id }, 'Gatework bootstrap owner ensured');
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
    if (!origin || origin === 'https://turksquare.com' || origin === 'https://www.turksquare.com' || origin === 'https://gatework.turksquare.com' || /^http:\/\/localhost:\d+$/.test(origin)) {
      callback(null, true);
      return;
    }
    callback(null, false);
  },
  // The mobile app uses PUT for the idempotent onboarding preference update.
  // Omitting it makes browsers reject the preflight request before it reaches
  // the authenticated endpoint, while native clients misleadingly continue
  // to work.
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
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
  // Wrapped in a transaction so the verification and its messaging projection
  // event commit together; the link flow must reach the projection exactly like
  // the code flow does.
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const verified = await client.query<{ display_name: string }>(
      'UPDATE users SET email_verified_at=now(), updated_at=now() WHERE id=$1 AND email_verified_at IS NULL RETURNING display_name',
      [userId],
    );
    if (verified.rowCount) {
      await queueMessagingUserUpsert(client, { id: userId, displayName: verified.rows[0]!.display_name, active: true });
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
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

// Step 1 of 3. Always answers the same way: an attacker must not learn from
// this endpoint whether an address has an account. A delivery failure is logged
// but not surfaced, because "we could not send it" is itself an existence
// signal — the caller retries with the resend the client already offers.
app.post('/v1/auth/password-reset/request', { config: { rateLimit: { max: 5, timeWindow: '1 hour' } } }, async (request, reply) => {
  const input = emailSchema.parse(request.body);
  const result = await db.query<{ id: string; email: string }>('SELECT id,email FROM users WHERE email=$1', [input.email.toLowerCase()]);
  const user = result.rows[0];
  if (user) {
    try {
      await issuePasswordResetCode(user);
    } catch (error) {
      app.log.error({ err: error, category: 'reset_password_code' }, 'Identity password reset code could not be issued');
    }
  }
  return reply.code(202).send({ data: { accepted: true } });
});

// Step 2 of 3. Trades the six-digit code for a single-use ticket. The code dies
// here whether or not it was right, so a ticket is the only thing that survives
// into the password step.
app.post('/v1/auth/password-reset/verify', { config: { rateLimit: { max: 8, timeWindow: '15 minutes' } } }, async (request, reply) => {
  const input = passwordResetVerifySchema.parse(request.body);
  const result = await db.query<{ id: string }>('SELECT id FROM users WHERE email=$1', [input.email.toLowerCase()]);
  const userId = result.rows[0]?.id;
  const ticket = userId ? await redeemPasswordResetCode(userId, input.code) : null;
  if (!ticket) {
    return reply.code(400).send({ error: { code: 'INVALID_OR_EXPIRED_CODE', message: 'Kod geçersiz veya süresi dolmuş.' } });
  }
  return reply.code(200).send({ data: { ticket, expiresInSeconds: 600 } });
});

// Step 3 of 3. The ticket is consumed before the password is even inspected, so
// a rejected password costs the ticket too — a caller who fails the policy check
// starts over from the code rather than getting unlimited attempts against one
// redeemed code.
app.post('/v1/auth/password-reset/confirm', { config: { rateLimit: { max: 8, timeWindow: '15 minutes' } } }, async (request, reply) => {
  const input = passwordResetConfirmSchema.parse(request.body);
  const userId = await consumePasswordResetTicket(input.ticket);
  if (!userId) return reply.code(400).send({ error: { code: 'INVALID_OR_EXPIRED_TICKET', message: 'Sıfırlama oturumu geçersiz veya süresi dolmuş. Lütfen yeni kod isteyin.' } });
  const account = await db.query<{ email: string; display_name: string; password_hash: string; email_verified_at: Date | null }>(
    'SELECT email,display_name,password_hash,email_verified_at FROM users WHERE id=$1',
    [userId],
  );
  const identity = account.rows[0];
  if (!identity) return reply.code(400).send({ error: { code: 'INVALID_OR_EXPIRED_TICKET', message: 'Sıfırlama oturumu geçersiz veya süresi dolmuş. Lütfen yeni kod isteyin.' } });
  const passwordValidation = await validateNewPassword(input.password, { email: identity.email, name: identity.display_name });
  if (passwordValidation) return reply.code(passwordValidation.code === 'PASSWORD_CHECK_UNAVAILABLE' ? 503 : 400).send({ error: passwordValidation });
  // Reusing the current password would leave whoever prompted the reset exactly
  // as able to sign in as before.
  if (await argon2.verify(identity.password_hash, input.password).catch(() => false)) {
    return reply.code(400).send({ error: { code: 'PASSWORD_UNCHANGED', message: 'Yeni parolanız eskisiyle aynı olamaz.' } });
  }
  const passwordHash = await hashPassword(input.password);
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    await client.query('UPDATE users SET password_hash=$1, updated_at=now() WHERE id=$2', [passwordHash, userId]);
    // Every existing session dies with the old password. A reset is what someone
    // does after losing control of an account, so leaving live refresh tokens
    // behind would defeat the point.
    await client.query('UPDATE refresh_token_families SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL', [userId]);
    // Reading a code out of the inbox proves the same thing signup verification
    // proves. Leaving the account unverified after that would strand a person
    // who reset before ever confirming their address.
    if (identity.email_verified_at === null) {
      const verified = await client.query<{ display_name: string }>(
        'UPDATE users SET email_verified_at=now() WHERE id=$1 AND email_verified_at IS NULL RETURNING display_name',
        [userId],
      );
      if (verified.rowCount) {
        await queueMessagingUserUpsert(client, { id: userId, displayName: verified.rows[0]!.display_name, active: true });
      }
    }
    await client.query('COMMIT');
  } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
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

// Gatework only receives a minimal operator profile. Password hashes, refresh
// tokens, passkeys and identity documents never cross this endpoint.
app.get('/v1/auth/gatework/me', async (request, reply) => {
  try {
    const user = await requireUser(request);
    const roles = await activeGateworkRoles(user.id);
    if (!roles.length) return reply.code(403).send({ error: { code: 'GATEWORK_FORBIDDEN', message: 'Gatework erişimi yok.' } });
    return { data: { id: user.id, email: user.email, displayName: user.display_name, roles } };
  } catch {
    return reply.code(401).send({ error: { code: 'UNAUTHENTICATED', message: 'Oturum doğrulanamadı.' } });
  }
});

app.get('/v1/auth/gatework/members', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const { user, roles } = await requireGateworkRole(request, ['owner', 'security_admin', 'operations_admin', 'auditor']);
    const input = gateworkMembersQuery.parse(request.query);
    const rows = await db.query<{ id: string; email: string; display_name: string; email_verified_at: Date | null; created_at: Date; roles: string[] }>(
      `SELECT u.id,u.email,u.display_name,u.email_verified_at,u.created_at,COALESCE(array_remove(array_agg(r.role) FILTER (WHERE r.revoked_at IS NULL), NULL), '{}') roles
       FROM users u LEFT JOIN admin_roles r ON r.user_id=u.id
       WHERE ($1::uuid IS NULL OR u.id > $1) GROUP BY u.id ORDER BY u.id ASC LIMIT $2`, [input.cursor ?? null, input.limit],
    );
    await auditGatework({ actorId: user.id, roles, action: 'members.list', targetType: 'member_query', targetId: input.cursor ?? 'initial', requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    return { data: rows.rows.map((row) => ({ id: row.id, email: row.email, displayName: row.display_name, emailVerified: Boolean(row.email_verified_at), createdAt: row.created_at.toISOString(), roles: row.roles })), nextCursor: rows.rows.length === input.limit ? rows.rows.at(-1)?.id : null };
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'GATEWORK_FORBIDDEN' } });
  }
});

app.post('/v1/auth/gatework/members/:id/revoke-sessions', { config: { rateLimit: { max: 10, timeWindow: '15 minutes' } } }, async (request, reply) => {
  const targetId = (request.params as { id: string }).id;
  try {
    const { user, roles } = await requireGateworkRole(request, ['owner', 'security_admin']);
    const input = gateworkRevokeSchema.parse(request.body);
    if (targetId === user.id) return reply.code(400).send({ error: { code: 'SELF_REVOKE_NOT_ALLOWED' } });
    await db.query('UPDATE refresh_token_families SET revoked_at=COALESCE(revoked_at,now()) WHERE user_id=$1 AND revoked_at IS NULL', [z.string().uuid().parse(targetId)]);
    await auditGatework({ actorId: user.id, roles, action: 'member.sessions.revoke', targetType: 'member', targetId, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    return reply.code(204).send();
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'GATEWORK_ACTION_REJECTED' } });
  }
});

app.post('/v1/auth/gatework/roles', { config: { rateLimit: { max: 6, timeWindow: '1 hour' } } }, async (request, reply) => {
  try {
    const { user, roles } = await requireGateworkRole(request, ['owner']);
    const input = gateworkRoleSchema.parse(request.body);
    await db.query('INSERT INTO admin_roles(user_id,role,granted_by,revoked_at) VALUES($1,$2,$3,NULL) ON CONFLICT(user_id,role) DO UPDATE SET granted_by=EXCLUDED.granted_by,granted_at=now(),revoked_at=NULL', [input.userId, input.role, user.id]);
    await auditGatework({ actorId: user.id, roles, action: 'role.grant', targetType: 'member', targetId: input.userId, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    return reply.code(204).send();
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'ROLE_CHANGE_REJECTED' } });
  }
});

// A short-lived delegation is minted only after Identity has checked the
// operator role in its own database. Community never receives an Identity DB
// credential and never trusts a client-supplied role claim.
app.post('/v1/auth/gatework/delegation', { config: { rateLimit: { max: 30, timeWindow: '15 minutes' } } }, async (request, reply) => {
  try {
    const { user, roles } = await requireGateworkRole(request);
    const token = await signAccessToken({ id: user.id }, { audience: required('GATEWORK_COMMUNITY_AUDIENCE'), ttlSeconds: 5 * 60, scope: roles });
    await auditGatework({ actorId: user.id, roles, action: 'delegation.mint', targetType: 'community', targetId: 'gatework', requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    return { data: { accessToken: token, expiresIn: 300 } };
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'GATEWORK_FORBIDDEN' } });
  }
});

app.post('/v1/auth/gatework/system-principals', { config: { rateLimit: { max: 10, timeWindow: '1 hour' } } }, async (request, reply) => {
  try {
    const { user, roles } = await requireGateworkRole(request, ['owner', 'operations_admin', 'content_editor']);
    const input = systemPrincipalSchema.parse(request.body);
    const principal = await db.query<{ id: string; display_name: string; handle: string }>('INSERT INTO system_principals(display_name,handle,created_by) VALUES($1,$2,$3) RETURNING id,display_name,handle', [input.displayName, input.handle, user.id]);
    await auditGatework({ actorId: user.id, roles, action: 'system_principal.create', targetType: 'system_principal', targetId: principal.rows[0]!.id, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    return reply.code(201).send({ data: { id: principal.rows[0]!.id, displayName: principal.rows[0]!.display_name, handle: principal.rows[0]!.handle } });
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'SYSTEM_PRINCIPAL_CREATE_REJECTED' } });
  }
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

await seedGateworkOwner();
await app.listen({ port: Number(process.env.PORT ?? 8080), host: '0.0.0.0' });

for (const route of OUTBOX_ROUTES) {
  if (isQueueConfigured(route.queue)) continue;
  app.log.warn(
    { queue: route.queue, eventType: route.eventType },
    'Azure Service Bus queue is not configured; these events stay durable in the Identity outbox until it is',
  );
}

if (OUTBOX_ROUTES.some((route) => isQueueConfigured(route.queue))) {
  void publishAllOutboxes();
  const outboxTimer = setInterval(() => void publishAllOutboxes(), 5000);
  outboxTimer.unref();
}

const shutdown = async (signal: string) => {
  app.log.info({ signal }, 'Identity service stopping');
  await app.close();
  await closeServiceBus();
  await db.end();
  process.exit(0);
};

process.once('SIGTERM', () => void shutdown('SIGTERM'));
process.once('SIGINT', () => void shutdown('SIGINT'));
