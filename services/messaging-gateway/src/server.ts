import { createPublicKey, randomUUID } from 'node:crypto';
import { GetPublicKeyCommand, KMSClient } from '@aws-sdk/client-kms';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import { importSPKI, jwtVerify } from 'jose';
import pg from 'pg';
import { z } from 'zod';

const required = (key: string): string => {
  const value = process.env[key];
  if (!value) throw new Error(`Missing required environment variable: ${key}`);
  return value;
};

const pool = new pg.Pool({
  connectionString: required('DATABASE_URL'),
  max: 20,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: true } : undefined,
});
const identityKms = new KMSClient({});
const identityVerificationKey = await (async () => {
  const key = await identityKms.send(new GetPublicKeyCommand({ KeyId: required('IDENTITY_JWT_SIGNING_KMS_KEY_ARN') }));
  if (!key.PublicKey) throw new Error('Identity signing public key is unavailable');
  const pem = createPublicKey({ key: Buffer.from(key.PublicKey), format: 'der', type: 'spki' }).export({ format: 'pem', type: 'spki' }).toString();
  return importSPKI(pem, 'RS256');
})();
const matrixBaseUrl = required('MATRIX_BASE_URL').replace(/\/$/, '');
const matrixToken = required('MATRIX_APPSERVICE_TOKEN');
const matrixServerName = required('MATRIX_SERVER_NAME');
const internalServiceToken = required('INTERNAL_SERVICE_TOKEN');

const app = Fastify({ logger: { redact: ['req.headers.authorization', 'req.headers.x-internal-service-token'] } });
const directConversationBody = z.object({ targetUserId: z.string().uuid() });
const auctionConversationBody = z.object({ sellerUserId: z.string().uuid(), winnerUserId: z.string().uuid(), auctionId: z.string().uuid() });
const messageBody = z.object({ body: z.string().trim().min(1).max(4000), idempotencyKey: z.string().uuid() });
const paginationQuery = z.object({ from: z.string().max(512).optional(), limit: z.coerce.number().int().min(1).max(50).default(30) });

type ConversationRow = {
  id: string;
  participant_low: string;
  participant_high: string;
  matrix_room_id: string;
  created_by: string;
  source: 'profile' | 'auction';
  auction_id: string | null;
  created_at: Date;
};

async function currentUser(authorization?: string): Promise<string> {
  const token = authorization?.replace(/^Bearer\s+/i, '');
  if (!token) throw new HttpError(401, 'UNAUTHENTICATED');
  try {
    const result = await jwtVerify(token, identityVerificationKey, {
      issuer: required('JWT_ISSUER'),
      audience: required('JWT_AUDIENCE'),
      algorithms: ['RS256'],
    });
    if (!result.payload.sub || !z.string().uuid().safeParse(result.payload.sub).success) throw new Error('invalid subject');
    return result.payload.sub;
  } catch {
    throw new HttpError(401, 'UNAUTHENTICATED');
  }
}

class HttpError extends Error {
  constructor(public readonly statusCode: number, public readonly code: string) {
    super(code);
  }
}

function canonicalPair(first: string, second: string): [string, string] {
  if (first === second) throw new HttpError(400, 'SELF_DIRECT_MESSAGE_NOT_ALLOWED');
  return first < second ? [first, second] : [second, first];
}

function matrixUserId(userId: string): string {
  return `@ts_${userId.replaceAll('-', '')}:${matrixServerName}`;
}

async function matrixRequest<T>(path: string, init: RequestInit = {}, impersonate?: string): Promise<T> {
  const url = new URL(`${matrixBaseUrl}${path}`);
  url.searchParams.set('access_token', matrixToken);
  if (impersonate) url.searchParams.set('user_id', matrixUserId(impersonate));
  const response = await fetch(url, {
    ...init,
    headers: { 'content-type': 'application/json', ...(init.headers ?? {}) },
    signal: AbortSignal.timeout(8_000),
  });
  if (!response.ok) {
    const body = await response.text();
    app.log.warn({ status: response.status, body: body.slice(0, 300) }, 'Matrix request failed');
    throw new HttpError(503, 'MESSAGING_UNAVAILABLE');
  }
  return response.status === 204 ? (undefined as T) : (await response.json() as T);
}

