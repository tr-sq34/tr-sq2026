import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { cookies } from 'next/headers';
import type { GateworkMember } from './types';

/**
 * The operator session.
 *
 * Two clocks matter here and confusing them is what took the console down. The
 * cookie is good for eight hours, but the Identity access token inside it lives
 * fifteen minutes. Nothing renewed it, so from minute sixteen every delegated
 * call came back IDENTITY_401 while `getSession()` still cheerfully returned a
 * session - the panel looked signed in and could not read a single number.
 *
 * `accessExpiresAt` is now carried explicitly, read out of the token itself
 * rather than assumed, so the middleware knows when to trade the refresh token
 * for a new pair before a render needs it.
 */
export const SESSION_COOKIE = '__Host-gatework';

// __Host- prefix rules: secure, path=/, no domain. Same options on every write,
// because a mismatch here does not fail loudly - it silently writes a second
// cookie the browser then sends alongside the first.
export const SESSION_COOKIE_OPTIONS = {
  httpOnly: true,
  secure: true,
  sameSite: 'strict',
  path: '/',
  maxAge: 60 * 60 * 8,
  priority: 'high',
} as const;

const required = (name: string) => {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
};
const key = () => createHash('sha256').update(required('GATEWORK_SESSION_SECRET')).digest();

export type GateworkSession = {
  member: GateworkMember;
  accessToken: string;
  refreshToken: string;
  issuedAt: number;
  /** Hard end of the session. Past this the operator signs in again, full stop. */
  expiresAt: number;
  /**
   * When the access token stops being accepted. Optional because sessions
   * issued before this field existed are still in browsers; an unknown expiry
   * is treated as "expired", which costs one refresh and never a wrong answer.
   */
  accessExpiresAt?: number;
};

/**
 * The `exp` claim, read without verifying the signature.
 *
 * Verification is Identity's job and it does it on every call. All this needs
 * is the moment the token stops working, and taking that from the token beats
 * assuming fifteen minutes here and having someone change it there.
 */
export function accessTokenExpiry(token: string): number | undefined {
  const payload = token.split('.')[1];
  if (!payload) return undefined;
  try {
    const claims = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as { exp?: number };
    return typeof claims.exp === 'number' ? claims.exp * 1000 : undefined;
  } catch {
    return undefined;
  }
}

export function encryptSession(value: GateworkSession) {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key(), iv);
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(value), 'utf8'), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), ciphertext]).toString('base64url');
}

export function decryptSession(value: string): GateworkSession | null {
  try {
    const data = Buffer.from(value, 'base64url');
    const decipher = createDecipheriv('aes-256-gcm', key(), data.subarray(0, 12));
    decipher.setAuthTag(data.subarray(12, 28));
    const parsed = JSON.parse(Buffer.concat([decipher.update(data.subarray(28)), decipher.final()]).toString('utf8')) as GateworkSession;
    return parsed.expiresAt > Date.now() ? parsed : null;
  } catch { return null; }
}

export async function getSession() { return decryptSession((await cookies()).get(SESSION_COOKIE)?.value ?? ''); }
export async function setSession(session: GateworkSession) {
  (await cookies()).set(SESSION_COOKIE, encryptSession(session), SESSION_COOKIE_OPTIONS);
}
export async function clearSession() { (await cookies()).delete(SESSION_COOKIE); }
