import { z } from 'zod';
import { createHash, randomUUID } from 'node:crypto';
import { getSession } from './session';

const requiredSession = async () => { const session = await getSession(); if (!session) throw new Error('UNAUTHENTICATED'); return session; };
const identityBase = () => (process.env.IDENTITY_API_BASE_URL ?? 'http://localhost:8080').replace(/\/$/, '');
const communityBase = () => (process.env.COMMUNITY_API_BASE_URL ?? 'http://localhost:8081').replace(/\/$/, '');
const delegationSchema = z.object({ data: z.object({ accessToken: z.string(), expiresIn: z.number().optional() }) });

async function identityFetch(path: string, init: RequestInit, accessToken: string) {
  const response = await fetch(`${identityBase()}${path}`, { ...init, headers: { 'content-type': 'application/json', authorization: `Bearer ${accessToken}`, ...(init.headers ?? {}) }, cache: 'no-store' });
  if (!response.ok) throw new Error(`IDENTITY_${response.status}`); return response;
}
/**
 * The delegation token, minted once and reused while it lives.
 *
 * Identity allows thirty mints per fifteen minutes, and the Komuta Merkezi asks
 * six services at once - so a single operator refreshing the dashboard a few
 * times was enough to turn the whole panel into IDENTITY_429. Every screen was
 * minting its own token for the same operator, seconds apart, and throwing it
 * away.
 *
 * Two layers, both about not asking twice for the same thing. `pending` folds
 * the six simultaneous calls of one page load into a single mint, and `held`
 * carries that token across page loads for as long as Identity says it is good
 * for. Nothing is widened by this: the token is the operator's own, keyed by a
 * digest of their access token so it cannot be handed to anyone else, and it is
 * dropped a minute before it would stop being accepted anyway.
 */
const DELEGATION_SAFETY_MS = 60_000;
const held = new Map<string, { token: string; expiresAt: number }>();
const pending = new Map<string, Promise<string>>();

export async function delegation(accessToken: string) {
  const key = createHash('sha256').update(accessToken).digest('base64url');
  const now = Date.now();

  const cached = held.get(key);
  if (cached && cached.expiresAt > now) return cached.token;

  const inFlight = pending.get(key);
  if (inFlight) return inFlight;

  // Operators come and go and their access tokens rotate every fifteen
  // minutes, so the keys are short lived by nature. Sweeping on mint keeps the
  // map the size of the people currently signed in.
  for (const [existing, entry] of held) if (entry.expiresAt <= now) held.delete(existing);

  const attempt = (async () => {
    const response = await identityFetch('/v1/auth/gatework/delegation', { method: 'POST', body: '{}' }, accessToken);
    const data = delegationSchema.parse(await response.json()).data;
    const lifetime = (data.expiresIn ?? 300) * 1000;
    if (lifetime > DELEGATION_SAFETY_MS) held.set(key, { token: data.accessToken, expiresAt: Date.now() + lifetime - DELEGATION_SAFETY_MS });
    return data.accessToken;
  })().finally(() => {
    pending.delete(key);
  });

  pending.set(key, attempt);
  return attempt;
}
export const createSystemAccountSchema = z.object({ displayName: z.string().trim().min(2).max(100), handle: z.string().trim().toLowerCase().regex(/^[a-z0-9][a-z0-9_-]{2,39}$/), reason: z.string().trim().min(5).max(500) });
export const publishOfficialPostSchema = z.object({ authorId: z.string().uuid(), body: z.string().trim().min(1).max(2200), visibility: z.enum(['public','friends_only']).default('public'), regionCode: z.string().trim().regex(/^[A-Za-z]{2}$/).optional(), reason: z.string().trim().min(5).max(500) });

// Haber Merkezi. Same delegation path as an official post - the console never
// writes to Community with the operator's own token - and the same author rule:
// news goes out under an active official account, not under a person.
export const publishNewsArticleSchema = z.object({
  authorId: z.string().uuid(),
  title: z.string().trim().min(3).max(200),
  summary: z.string().trim().min(3).max(500),
  body: z.string().trim().min(1).max(20000),
  category: z.enum(['gundem','gocmenlik','ekonomi','yasam','spor','kultur','topluluk']),
  heroMediaId: z.string().uuid().optional(),
  regionCode: z.string().trim().regex(/^[A-Za-z]{2}$/).optional(),
  // Empty means "not on the home screen". The strip is short on purpose, so a
  // rank is a decision an editor takes rather than a default every piece gets.
  headlineRank: z.coerce.number().int().min(1).max(20).optional(),
  commentsEnabled: z.boolean().default(true),
  reason: z.string().trim().min(5).max(500),
});

