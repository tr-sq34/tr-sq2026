import { z } from 'zod';
import { randomUUID } from 'node:crypto';
import { getSession } from './session';

const requiredSession = async () => { const session = await getSession(); if (!session) throw new Error('UNAUTHENTICATED'); return session; };
const identityBase = () => (process.env.IDENTITY_API_BASE_URL ?? 'http://localhost:8080').replace(/\/$/, '');
const communityBase = () => (process.env.COMMUNITY_API_BASE_URL ?? 'http://localhost:8081').replace(/\/$/, '');
const delegationSchema = z.object({ data: z.object({ accessToken: z.string() }) });

async function identityFetch(path: string, init: RequestInit, accessToken: string) {
  const response = await fetch(`${identityBase()}${path}`, { ...init, headers: { 'content-type': 'application/json', authorization: `Bearer ${accessToken}`, ...(init.headers ?? {}) }, cache: 'no-store' });
  if (!response.ok) throw new Error(`IDENTITY_${response.status}`); return response;
}
async function delegation(accessToken: string) {
  const response = await identityFetch('/v1/auth/gatework/delegation', { method: 'POST', body: '{}' }, accessToken);
  return delegationSchema.parse(await response.json()).data.accessToken;
}
export const createSystemAccountSchema = z.object({ displayName: z.string().trim().min(2).max(100), handle: z.string().trim().toLowerCase().regex(/^[a-z0-9][a-z0-9_-]{2,39}$/), reason: z.string().trim().min(5).max(500) });
export const publishOfficialPostSchema = z.object({ authorId: z.string().uuid(), body: z.string().trim().min(1).max(2200), visibility: z.enum(['public','friends_only']).default('public'), regionCode: z.string().trim().regex(/^[A-Za-z]{2}$/).optional(), reason: z.string().trim().min(5).max(500) });

export async function createSystemAccount(raw: unknown) {
  const input = createSystemAccountSchema.parse(raw); const session = await requiredSession(); const idempotencyKey = randomUUID();
  const principalResponse = await identityFetch('/v1/auth/gatework/system-principals', { method: 'POST', body: JSON.stringify({ ...input, idempotencyKey }) }, session.accessToken);
  const principal = z.object({ data: z.object({ id: z.string().uuid(), displayName: z.string(), handle: z.string() }) }).parse(await principalResponse.json()).data;
  const token = await delegation(session.accessToken);
  const activate = await fetch(`${communityBase()}/v1/internal/gatework/system-accounts`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify({ principalId: principal.id, displayName: principal.displayName, reason: input.reason, idempotencyKey }), cache: 'no-store' });
  if (!activate.ok) throw new Error(`COMMUNITY_${activate.status}`);
  return principal;
}
export async function publishOfficialPost(raw: unknown) {
  const input = publishOfficialPostSchema.parse(raw); const session = await requiredSession(); const token = await delegation(session.accessToken);
  const response = await fetch(`${communityBase()}/v1/internal/gatework/posts`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify({ ...input, idempotencyKey: randomUUID() }), cache: 'no-store' });
  if (!response.ok) throw new Error(`COMMUNITY_${response.status}`);
  return z.object({ data: z.object({ id: z.string().uuid() }) }).parse(await response.json()).data;
}
