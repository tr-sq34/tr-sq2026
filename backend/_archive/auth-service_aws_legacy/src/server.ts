import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import argon2 from 'argon2';
import Fastify from 'fastify';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import { jwtVerify, SignJWT } from 'jose';
import { generateAuthenticationOptions, generateRegistrationOptions, verifyAuthenticationResponse, verifyRegistrationResponse } from '@simplewebauthn/server';
import type { AuthenticationResponseJSON, RegistrationResponseJSON } from '@simplewebauthn/server';
import pg from 'pg';
import { z } from 'zod';

const required = (name: string) => {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
};

const db = new pg.Pool({ connectionString: required('DATABASE_URL'), max: 10, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: true } : undefined });
const jwtKey = new TextEncoder().encode(required('JWT_SECRET'));
const issuer = required('JWT_ISSUER');
const audience = required('JWT_AUDIENCE');
const rpID = required('WEBAUTHN_RP_ID');
const expectedOrigin = required('WEBAUTHN_ORIGIN');
const app = Fastify({ logger: { redact: ['req.headers.authorization', 'req.body.password', 'req.body.refreshToken'] } });

const registerSchema = z.object({ name: z.string().trim().min(2).max(100), email: z.string().trim().email().max(254), password: z.string().min(12).max(128) });
const loginSchema = z.object({ email: z.string().trim().email().max(254), password: z.string().min(1).max(128) });
const refreshSchema = z.object({ refreshToken: z.string().min(32).max(512) });
const logoutSchema = z.object({ refreshToken: z.string().min(32).max(512) });
const actionSchema = z.object({ token: z.string().min(32).max(512) });
const emailSchema = z.object({ email: z.string().trim().email().max(254) });
const resetSchema = actionSchema.extend({ password: z.string().min(12).max(128) });
const webauthnSchema = z.object({ credential: z.record(z.unknown()) });

const opaqueToken = () => randomBytes(48).toString('base64url');
const hashOpaque = (token: string) => createHash('sha256').update(token).digest('hex');
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
  const endpoint = process.env.PWNED_PASSWORDS_RANGE_URL ?? 'https://api.pwnedpasswords.com/range';

  try {
    // Azure Function helper endpoint (e.g. https://func-*.azurewebsites.net/api/passwordBreachCheck)
    if (endpoint.includes('/api/passwordBreachCheck')) {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ prefix, suffix }),
        signal: AbortSignal.timeout(5000),
      });
      if (!response.ok) return 'unavailable';
      const result = await response.json() as { breached?: boolean };
      return result.breached ? 'breached' : 'safe';
    }

    const response = await fetch(`${endpoint}/${prefix}`, {
      headers: { 'Add-Padding': 'true', 'User-Agent': 'AmericaHubAuth/1.0' },
      signal: AbortSignal.timeout(3000),
    });
    if (!response.ok) return 'unavailable';
    const found = (await response.text()).split(/\r?\n/).some((line) => {
      const [candidate] = line.split(':', 1);
      return candidate?.length === suffix.length &&
        timingSafeEqual(Buffer.from(candidate), Buffer.from(suffix));
    });
    return found ? 'breached' : 'safe';
  } catch {
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
const signAccessToken = async (user: { id: string; email: string }) => new SignJWT({ email: user.email })
  .setProtectedHeader({ alg: 'HS256', typ: 'JWT' }).setIssuer(issuer).setAudience(audience).setSubject(user.id).setIssuedAt().setExpirationTime('15m').sign(jwtKey);

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

function resolveEmailDeliveryWebhook(): string | undefined {
  if (process.env.EMAIL_DELIVERY_WEBHOOK) return process.env.EMAIL_DELIVERY_WEBHOOK;
  if (process.env.EMAIL_RELAY_FUNCTION_NAME) {
    const base = process.env.EMAIL_RELAY_FUNCTION_NAME.replace(/\/$/, '');
    return `${base}/api/emailRelay`;
  }
  return undefined;
}

async function deliverActionLink(email: string, kind: 'verify_email' | 'reset_password', token: string) {
  const endpoint = resolveEmailDeliveryWebhook();
  if (!endpoint) {
    if (process.env.NODE_ENV === 'production') throw new Error('EMAIL_DELIVERY_WEBHOOK or EMAIL_RELAY_FUNCTION_NAME is required in production');
    return; // Development must obtain tokens from a test-mail provider, never logs.
  }
  const response = await fetch(endpoint, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, kind, token }) });
  if (!response.ok) throw new Error('Email delivery failed');
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
  const verified = await jwtVerify(token, jwtKey, { issuer, audience });
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
await app.register(rateLimit, { global: true, max: 120, timeWindow: '1 minute', keyGenerator: (request) => request.ip });

app.post('/v1/auth/register', { config: { rateLimit: { max: 5, timeWindow: '1 hour' } } }, async (request, reply) => {
  const input = registerSchema.parse(request.body);
  const passwordValidation = await validateNewPassword(input.password, { email: input.email, name: input.name });
  if (passwordValidation) return reply.code(passwordValidation.code === 'PASSWORD_CHECK_UNAVAILABLE' ? 503 : 400).send({ error: passwordValidation });
  const passwordHash = await hashPassword(input.password);
  try {
    const result = await db.query<{ id: string; email: string }>('INSERT INTO users(email, display_name, password_hash) VALUES($1,$2,$3) RETURNING id,email', [input.email.toLowerCase(), input.name, passwordHash]);
    const verificationToken = await createActionToken(result.rows[0]!.id, 'verify_email', '15 minutes');
    await deliverActionLink(result.rows[0]!.email, 'verify_email', verificationToken);
    // Delivery is intentionally asynchronous and the token is never returned.
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
    return { data: { user: { id: row.user_id, email: row.email }, accessToken: await signAccessToken({ id: row.user_id, email: row.email }), refreshToken: replacement } };
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
