import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import { importJWK, jwtVerify } from 'jose';
import type pg from 'pg';
import { z } from 'zod';
import { createDatabasePool } from './database.js';
import { getIdentityVerificationKey } from './infrastructure/azureKeyVault.js';

const required = (key: string): string => {
  const value = process.env[key];
  if (!value) throw new Error(`Missing required environment variable: ${key}`);
  return value;
};

const pool = createDatabasePool();
const identityVerificationKey = await (async () => {
  const jwk = await getIdentityVerificationKey();
  return importJWK(jwk, 'RS256');
})();
const matrixBaseUrl = required('MATRIX_BASE_URL').replace(/\/$/, '');
const matrixToken = required('MATRIX_APPSERVICE_TOKEN');
const internalServiceToken = required('INTERNAL_SERVICE_TOKEN');

/**
 * Must equal Synapse's `server_name` and the domain in the application
 * service's `namespaces.users` regex. A mismatch makes every register and
 * impersonation call fail with M_EXCLUSIVE, so it is verified against the live
 * homeserver at startup by assertMatrixServerName().
 */
const matrixServerName = required('MATRIX_SERVER_NAME');

const app = Fastify({
  logger: {
    redact: [
      'req.headers.authorization',
      'req.headers["x-internal-service-token"]',
      'req.body.body',
    ],
  },
});

const directConversationBody = z.object({ targetUserId: z.string().uuid() });
const auctionConversationBody = z.object({ sellerUserId: z.string().uuid(), winnerUserId: z.string().uuid(), auctionId: z.string().uuid() });
const messageBody = z.object({ body: z.string().trim().min(1).max(4000), idempotencyKey: z.string().uuid() });
const conversationListQuery = z.object({ cursor: z.string().max(512).optional(), limit: z.coerce.number().int().min(1).max(50).default(30) });
const messageListQuery = z.object({ from: z.string().max(512).optional(), limit: z.coerce.number().int().min(1).max(50).default(30) });
const conversationIdParam = z.object({ id: z.string().uuid() });
const groupBody = z.object({
  name: z.string().trim().min(3).max(80),
  city: z.string().trim().min(2).max(80),
  privacy: z.enum(['public', 'private']),
  imageUrl: z.string().url().max(512).optional(),
});
const groupRequestParams = z.object({ id: z.string().uuid(), userId: z.string().uuid() });
const groupRequestBody = z.object({ decision: z.enum(['accepted', 'declined']) });

type ConversationRow = {
  id: string;
  participant_low: string;
  participant_high: string;
  matrix_room_id: string;
  created_by: string;
  source: 'profile' | 'auction';
  auction_id: string | null;
  created_at: Date;
  last_message_at: Date;
};

type GroupRow = {
  id: string;
  matrix_room_id: string;
  name: string;
  city: string;
  privacy: 'public' | 'private';
  image_url: string | null;
  created_by: string;
  created_at: Date;
  last_message_at: Date;
};

type GroupListRow = GroupRow & {
  member_count: string | number;
  membership_status: 'joined' | 'requested' | null;
  membership_role: 'owner' | 'member' | null;
};

class HttpError extends Error {
  constructor(public readonly statusCode: number, public readonly code: string) {
    super(code);
  }
}

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

function canonicalPair(first: string, second: string): [string, string] {
  if (first === second) throw new HttpError(400, 'SELF_DIRECT_MESSAGE_NOT_ALLOWED');
  return first < second ? [first, second] : [second, first];
}

const matrixLocalpart = (userId: string): string => `ts_${userId.replaceAll('-', '')}`;
const matrixUserId = (userId: string): string => `@${matrixLocalpart(userId)}:${matrixServerName}`;

/**
 * Inverse of matrixUserId. Returns null for anything that is not one of our
 * shadow identities — the application service's own sender user, or a future
 * server-notice account — so those senders are dropped rather than surfaced to
 * the client as a malformed TurkSquare user ID.
 */