/* --- Haber görseli ---------------------------------------------------------
 *
 * Görsel, tarayıcıdan depoya değil, panelin sunucu tarafından depoya gidiyor.
 * İki nedeni var. Kısa ömürlü yazma bağlantısı tarayıcıya hiç inmiyor; ve
 * depolama hesabına tarayıcıdan yazabilmek için ayrıca CORS kuralı gerekirdi -
 * yükleme yolunun çalışması bir altyapı ayarına bağlı kalırdı.
 *
 * Buradan sonrası uygulamadakiyle aynı hat: karantinaya yazılıyor, medya
 * işleyici tarıyor, EXIF'i temizliyor, webp'ye çeviriyor ve ancak ondan sonra
 * "ready" oluyor. Panelden gelen görsel ayrıcalıklı değil.
 */
export const MEDIA_CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;
export const MEDIA_MAX_BYTES = 10 * 1024 * 1024;

const mediaTicketSchema = z.object({
  data: z.object({
    uploadId: z.string().uuid(),
    mediaId: z.string().uuid(),
    uploadUrl: z.string().url(),
    requiredHeaders: z.record(z.string(), z.string()),
  }),
});

export const mediaStatusSchema = z.object({
  id: z.string().uuid(),
  status: z.enum(['quarantined', 'scanning', 'ready', 'rejected']),
  url: z.string().url().nullable(),
  thumbnailUrl: z.string().url().nullable(),
});

async function communityFetch(path: string, init: RequestInit) {
  const session = await requiredSession();
  const token = await delegation(session.accessToken);
  return fetch(`${communityBase()}${path}`, {
    ...init,
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}`, ...(init.headers ?? {}) },
    cache: 'no-store',
  });
}

export async function uploadNewsImage(input: {
  ownerId: string;
  fileName: string;
  contentType: string;
  bytes: Buffer;
}) {
  const ticketResponse = await communityFetch('/v1/internal/gatework/media/uploads/presign', {
    method: 'POST',
    body: JSON.stringify({
      ownerId: input.ownerId,
      kind: 'image',
      contentType: input.contentType,
      fileName: input.fileName,
      sizeBytes: input.bytes.byteLength,
      sha256: createHash('sha256').update(input.bytes).digest('hex'),
    }),
  });
  if (!ticketResponse.ok) throw new Error(`PRESIGN_${ticketResponse.status}`);
  const ticket = mediaTicketSchema.parse(await ticketResponse.json()).data;

  const stored = await fetch(ticket.uploadUrl, {
    method: 'PUT',
    headers: ticket.requiredHeaders,
    body: new Uint8Array(input.bytes),
  });
  // Depolama servisinin gövdesi XML; hata kodunu oradan alıp öne çıkarmak,
  // "yükleme başarısız" demekten çok daha kullanışlı bir kayıt bırakıyor.
  if (!stored.ok) {
    const code = /<Code>(.*?)<\/Code>/.exec(await stored.text().catch(() => ''))?.[1];
    throw new Error(`STORAGE_${stored.status}${code ? `_${code}` : ''}`);
  }

  const completed = await communityFetch('/v1/internal/gatework/media/uploads/complete', {
    method: 'POST',
    body: JSON.stringify({ ownerId: input.ownerId, uploadId: ticket.uploadId }),
  });
  if (!completed.ok) throw new Error(`COMPLETE_${completed.status}`);
  return { mediaId: ticket.mediaId };
}

/// Tarama birkaç saniye sürüyor; panel bu ucu yoklayarak bekliyor. Yayınlama
/// düğmesi görsel hazır olmadan açılmıyor - hazır olmayan bir kimlikle haber
/// yayınlamak servisten MEDIA_NOT_READY ile geri dönerdi.
export async function newsImageStatus(mediaId: string, ownerId: string) {
  const response = await communityFetch(
    `/v1/internal/gatework/media/${mediaId}?ownerId=${encodeURIComponent(ownerId)}`,
    { method: 'GET' },
  );
  if (!response.ok) throw new Error(`STATUS_${response.status}`);
  return z.object({ data: mediaStatusSchema }).parse(await response.json()).data;
}

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
export async function publishNewsArticle(raw: unknown) {
  const input = publishNewsArticleSchema.parse(raw); const session = await requiredSession(); const token = await delegation(session.accessToken);
  const response = await fetch(`${communityBase()}/v1/internal/gatework/news`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify({ ...input, idempotencyKey: randomUUID() }), cache: 'no-store' });
  if (!response.ok) throw new Error(`COMMUNITY_${response.status}`);
  return z.object({ data: z.object({ id: z.string().uuid() }) }).parse(await response.json()).data;
}
