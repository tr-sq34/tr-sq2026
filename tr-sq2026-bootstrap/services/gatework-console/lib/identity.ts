import { z } from 'zod';
import type { GateworkMember } from './types';

const baseUrl = () => (process.env.IDENTITY_API_BASE_URL ?? 'http://localhost:8080').replace(/\/$/, '');
const loginResponse = z.object({ data: z.object({ accessToken: z.string(), refreshToken: z.string(), user: z.object({ id: z.string(), email: z.string() }) }) });
const meResponse = z.object({ data: z.object({ id: z.string(), email: z.string().email(), displayName: z.string(), roles: z.array(z.string()), stepUpAt: z.string().optional() }) });

export async function identityLogin(email: string, password: string) {
  const response = await fetch(`${baseUrl()}/v1/auth/login`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, password }), cache: 'no-store' });
  if (!response.ok) throw new Error('INVALID_LOGIN');
  return loginResponse.parse(await response.json()).data;
}
export async function gateworkMe(accessToken: string): Promise<GateworkMember> {
  const response = await fetch(`${baseUrl()}/v1/auth/gatework/me`, { headers: { authorization: `Bearer ${accessToken}` }, cache: 'no-store' });
  if (!response.ok) throw new Error(response.status === 403 ? 'NOT_AUTHORIZED' : 'IDENTITY_UNAVAILABLE');
  const payload = meResponse.parse(await response.json()).data;
  return { id: payload.id, email: payload.email, displayName: payload.displayName, roles: payload.roles as GateworkMember['roles'], stepUpAt: payload.stepUpAt };
}
const refreshResponse = z.object({ data: z.object({ accessToken: z.string(), refreshToken: z.string() }) });

/**
 * Trade the refresh token for a new pair.
 *
 * Identity rotates on every use: the old token is consumed and reusing it
 * revokes the whole family. So the two failure modes have to stay apart. A 401
 * means the session is genuinely over and the cookie must go; anything else -
 * Identity restarting, a timeout, a 502 - is the console's problem and must not
 * sign a working operator out. `'unavailable'` keeps the existing session, which
 * is still valid until its own clock runs out.
 */
export async function identityRefresh(refreshToken: string): Promise<
  { outcome: 'renewed'; accessToken: string; refreshToken: string } | { outcome: 'expired' } | { outcome: 'unavailable' }
> {
  let response: Response;
  try {
    response = await fetch(`${baseUrl()}/v1/auth/refresh`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ refreshToken }),
      cache: 'no-store',
    });
  } catch {
    return { outcome: 'unavailable' };
  }
  if (response.status === 401) return { outcome: 'expired' };
  if (!response.ok) return { outcome: 'unavailable' };
  try {
    const data = refreshResponse.parse(await response.json()).data;
    return { outcome: 'renewed', accessToken: data.accessToken, refreshToken: data.refreshToken };
  } catch {
    return { outcome: 'unavailable' };
  }
}

export async function identityLogout(refreshToken: string) {
  await fetch(`${baseUrl()}/v1/auth/logout`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ refreshToken }), cache: 'no-store' }).catch(() => undefined);
}