function turksquareUserId(matrixId: string): string | null {
  const match = /^@ts_([0-9a-f]{32}):(.+)$/.exec(matrixId);
  if (!match || match[2] !== matrixServerName) return null;
  const hex = match[1]!;
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

// Cursors encode the exact sort key so a conversation that moves while the
// client is paginating cannot cause a skipped or repeated row.
const encodeCursor = (row: { last_message_at: Date; id: string }) =>
  Buffer.from(`${row.last_message_at.toISOString()}|${row.id}`).toString('base64url');
const decodeCursor = (cursor?: string): { lastMessageAt: string; id: string } | null => {
  if (!cursor) return null;
  const [lastMessageAt, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|');
  if (!lastMessageAt || !id || Number.isNaN(Date.parse(lastMessageAt)) || !z.string().uuid().safeParse(id).success) {
    throw new HttpError(400, 'INVALID_CURSOR');
  }
  return { lastMessageAt, id };
};

type MatrixError = { errcode?: string; error?: string };

/**
 * The application-service token authenticates every call. It is sent as a
 * bearer header rather than an `access_token` query parameter so it never
 * reaches Synapse's request log, the ingress access log, or an APM trace URL.
 * `user_id` stays a query parameter: that is the application-service
 * impersonation mechanism defined by the spec and it carries no secret.
 */
async function matrixRequest<T>(path: string, init: RequestInit = {}, impersonate?: string): Promise<T> {
  const url = new URL(`${matrixBaseUrl}${path}`);
  if (impersonate) url.searchParams.set('user_id', matrixUserId(impersonate));
  const response = await fetch(url, {
    ...init,
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${matrixToken}`,
      ...(init.headers ?? {}),
    },
    signal: AbortSignal.timeout(8_000),
  });
  if (!response.ok) {
    const body = await response.text();
    app.log.warn({ status: response.status, path, body: body.slice(0, 300) }, 'Matrix request failed');
    throw new HttpError(503, 'MESSAGING_UNAVAILABLE');
  }
  return response.status === 204 ? (undefined as T) : (await response.json() as T);
}

/**
 * Registers the Matrix identity that shadows a TurkSquare user.
 *
 * Only `M_USER_IN_USE` means "already provisioned". Every other 4xx — most
 * importantly `M_EXCLUSIVE`, which is what a server-name or namespace
 * misconfiguration produces — must surface instead of being swallowed, or the
 * failure resurfaces later as an unexplained room-creation error.
 */
async function ensureMatrixUser(userId: string): Promise<void> {
  const response = await fetch(`${matrixBaseUrl}/_matrix/client/v3/register`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${matrixToken}` },
    body: JSON.stringify({
      username: matrixLocalpart(userId),
      inhibit_login: true,
      auth: { type: 'm.login.application_service' },
    }),
    signal: AbortSignal.timeout(8_000),
  });
  if (response.ok) return;

  const detail = await response.json().catch(() => ({})) as MatrixError;
  if (detail.errcode === 'M_USER_IN_USE') return;
  app.log.error({ status: response.status, errcode: detail.errcode }, 'Unable to provision Matrix user');
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

/**
 * Creates the room behind a community group.
 *
 * The room is never listed in Synapse's public directory: discovery is served
 * from this service's own tables, so the homeserver never has to answer a
 * question about who exists. `join_rule` still differs by privacy, because a
 * public group must be joinable by an impersonated user with no invite, and an
 * invite-only room would reject exactly that call.
 */
async function createGroupRoom(ownerId: string, name: string, privacy: 'public' | 'private'): Promise<string> {
  await ensureMatrixUser(ownerId);
  const created = await matrixRequest<{ room_id: string }>('/_matrix/client/v3/createRoom', {
    method: 'POST',
    body: JSON.stringify({
      preset: privacy === 'public' ? 'public_chat' : 'private_chat',
      visibility: 'private',
      name,
      creation_content: { 'm.federate': false },
      initial_state: [
        { type: 'm.room.guest_access', state_key: '', content: { guest_access: 'forbidden' } },
        // A public group shows its backlog to whoever joins later — that history
        // is what makes a community worth joining. A private one reveals only
        // what was said after the member was let in.
        { type: 'm.room.history_visibility', state_key: '', content: { history_visibility: privacy === 'public' ? 'shared' : 'invited' } },
        { type: 'm.room.join_rules', state_key: '', content: { join_rule: privacy === 'public' ? 'public' : 'invite' } },
      ],
    }),
  }, ownerId);
  return created.room_id;
}

/**
 * The same gate direct conversations apply: a user who is not in the projection
 * — never verified, or deactivated since — has no Matrix identity to act as.
 */
async function assertActiveMember(userId: string): Promise<void> {
  const result = await pool.query<{ active: boolean }>('SELECT active FROM messaging_user_projection WHERE user_id=$1', [userId]);
  if (!result.rowCount || !result.rows[0]!.active) throw new HttpError(404, 'USER_NOT_AVAILABLE');
}

/**
 * Membership decisions belong to the owner alone. A plain member being able to
 * admit people would make a private group's guest list editable by anyone
 * already inside it.
 */
async function assertGroupOwner(groupId: string, userId: string): Promise<GroupRow> {
  const result = await pool.query<GroupRow>(
    `SELECT g.* FROM messaging_groups g
       JOIN messaging_group_members m ON m.group_id = g.id AND m.user_id = $2 AND m.role = 'owner' AND m.status = 'joined'
      WHERE g.id = $1`,
    [groupId, userId],
  );
  if (!result.rowCount) throw new HttpError(404, 'GROUP_NOT_FOUND');
  return result.rows[0]!;
}

async function groupById(groupId: string): Promise<GroupRow> {
  const result = await pool.query<GroupRow>('SELECT * FROM messaging_groups WHERE id=$1', [groupId]);
  if (!result.rowCount) throw new HttpError(404, 'GROUP_NOT_FOUND');
  return result.rows[0]!;
}

/**
 * Blocking is evaluated in both directions: if either participant has blocked
 * the other, neither may open a conversation or send into an existing one.
 */
async function assertNotBlocked(executor: pg.Pool | pg.PoolClient, first: string, second: string): Promise<void> {
  const blocked = await executor.query(
    'SELECT 1 FROM messaging_block_projection WHERE active AND ((blocker_id=$1 AND blocked_id=$2) OR (blocker_id=$2 AND blocked_id=$1))',
    [first, second],
  );
  if (blocked.rowCount) throw new HttpError(403, 'DIRECT_MESSAGE_NOT_ALLOWED');
}

async function ensureConversation(actorId: string, otherId: string, source: 'profile' | 'auction', auctionId?: string): Promise<ConversationRow> {
  const [low, high] = canonicalPair(actorId, otherId);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Bound the wait so a burst of concurrent taps queues rather than pinning
    // every pool connection behind the Matrix round trip below.
    await client.query("SET LOCAL lock_timeout = '15s'");
    // A unique constraint alone would reject the losing insert after both
    // requests had already created a remote Matrix room. The transaction lock
    // serializes a user pair even before a conversation row exists.
    await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [`${low}:${high}`]);

    // Read without FOR UPDATE. The row locks would be held for the whole Matrix
    // round trip below and block the projection worker's upsert for the same
    // users — the worker this endpoint depends on. Serialization of duplicate
    // rooms is already provided by the pair advisory lock, and a deactivation
    // that lands milliseconds after this read is indistinguishable from one that
    // lands milliseconds after the conversation was created.
    const memberCheck = await client.query<{ active: boolean }>(
      'SELECT active FROM messaging_user_projection WHERE user_id = ANY($1::uuid[])',
      [[actorId, otherId]],
    );
    if (memberCheck.rowCount !== 2 || memberCheck.rows.some((row) => !row.active)) throw new HttpError(404, 'USER_NOT_AVAILABLE');
    await assertNotBlocked(client, actorId, otherId);

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
    await client.query('ROLLBACK').catch(() => undefined);
    // 55P03 lock_not_available / 57014 query_canceled: contention, not a client error.
    const code = (error as { code?: string }).code;
    if (code === '55P03' || code === '57014') throw new HttpError(503, 'MESSAGING_BUSY');
    throw error;
  } finally {
    client.release();
  }
}

