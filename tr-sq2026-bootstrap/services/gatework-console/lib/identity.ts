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
export async function identityLogout(refreshToken: string) {
  await fetch(`${baseUrl()}/v1/auth/logout`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ refreshToken }), cache: 'no-store' }).catch(() => undefined);
}