async function ensureMatrixUser(userId: string): Promise<void> {
  const username = `ts_${userId.replaceAll('-', '')}`;
  const response = await fetch(`${matrixBaseUrl}/_matrix/client/v3/register?access_token=${encodeURIComponent(matrixToken)}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username, inhibit_login: true, auth: { type: 'm.login.application_service' } }),
    signal: AbortSignal.timeout(8_000),
  });
  if (response.ok || response.status === 400 || response.status === 409) return;
  app.log.warn({ status: response.status }, 'Unable to provision Matrix user');
  throw new HttpError(503, 'MESSAGING_UNAVAILABLE');
}

async function createMatrixRoom(ownerId: string, recipientId: string): Promise<string> {
  await ensureMatrixUser(ownerId);
  await ensureMatrixUser(recipientId);
  const created = await matrixRequest<{ room_id: string }>('/_matrix/client/v3/createRoom', {
    method: 'POST',
    body: JSON.stringify({
      is_direct: true,
      preset: 'private_chat',
      visibility: 'private',
      invite: [matrixUserId(recipientId)],
      creation_content: { 'm.federate': false },
      initial_state: [
        { type: 'm.room.guest_access', state_key: '', content: { guest_access: 'forbidden' } },
        { type: 'm.room.history_visibility', state_key: '', content: { history_visibility: 'invited' } },
      ],
    }),
  }, ownerId);
  await matrixRequest(`/_matrix/client/v3/rooms/${encodeURIComponent(created.room_id)}/join`, { method: 'POST', body: '{}' }, recipientId);
  return created.room_id;
}

async function ensureConversation(actorId: string, otherId: string, source: 'profile' | 'auction', auctionId?: string): Promise<ConversationRow> {
  const [low, high] = canonicalPair(actorId, otherId);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // A unique constraint alone would reject the losing insert after both
    // requests had already created a remote Matrix room. The transaction lock
    // serializes a user pair even before a conversation row exists.
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`${low}:${high}`]);
    const memberCheck = await client.query<{ active: boolean }>(
      'SELECT active FROM messaging_user_projection WHERE user_id = ANY($1::uuid[]) FOR UPDATE',
      [[actorId, otherId]],
    );
    if (memberCheck.rowCount !== 2 || memberCheck.rows.some((row) => !row.active)) throw new HttpError(404, 'USER_NOT_AVAILABLE');
    const blocked = await client.query(
      'SELECT 1 FROM messaging_block_projection WHERE active AND ((blocker_id=$1 AND blocked_id=$2) OR (blocker_id=$2 AND blocked_id=$1))',
      [actorId, otherId],
    );
    if (blocked.rowCount) throw new HttpError(403, 'DIRECT_MESSAGE_NOT_ALLOWED');
    const existing = await client.query<ConversationRow>(
      'SELECT * FROM direct_conversations WHERE participant_low=$1 AND participant_high=$2 FOR UPDATE',
      [low, high],
    );
    if (existing.rowCount) {
      await client.query('COMMIT');
      return existing.rows[0]!;
    }

    // The pair lock is held while Matrix creates the room. This is a deliberate
    // trade-off: it prevents duplicate rooms under concurrent taps.
    const roomId = await createMatrixRoom(actorId, otherId);
    const inserted = await client.query<ConversationRow>(
      `INSERT INTO direct_conversations(participant_low,participant_high,matrix_room_id,created_by,source,auction_id)
       VALUES($1,$2,$3,$4,$5,$6) RETURNING *`,
      [low, high, roomId, actorId, source, auctionId ?? null],
    );
    await client.query(
      'INSERT INTO messaging_audit_events(actor_id,conversation_id,event_type,metadata) VALUES($1,$2,$3,$4)',
      [actorId, inserted.rows[0]!.id, 'direct_conversation_created', JSON.stringify({ source, auctionId: auctionId ?? null })],
    );
    await client.query('COMMIT');
    return inserted.rows[0]!;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function conversationForUser(conversationId: string, userId: string): Promise<ConversationRow> {
  const result = await pool.query<ConversationRow>(
    'SELECT * FROM direct_conversations WHERE id=$1 AND (participant_low=$2 OR participant_high=$2)',
    [conversationId, userId],
  );
  if (!result.rowCount) throw new HttpError(404, 'CONVERSATION_NOT_FOUND');
  return result.rows[0]!;
}

const toConversationDto = (row: ConversationRow, viewerId: string) => ({
  id: row.id,
  participantId: row.participant_low === viewerId ? row.participant_high : row.participant_low,
  createdAt: row.created_at.toISOString(),
  source: row.source,
  auctionId: row.auction_id,
});

await app.register(helmet);
await app.register(rateLimit, { global: true, max: 120, timeWindow: '1 minute' });
await app.register(cors, {
  origin: (origin, callback) => callback(null, !origin || origin === 'https://turksquare.com' || origin === 'https://www.turksquare.com' || /^http:\/\/localhost:\d+$/.test(origin)),
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type', 'Idempotency-Key'],
  maxAge: 600,
});

app.get('/health', { config: { rateLimit: false } }, async (_request, reply) => {
  try {
    await pool.query('SELECT 1');
    return { status: 'ok' };
  } catch {
    return reply.code(503).send({ status: 'unavailable' });
  }
});

app.post('/v1/messages/direct-conversations', async (request, reply) => {
  try {
    const actorId = await currentUser(request.headers.authorization);
    const { targetUserId } = directConversationBody.parse(request.body);
    const conversation = await ensureConversation(actorId, targetUserId, 'profile');
    return reply.code(200).send({ data: toConversationDto(conversation, actorId) });
  } catch (error) {
    return sendError(reply, error);
  }
});

app.post('/internal/messages/auction-conversations', async (request, reply) => {
  if (request.headers['x-internal-service-token'] !== internalServiceToken) return reply.code(401).send({ error: { code: 'UNAUTHENTICATED' } });
  try {
    const { sellerUserId, winnerUserId, auctionId } = auctionConversationBody.parse(request.body);
    const conversation = await ensureConversation(sellerUserId, winnerUserId, 'auction', auctionId);
    return reply.code(200).send({ data: { id: conversation.id } });
  } catch (error) {
    return sendError(reply, error);
  }
});

app.get('/v1/messages/conversations', async (request, reply) => {
  try {
    const viewerId = await currentUser(request.headers.authorization);
    const { limit } = paginationQuery.parse(request.query);
    const result = await pool.query<ConversationRow>(
      `SELECT * FROM direct_conversations WHERE participant_low=$1 OR participant_high=$1 ORDER BY created_at DESC LIMIT $2`,
      [viewerId, limit],
    );
    return { data: result.rows.map((row) => toConversationDto(row, viewerId)) };
  } catch (error) {
    return sendError(reply, error);
  }
});

app.get('/v1/messages/conversations/:id/messages', async (request, reply) => {
  try {
    const viewerId = await currentUser(request.headers.authorization);
    const { from, limit } = paginationQuery.parse(request.query);
    const conversation = await conversationForUser(z.string().uuid().parse((request.params as { id: string }).id), viewerId);
    const params = new URLSearchParams({ dir: 'b', limit: String(limit) });
    if (from) params.set('from', from);
    const messages = await matrixRequest<unknown>(`/_matrix/client/v3/rooms/${encodeURIComponent(conversation.matrix_room_id)}/messages?${params}`, {}, viewerId);
    return { data: messages };
  } catch (error) {
    return sendError(reply, error);
  }
});

app.post('/v1/messages/conversations/:id/messages', async (request, reply) => {
  try {
    const viewerId = await currentUser(request.headers.authorization);
    const conversation = await conversationForUser(z.string().uuid().parse((request.params as { id: string }).id), viewerId);
    const { body, idempotencyKey } = messageBody.parse(request.body);
    const event = await matrixRequest<{ event_id: string }>(
      `/_matrix/client/v3/rooms/${encodeURIComponent(conversation.matrix_room_id)}/send/m.room.message/${idempotencyKey}`,
      { method: 'PUT', body: JSON.stringify({ msgtype: 'm.text', body }) },
      viewerId,
    );
    await pool.query('INSERT INTO messaging_audit_events(actor_id,conversation_id,event_type,metadata) VALUES($1,$2,$3,$4)', [viewerId, conversation.id, 'message_sent', JSON.stringify({ eventId: event.event_id })]);
    return reply.code(201).send({ data: { eventId: event.event_id } });
  } catch (error) {
    return sendError(reply, error);
  }
});

function sendError(reply: { code: (status: number) => { send: (body: unknown) => unknown } }, error: unknown) {
  const known = error instanceof HttpError ? error : new HttpError(503, 'MESSAGING_UNAVAILABLE');
  return reply.code(known.statusCode).send({ error: { code: known.code, message: 'Mesajlaşma şu anda kullanılamıyor.' } });
}

const port = Number(process.env.PORT ?? 8080);
await app.listen({ port, host: '0.0.0.0' });