type Thread =
  | { kind: 'direct'; roomId: string; conversationId: string; otherId: string }
  | { kind: 'group'; roomId: string; groupId: string };

/**
 * Resolves a thread ID the client holds to the room behind it.
 *
 * Direct conversations and groups are separate tables with separate membership
 * rules, but from the client's side both are just a thread it reads and writes
 * messages in. Resolving here keeps one message pipeline instead of two nearly
 * identical ones, and — because each branch joins on membership — a thread the
 * caller is not part of is indistinguishable from one that does not exist.
 */
async function threadForUser(id: string, userId: string): Promise<Thread> {
  const conversation = await pool.query<ConversationRow>(
    'SELECT * FROM direct_conversations WHERE id=$1 AND (participant_low=$2 OR participant_high=$2)',
    [id, userId],
  );
  if (conversation.rowCount) {
    const row = conversation.rows[0]!;
    return {
      kind: 'direct',
      roomId: row.matrix_room_id,
      conversationId: row.id,
      otherId: row.participant_low === userId ? row.participant_high : row.participant_low,
    };
  }

  const group = await pool.query<{ id: string; matrix_room_id: string }>(
    `SELECT g.id, g.matrix_room_id
       FROM messaging_groups g
       JOIN messaging_group_members m ON m.group_id = g.id AND m.user_id = $2 AND m.status = 'joined'
      WHERE g.id = $1`,
    [id, userId],
  );
  if (group.rowCount) {
    const row = group.rows[0]!;
    return { kind: 'group', roomId: row.matrix_room_id, groupId: row.id };
  }

  throw new HttpError(404, 'CONVERSATION_NOT_FOUND');
}

