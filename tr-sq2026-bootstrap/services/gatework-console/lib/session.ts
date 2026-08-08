import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { cookies } from 'next/headers';
import type { GateworkMember } from './types';

const cookieName = '__Host-gatework';
const required = (name: string) => {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
};
const key = () => createHash('sha256').update(required('GATEWORK_SESSION_SECRET')).digest();

export type GateworkSession = { member: GateworkMember; accessToken: string; refreshToken: string; issuedAt: number; expiresAt: number };

function encrypt(value: GateworkSession) {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key(), iv);
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(value), 'utf8'), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), ciphertext]).toString('base64url');
}
function decrypt(value: string): GateworkSession | null {
  try {
    const data = Buffer.from(value, 'base64url');
    const decipher = createDecipheriv('aes-256-gcm', key(), data.subarray(0, 12));
    decipher.setAuthTag(data.subarray(12, 28));
    const parsed = JSON.parse(Buffer.concat([decipher.update(data.subarray(28)), decipher.final()]).toString('utf8')) as GateworkSession;
    return parsed.expiresAt > Date.now() ? parsed : null;
  } catch { return null; }
}
export async function getSession() { return decrypt((await cookies()).get(cookieName)?.value ?? ''); }
export async function setSession(session: GateworkSession) {
  (await cookies()).set(cookieName, encrypt(session), { httpOnly: true, secure: true, sameSite: 'strict', path: '/', maxAge: 60 * 60 * 8, priority: 'high' });
}
export async function clearSession() { (await cookies()).delete(cookieName); }