type MatrixEvent = {
  type?: string;
  event_id?: string;
  sender?: string;
  origin_server_ts?: number;
  content?: { msgtype?: string; body?: unknown };
};
type MatrixMessagesResponse = { chunk?: MatrixEvent[]; start?: string; end?: string | null };
type MessageDto = { id: string; senderId: string; body: string; sentAt: string; senderName?: string | null };

/**
 * Projects a Matrix event onto the gateway's own contract.
 *
 * The mobile client is not supposed to know that Matrix exists: room IDs,
 * `@ts_…` sender IDs and event schemas are all implementation detail, and
 * leaking them would freeze the choice of homeserver into every shipped app
 * version. Anything that is not a plain text message from a known TurkSquare
 * identity — membership changes, state events, the room creation event — is
 * dropped rather than rendered as an empty bubble.
 */
function toMessageDto(event: MatrixEvent): MessageDto | null {
  if (event.type !== 'm.room.message' || event.content?.msgtype !== 'm.text') return null;
  if (typeof event.event_id !== 'string' || typeof event.content.body !== 'string') return null;
  if (typeof event.sender !== 'string' || typeof event.origin_server_ts !== 'number') return null;
  const senderId = turksquareUserId(event.sender);
  if (!senderId) return null;
  return {
    id: event.event_id,
    senderId,
    body: event.content.body,
    sentAt: new Date(event.origin_server_ts).toISOString(),
  };
}

type ConversationListRow = ConversationRow & { participant_display_name: string | null };

const toConversationDto = (row: ConversationListRow | ConversationRow, viewerId: string) => ({
  id: row.id,
  participantId: row.participant_low === viewerId ? row.participant_high : row.participant_low,
  participantDisplayName: 'participant_display_name' in row ? row.participant_display_name : undefined,
  createdAt: row.created_at.toISOString(),
  lastMessageAt: row.last_message_at.toISOString(),
  source: row.source,
  auctionId: row.auction_id,
});

const toGroupDto = (row: GroupListRow | GroupRow) => ({
  id: row.id,
  name: row.name,
  city: row.city,
  privacy: row.privacy,
  imageUrl: row.image_url,
  memberCount: 'member_count' in row ? Number(row.member_count) : 1,
  membershipStatus: 'membership_status' in row ? (row.membership_status ?? 'none') : 'joined',
  role: 'membership_role' in row ? row.membership_role : 'owner',
  createdAt: row.created_at.toISOString(),
  lastMessageAt: row.last_message_at.toISOString(),
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
    const { cursor, limit } = conversationListQuery.parse(request.query);
    const page = decodeCursor(cursor);
    // The display name comes from the local projection, never from Synapse's
    // profile API, so the mobile client cannot be used to enumerate Matrix users.
    const result = await pool.query<ConversationListRow>(
      `SELECT c.*, p.display_name AS participant_display_name
         FROM direct_conversations c
         LEFT JOIN messaging_user_projection p
           ON p.user_id = CASE WHEN c.participant_low = $1 THEN c.participant_high ELSE c.participant_low END
        WHERE (c.participant_low = $1 OR c.participant_high = $1)
          AND ($2::timestamptz IS NULL OR (c.last_message_at, c.id) < ($2::timestamptz, $3::uuid))
        ORDER BY c.last_message_at DESC, c.id DESC
        LIMIT $4`,
      [viewerId, page?.lastMessageAt ?? null, page?.id ?? null, limit],
    );
    return {
      data: result.rows.map((row) => toConversationDto(row, viewerId)),
      nextCursor: result.rows.length === limit ? encodeCursor(result.rows.at(-1)!) : null,
    };
  } catch (error) {
    return sendError(reply, error);
  }
});

/**
 * Lists every group, including private ones the caller is not in.
 *
 * A private group's name and city are what makes it findable at all; without
 * them nobody could ever ask to join one. Its messages stay unreachable — the
 * caller has no Matrix membership, so the message routes below refuse the room.
 */
app.get('/v1/messages/groups', async (request, reply) => {
  try {
    const viewerId = await currentUser(request.headers.authorization);
    const { cursor, limit } = conversationListQuery.parse(request.query);
    const page = decodeCursor(cursor);
    const result = await pool.query<GroupListRow>(
      `SELECT g.*,
              (SELECT COUNT(*) FROM messaging_group_members c
                WHERE c.group_id = g.id AND c.status = 'joined') AS member_count,
              m.status AS membership_status,
              m.role AS membership_role
         FROM messaging_groups g
         LEFT JOIN messaging_group_members m ON m.group_id = g.id AND m.user_id = $1
        WHERE ($2::timestamptz IS NULL OR (g.last_message_at, g.id) < ($2::timestamptz, $3::uuid))
        ORDER BY g.last_message_at DESC, g.id DESC
        LIMIT $4`,
      [viewerId, page?.lastMessageAt ?? null, page?.id ?? null, limit],
    );
    return {
      data: result.rows.map(toGroupDto),
      nextCursor: result.rows.length === limit ? encodeCursor(result.rows.at(-1)!) : null,
    };
  } catch (error) {
    return sendError(reply, error);
  }
});

// Creating a room is the most expensive thing an authenticated caller can ask
// for, and every group is permanent state on the homeserver, so this route is
// capped far below the global limit.
app.post('/v1/messages/groups', { config: { rateLimit: { max: 5, timeWindow: '1 hour' } } }, async (request, reply) => {
  try {
    const actorId = await currentUser(request.headers.authorization);
    const { name, city, privacy, imageUrl } = groupBody.parse(request.body);
    await assertActiveMember(actorId);

    const roomId = await createGroupRoom(actorId, name, privacy);
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const inserted = await client.query<GroupRow>(
        `INSERT INTO messaging_groups(matrix_room_id,name,city,privacy,image_url,created_by)
         VALUES($1,$2,$3,$4,$5,$6) RETURNING *`,
        [roomId, name, city, privacy, imageUrl ?? null, actorId],
      );
      const group = inserted.rows[0]!;
      await client.query(
        `INSERT INTO messaging_group_members(group_id,user_id,role,status) VALUES($1,$2,'owner','joined')`,
        [group.id, actorId],
      );
      await client.query(
        'INSERT INTO messaging_audit_events(actor_id,group_id,event_type,metadata) VALUES($1,$2,$3,$4)',
        [actorId, group.id, 'group_created', JSON.stringify({ privacy })],
      );
      await client.query('COMMIT');
      return reply.code(201).send({ data: toGroupDto(group) });
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      // The room now exists on the homeserver with no group row pointing at it.
      // It is unreachable rather than harmful, but it is logged so it can be
      // cleaned up: nothing else records that ID.
      app.log.error({ err: error, roomId }, 'Group row insert failed after the Matrix room was created');
      throw error;
    } finally {
      client.release();
    }
  } catch (error) {
    return sendError(reply, error);
  }
});

/**
 * Joins a public group outright, or records a request against a private one.
 *
 * Repeating the call is deliberately harmless: both the Matrix join and the
 * membership insert are idempotent, so a double tap returns the same state
 * instead of failing.
 */
app.post('/v1/messages/groups/:id/join', async (request, reply) => {
  try {
    const viewerId = await currentUser(request.headers.authorization);
    const { id } = conversationIdParam.parse(request.params);
    await assertActiveMember(viewerId);
    const group = await groupById(id);

    const existing = await pool.query<{ status: 'joined' | 'requested' }>(
      'SELECT status FROM messaging_group_members WHERE group_id=$1 AND user_id=$2',
      [group.id, viewerId],
    );
    if (existing.rowCount) return { data: { membershipStatus: existing.rows[0]!.status } };

    if (group.privacy === 'public') {
      await ensureMatrixUser(viewerId);
      await matrixRequest(`/_matrix/client/v3/rooms/${encodeURIComponent(group.matrix_room_id)}/join`, { method: 'POST', body: '{}' }, viewerId);
    }
    const status = group.privacy === 'public' ? 'joined' : 'requested';
    await pool.query(
      `INSERT INTO messaging_group_members(group_id,user_id,role,status) VALUES($1,$2,'member',$3)
       ON CONFLICT (group_id,user_id) DO NOTHING`,
      [group.id, viewerId, status],
    );
    await pool.query(
      'INSERT INTO messaging_audit_events(actor_id,group_id,event_type,metadata) VALUES($1,$2,$3,$4)',
      [viewerId, group.id, status === 'joined' ? 'group_joined' : 'group_join_requested', '{}'],
    );
    return { data: { membershipStatus: status } };
  } catch (error) {
    return sendError(reply, error);
  }
});

/**
 * Leaves a group, or withdraws a pending request.
 *
 * The owner cannot leave: the room's only power-level 100 account would be gone
 * and nobody could admit members or moderate afterwards. Transferring ownership
 * is the missing piece here, not an exit for the owner.
 */
app.post('/v1/messages/groups/:id/leave', async (request, reply) => {
  try {
    const viewerId = await currentUser(request.headers.authorization);
    const { id } = conversationIdParam.parse(request.params);
    const group = await groupById(id);
    const membership = await pool.query<{ role: 'owner' | 'member'; status: 'joined' | 'requested' }>(
      'SELECT role, status FROM messaging_group_members WHERE group_id=$1 AND user_id=$2',
      [group.id, viewerId],
    );
    if (!membership.rowCount) return { data: { membershipStatus: 'none' } };
    if (membership.rows[0]!.role === 'owner') throw new HttpError(409, 'GROUP_OWNER_CANNOT_LEAVE');

    if (membership.rows[0]!.status === 'joined') {
      await matrixRequest(`/_matrix/client/v3/rooms/${encodeURIComponent(group.matrix_room_id)}/leave`, { method: 'POST', body: '{}' }, viewerId);
    }
    await pool.query('DELETE FROM messaging_group_members WHERE group_id=$1 AND user_id=$2', [group.id, viewerId]);
    await pool.query(
      'INSERT INTO messaging_audit_events(actor_id,group_id,event_type,metadata) VALUES($1,$2,$3,$4)',
      [viewerId, group.id, 'group_left', '{}'],
    );
    return { data: { membershipStatus: 'none' } };
  } catch (error) {
    return sendError(reply, error);
  }
});

// Owner-only view of who is waiting. Nothing else exposes the requester list,
// so a private group's pending members stay invisible to its members.
app.get('/v1/messages/groups/:id/requests', async (request, reply) => {
  try {
    const viewerId = await currentUser(request.headers.authorization);
    const { id } = conversationIdParam.parse(request.params);
    await assertGroupOwner(id, viewerId);
    const result = await pool.query<{ user_id: string; display_name: string | null; created_at: Date }>(
      `SELECT m.user_id, p.display_name, m.created_at
         FROM messaging_group_members m
         LEFT JOIN messaging_user_projection p ON p.user_id = m.user_id
        WHERE m.group_id = $1 AND m.status = 'requested'
        ORDER BY m.created_at ASC
        LIMIT 100`,
      [id],
    );
    return {
      data: result.rows.map((row) => ({
        userId: row.user_id,
        displayName: row.display_name,
        requestedAt: row.created_at.toISOString(),
      })),
    };
  } catch (error) {
    return sendError(reply, error);
  }
});

app.post('/v1/messages/groups/:id/requests/:userId', async (request, reply) => {
  try {
    const viewerId = await currentUser(request.headers.authorization);
    const { id, userId } = groupRequestParams.parse(request.params);
    const { decision } = groupRequestBody.parse(request.body);
    const group = await assertGroupOwner(id, viewerId);

    const pending = await pool.query(
      `SELECT 1 FROM messaging_group_members WHERE group_id=$1 AND user_id=$2 AND status='requested'`,
      [group.id, userId],
    );
    if (!pending.rowCount) throw new HttpError(404, 'JOIN_REQUEST_NOT_FOUND');

    if (decision === 'declined') {
      // The row is deleted rather than marked: a user who was turned down once
      // is allowed to ask again later.
      await pool.query('DELETE FROM messaging_group_members WHERE group_id=$1 AND user_id=$2', [group.id, userId]);
    } else {
      await assertActiveMember(userId);
      await ensureMatrixUser(userId);
      await matrixRequest(
        `/_matrix/client/v3/rooms/${encodeURIComponent(group.matrix_room_id)}/invite`,
        { method: 'POST', body: JSON.stringify({ user_id: matrixUserId(userId) }) },
        viewerId,
      );
      await matrixRequest(`/_matrix/client/v3/rooms/${encodeURIComponent(group.matrix_room_id)}/join`, { method: 'POST', body: '{}' }, userId);
      await pool.query(`UPDATE messaging_group_members SET status='joined' WHERE group_id=$1 AND user_id=$2`, [group.id, userId]);
    }
    await pool.query(
      'INSERT INTO messaging_audit_events(actor_id,group_id,event_type,metadata) VALUES($1,$2,$3,$4)',
      [viewerId, group.id, 'group_join_decided', JSON.stringify({ userId, decision })],
    );
    return { data: { membershipStatus: decision === 'accepted' ? 'joined' : 'none' } };
  } catch (error) {
    return sendError(reply, error);
  }
});

app.get('/v1/messages/conversations/:id/messages', async (request, reply) => {
  try {
    const viewerId = await currentUser(request.headers.authorization);
    const { from, limit } = messageListQuery.parse(request.query);
    const { id } = conversationIdParam.parse(request.params);
    const thread = await threadForUser(id, viewerId);
    const params = new URLSearchParams({ dir: 'b', limit: String(limit) });
    if (from) params.set('from', from);
    const page = await matrixRequest<MatrixMessagesResponse>(
      `/_matrix/client/v3/rooms/${encodeURIComponent(thread.roomId)}/messages?${params}`,
      {},
      viewerId,
    );
    const chunk = Array.isArray(page.chunk) ? page.chunk : [];
    const messages = chunk.map(toMessageDto).filter((message): message is MessageDto => message !== null);
    // A group bubble has to say who wrote it. A direct thread has exactly two
    // participants and the client already knows both names from the inbox, so
    // the extra query only runs where it buys something.
    if (thread.kind === 'group' && messages.length) {
      const senderIds = [...new Set(messages.map((message) => message.senderId))].filter((id) => id !== viewerId);
      if (senderIds.length) {
        const names = await pool.query<{ user_id: string; display_name: string | null }>(
          'SELECT user_id, display_name FROM messaging_user_projection WHERE user_id = ANY($1::uuid[])',
          [senderIds],
        );
        const byId = new Map(names.rows.map((row) => [row.user_id, row.display_name]));
        for (const message of messages) {
          if (message.senderId !== viewerId) message.senderName = byId.get(message.senderId) ?? null;
        }
      }
    }
    return {
      data: messages,
      // `end` is Matrix's opaque backwards-pagination token. It is returned only
      // while the room still has history: an empty chunk means the client has
      // reached the beginning and must stop, otherwise it would loop forever on
      // a page whose text events were all filtered out.
      nextCursor: chunk.length ? (page.end ?? null) : null,
    };
  } catch (error) {
    return sendError(reply, error);
  }
});

app.post('/v1/messages/conversations/:id/messages', async (request, reply) => {
  try {
    const viewerId = await currentUser(request.headers.authorization);
    const { id } = conversationIdParam.parse(request.params);
    const thread = await threadForUser(id, viewerId);
    const { body, idempotencyKey } = messageBody.parse(request.body);

    // Re-checked on every send, not only at conversation creation: a block
    // placed after the room exists must stop further messages in both
    // directions. Matrix room membership survives the block by design so the
    // existing history stays readable. A group has no single counterparty, so
    // there is nothing to evaluate — leaving is the remedy there.
    if (thread.kind === 'direct') await assertNotBlocked(pool, viewerId, thread.otherId);

    const event = await matrixRequest<{ event_id: string }>(
      `/_matrix/client/v3/rooms/${encodeURIComponent(thread.roomId)}/send/m.room.message/${encodeURIComponent(idempotencyKey)}`,
      { method: 'PUT', body: JSON.stringify({ msgtype: 'm.text', body }) },
      viewerId,
    );
    // Ordering only ever moves forward, so a delayed write cannot pull a
    // conversation back down the inbox.
    if (thread.kind === 'direct') {
      await pool.query('UPDATE direct_conversations SET last_message_at=GREATEST(last_message_at, now()) WHERE id=$1', [thread.conversationId]);
      await pool.query('INSERT INTO messaging_audit_events(actor_id,conversation_id,event_type,metadata) VALUES($1,$2,$3,$4)', [viewerId, thread.conversationId, 'message_sent', JSON.stringify({ eventId: event.event_id })]);
    } else {
      await pool.query('UPDATE messaging_groups SET last_message_at=GREATEST(last_message_at, now()) WHERE id=$1', [thread.groupId]);
      await pool.query('INSERT INTO messaging_audit_events(actor_id,group_id,event_type,metadata) VALUES($1,$2,$3,$4)', [viewerId, thread.groupId, 'message_sent', JSON.stringify({ eventId: event.event_id })]);
    }
    return reply.code(201).send({ data: { eventId: event.event_id } });
  } catch (error) {
    return sendError(reply, error);
  }
});

const ERROR_MESSAGES: Record<string, string> = {
  UNAUTHENTICATED: 'Oturumun doğrulanamadı.',
  VALIDATION_FAILED: 'İstek geçersiz.',
  INVALID_CURSOR: 'Sayfalama anahtarı geçersiz.',
  SELF_DIRECT_MESSAGE_NOT_ALLOWED: 'Kendine mesaj gönderemezsin.',
  USER_NOT_AVAILABLE: 'Bu kullanıcıya şu anda mesaj gönderilemiyor.',
  DIRECT_MESSAGE_NOT_ALLOWED: 'Bu kullanıcıyla mesajlaşamazsın.',
  CONVERSATION_NOT_FOUND: 'Konuşma bulunamadı.',
  GROUP_NOT_FOUND: 'Grup bulunamadı.',
  JOIN_REQUEST_NOT_FOUND: 'Bekleyen katılım isteği bulunamadı.',
  GROUP_OWNER_CANNOT_LEAVE: 'Grubun kurucusu gruptan ayrılamaz.',
  MESSAGING_BUSY: 'Mesajlaşma yoğun, lütfen tekrar dene.',
  MESSAGING_UNAVAILABLE: 'Mesajlaşma şu anda kullanılamıyor.',
};

function sendError(reply: { code: (status: number) => { send: (body: unknown) => unknown } }, error: unknown) {
  // A malformed request is the client's fault; reporting it as 503 hid real
  // validation bugs behind a retryable status.
  const known = error instanceof z.ZodError
    ? new HttpError(400, 'VALIDATION_FAILED')
    : error instanceof HttpError
      ? error
      : new HttpError(503, 'MESSAGING_UNAVAILABLE');
  if (!(error instanceof HttpError) && !(error instanceof z.ZodError)) {
    app.log.error({ err: error }, 'Unhandled messaging gateway failure');
  }
  return reply.code(known.statusCode).send({ error: { code: known.code, message: ERROR_MESSAGES[known.code] ?? ERROR_MESSAGES.MESSAGING_UNAVAILABLE } });
}

/**
 * Confirms that MATRIX_SERVER_NAME matches the homeserver's own `server_name`.
 *
 * These two values live in different systems (Key Vault and homeserver.yaml)
 * and a mismatch is invisible until the first user tries to send a message,
 * because every register and impersonation call is rejected with M_EXCLUSIVE.
 * An unreachable homeserver is only a warning — Synapse may still be starting —
 * but a reachable homeserver that disagrees is a hard configuration error.
 */
async function assertMatrixServerName(): Promise<void> {
  let whoami: { user_id?: string };
  try {
    whoami = await matrixRequest<{ user_id?: string }>('/_matrix/client/v3/account/whoami');
  } catch {
    app.log.warn({ matrixServerName }, 'Could not verify Matrix server name at startup; homeserver unreachable');
    return;
  }
  const advertised = whoami.user_id?.split(':').slice(1).join(':');
  if (advertised && advertised !== matrixServerName) {
    app.log.fatal({ configured: matrixServerName, advertised }, 'MATRIX_SERVER_NAME does not match the homeserver server_name');
    throw new Error(`MATRIX_SERVER_NAME mismatch: configured ${matrixServerName}, homeserver reports ${advertised}`);
  }
}

// Verified before the port opens so a misconfigured revision never reports
// healthy to Container Apps and never takes traffic.
await assertMatrixServerName();

const port = Number(process.env.PORT ?? 8080);
await app.listen({ port, host: '0.0.0.0' });

const shutdown = async (signal: string) => {
  app.log.info({ signal }, 'Messaging gateway stopping');
  await app.close();
  await pool.end().catch(() => undefined);
  process.exit(0);
};
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
