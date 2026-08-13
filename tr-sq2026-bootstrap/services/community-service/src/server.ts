import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import { randomUUID } from 'node:crypto';
import { importJWK, jwtVerify } from 'jose';
import { z } from 'zod';
import type pg from 'pg';
import { createDatabasePool } from './database.js';
import { closeServiceBus, isMessagingProjectionConfigured, sendMessagingProjectionEvent } from './infrastructure/azureServiceBus.js';
import { generateMediaUploadSasUrl, generateMediaReadSasUrl, headMediaBlob } from './infrastructure/azureBlob.js';
import { getIdentityVerificationKey } from './infrastructure/azureKeyVault.js';
import { advanceProgress, awardBadge, recomputeScore, reporterTrust, touchStreak } from './journey.js';

const required = (key: string) => { const value = process.env[key]; if (!value) throw new Error(`Missing ${key}`); return value; };
const db = createDatabasePool();
const identityVerificationKey = await (async () => {
  const jwk = await getIdentityVerificationKey();
  return importJWK(jwk, 'RS256');
})();
const app = Fastify({ logger: { redact: ['req.headers.authorization'] } });
const feedQuery = z.object({ mode: z.enum(['forYou', 'nearby', 'following']).default('forYou'), cursor: z.string().max(128).optional(), limit: z.coerce.number().int().min(1).max(50).default(20) });
const interactionBody = z.object({ enabled: z.boolean(), idempotencyKey: z.string().uuid() });
const shareBody = z.object({ idempotencyKey: z.string().uuid() });
const postBody = z.object({ body:z.string().trim().min(1).max(2200), visibility:z.enum(['public','friends_only']).default('public'), locationLabel:z.string().trim().max(120).optional(), locationRegionCode:z.string().trim().regex(/^[A-Za-z]{2}$/).optional(), marketplaceListingId:z.string().uuid().optional(), poll:z.object({ question:z.string().trim().min(1).max(300), selectionMode:z.enum(['single','multiple']), options:z.array(z.string().trim().min(1).max(160)).min(2).max(4), closesAt:z.string().datetime().optional() }).optional(), idempotencyKey:z.string().uuid() });
const storyBody=z.object({mediaId:z.string().uuid(),visibility:z.enum(['network','public']),ttlHours:z.union([z.literal(6),z.literal(12),z.literal(24)]),excludedUserIds:z.array(z.string().uuid()).max(200).default([])});
const storyQuery=z.object({cursor:z.string().max(128).optional(),limit:z.coerce.number().int().min(1).max(50).default(30)});
const storyAudienceContactsQuery=z.object({limit:z.coerce.number().int().min(1).max(200).default(100)});
const storyAudienceExclusionsBody=z.object({excludedUserIds:z.array(z.string().uuid()).max(200)});
const storyHighlightBody=z.object({title:z.string().trim().min(1).max(40),visibility:z.enum(['network','public']).default('network'),storyIds:z.array(z.string().uuid()).min(1).max(20)});
const mediaPresignBody=z.object({
  kind:z.literal('image'),
  contentType:z.enum(['image/jpeg','image/png','image/webp']),
  fileName:z.string().trim().min(1).max(180),
  sizeBytes:z.coerce.number().int().min(1).max(10 * 1024 * 1024),
  sha256:z.string().regex(/^[a-fA-F0-9]{64}$/),
});
const mediaCompleteBody=z.object({uploadId:z.string().uuid()});
const commentBody=z.object({body:z.string().trim().min(1).max(1000),parentId:z.string().uuid().optional()});
const listingBody=z.object({title:z.string().trim().min(3).max(140),description:z.string().trim().min(10).max(4000),price:z.coerce.number().nonnegative(),city:z.string().trim().min(2).max(100).optional(),regionCode:z.string().regex(/^[A-Za-z]{2}$/).optional()});
const listingQuery=z.object({cursor:z.string().max(128).optional(),limit:z.coerce.number().int().min(1).max(50).default(20)});
const auctionBody=z.object({startingPrice:z.coerce.number().nonnegative(),minimumIncrement:z.coerce.number().positive(),startsAt:z.string().datetime(),endsAt:z.string().datetime()}).refine((v)=>Date.parse(v.endsAt)>Date.parse(v.startsAt));
const bidBody=z.object({amount:z.coerce.number().positive()});
const gateworkSystemAccountBody=z.object({principalId:z.string().uuid(),displayName:z.string().trim().min(2).max(100),reason:z.string().trim().min(5).max(500),idempotencyKey:z.string().uuid()});
const gateworkPostBody=z.object({authorId:z.string().uuid(),body:z.string().trim().min(1).max(2200),visibility:z.enum(['public','friends_only']).default('public'),regionCode:z.string().trim().regex(/^[A-Za-z]{2}$/).optional(),reason:z.string().trim().min(5).max(500),idempotencyKey:z.string().uuid()});
const decodeCursor = (cursor?: string) => { if (!cursor) return null; try { const [createdAt, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|'); if (!createdAt || !id) throw Error(); return { createdAt, id }; } catch { throw Object.assign(new Error('Invalid cursor'), { statusCode: 400 }); } };
const encodeCursor = (row: { created_at: Date; id: string }) => Buffer.from(`${row.created_at.toISOString()}|${row.id}`).toString('base64url');
const sha256Base64 = (hex: string) => Buffer.from(hex, 'hex').toString('base64');
const mediaObjectUrl = async (safeUrlOrKey: string) => {
  if (/^https:\/\//.test(safeUrlOrKey)) return safeUrlOrKey;
  return generateMediaReadSasUrl(safeUrlOrKey, 300);
};

async function viewer(headers: { authorization?: string }) { const token = headers.authorization?.replace(/^Bearer\s+/i, ''); if (!token) throw Error('UNAUTHORIZED'); const verified = await jwtVerify(token, identityVerificationKey, { issuer: required('JWT_ISSUER'), audience: required('JWT_AUDIENCE'), algorithms: ['RS256'] }); if (!verified.payload.sub) throw Error('UNAUTHORIZED'); return verified.payload.sub; }
type GateworkRole='owner'|'security_admin'|'operations_admin'|'content_editor'|'moderator'|'analyst'|'auditor';
const gateworkRoles=new Set<GateworkRole>(['owner','security_admin','operations_admin','content_editor','moderator','analyst','auditor']);
async function gateworkActor(headers:{authorization?:string}) { const token=headers.authorization?.replace(/^Bearer\s+/i,''); if(!token) throw Error('UNAUTHORIZED'); const verified=await jwtVerify(token,identityVerificationKey,{issuer:required('JWT_ISSUER'),audience:required('GATEWORK_JWT_AUDIENCE'),algorithms:['RS256']}); const actorId=verified.payload.sub; const scopes=Array.isArray(verified.payload.scope)?verified.payload.scope.filter((v):v is GateworkRole=>typeof v==='string'&&gateworkRoles.has(v as GateworkRole)):[]; if(!actorId||!scopes.length) throw Error('UNAUTHORIZED'); return {actorId,roles:scopes}; }
const requireGateworkRole=(actor:{roles:GateworkRole[]},allowed:GateworkRole[])=>{if(!actor.roles.some((role)=>allowed.includes(role)))throw Error('FORBIDDEN');};
async function auditGateworkOperation(input:{actorId:string;roles:GateworkRole[];action:string;targetType:string;targetId:string;reason?:string;requestId?:string;rayId?:string;outcome:'succeeded'|'denied'|'failed'}){await db.query('INSERT INTO gatework_operation_audit_events(actor_id,actor_roles,action,target_type,target_id,reason,request_id,cloudflare_ray_id,outcome) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)',[input.actorId,input.roles,input.action,input.targetType,input.targetId,input.reason??null,input.requestId??null,input.rayId??null,input.outcome]);}
await app.register(helmet); await app.register(rateLimit, { global: true, max: 120, timeWindow: '1 minute' });
await app.register(cors, {
  origin: (origin, callback) => {
    if (!origin || origin === 'https://turksquare.com' || origin === 'https://www.turksquare.com' || /^http:\/\/localhost:\d+$/.test(origin)) {
      callback(null, true);
      return;
    }
    callback(null, false);
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type', 'Idempotency-Key'],
  maxAge: 600,
});

app.get('/health', { config: { rateLimit: false } }, async (_request, reply) => {
  try {
    await db.query('SELECT 1');
    return { status: 'ok' };
  } catch (error) {
    app.log.warn({ err: error }, 'Community health check failed');
    return reply.code(503).send({ status: 'unavailable' });
  }
});

app.post('/v1/internal/gatework/system-accounts', { config: { rateLimit: { max: 10, timeWindow: '1 hour' } } }, async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const input = gateworkSystemAccountBody.parse(request.body);
    const client = await db.connect();
    try {
      await client.query('BEGIN');
      const prior = await client.query<{ result_id: string | null }>(
        "SELECT result_id FROM gatework_command_dedup WHERE actor_id=$1 AND idempotency_key=$2 AND command_type='system_account.create' FOR UPDATE",
        [actor.actorId, input.idempotencyKey],
      );
      if (prior.rows[0]?.result_id) {
        await client.query('COMMIT');
        return reply.code(200).send({ data: { id: prior.rows[0].result_id } });
      }
      await client.query("INSERT INTO community_system_accounts(user_id,role,active) VALUES($1,'official',true) ON CONFLICT(user_id) DO UPDATE SET active=true", [input.principalId]);
      await client.query("INSERT INTO community_profile_projection(user_id,display_name,region_code,interests,updated_at) VALUES($1,$2,'US','{}',now()) ON CONFLICT(user_id) DO UPDATE SET display_name=EXCLUDED.display_name,updated_at=now()", [input.principalId, input.displayName]);
      await client.query("INSERT INTO gatework_command_dedup(actor_id,idempotency_key,command_type,result_id) VALUES($1,$2,'system_account.create',$3)", [actor.actorId, input.idempotencyKey, input.principalId]);
      await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'system_account.activate', targetType: 'system_account', targetId: input.principalId, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
      await client.query('COMMIT');
      return reply.code(201).send({ data: { id: input.principalId } });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'GATEWORK_SYSTEM_ACCOUNT_REJECTED' } });
  }
});

app.post('/v1/internal/gatework/posts', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const input = gateworkPostBody.parse(request.body);
    const client = await db.connect();
    try {
      await client.query('BEGIN');
      const prior = await client.query<{ result_id: string | null }>("SELECT result_id FROM gatework_command_dedup WHERE actor_id=$1 AND idempotency_key=$2 AND command_type='official_post.create' FOR UPDATE", [actor.actorId, input.idempotencyKey]);
      if (prior.rows[0]?.result_id) {
        await client.query('COMMIT');
        return reply.code(200).send({ data: { id: prior.rows[0].result_id } });
      }
      const official = await client.query("SELECT 1 FROM community_system_accounts WHERE user_id=$1 AND role='official' AND active", [input.authorId]);
      if (!official.rows[0]) throw Error('OFFICIAL_NOT_ACTIVE');
      const post = await client.query<{ id: string }>("INSERT INTO community_posts(author_id,kind,visibility,body,region_code) VALUES($1,'standard',$2,$3,$4) RETURNING id", [input.authorId, input.visibility, input.body, input.regionCode?.toUpperCase() ?? null]);
      await client.query("INSERT INTO gatework_command_dedup(actor_id,idempotency_key,command_type,result_id) VALUES($1,$2,'official_post.create',$3)", [actor.actorId, input.idempotencyKey, post.rows[0]!.id]);
      await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'official_post.publish', targetType: 'post', targetId: post.rows[0]!.id, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
      await client.query('COMMIT');
      return reply.code(201).send({ data: post.rows[0] });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'GATEWORK_POST_REJECTED' } });
  }
});

// A client can upload only a declared image to a private quarantine prefix.
// The final safe object is created by a separate media processor after scan
// and EXIF stripping; it is never the object addressed by this presigned URL.
app.post('/v1/media/uploads/presign', { config: { rateLimit: { max: 12, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const input = mediaPresignBody.parse(request.body);
    const mediaId = randomUUID();
    const uploadId = randomUUID();
    const quarantineKey = `uploads/quarantine/${userId}/${mediaId}`;
    const checksum = sha256Base64(input.sha256.toLowerCase());
    const client = await db.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        "INSERT INTO media_assets(id,owner_id,status,kind) VALUES($1,$2,'quarantined',$3)",
        [mediaId, userId, input.kind],
      );
      await client.query(
        "INSERT INTO media_upload_sessions(id,media_id,owner_id,quarantine_key,expected_sha256,expected_size_bytes,content_type,expires_at) VALUES($1,$2,$3,$4,$5,$6,$7,now()+interval '5 minutes')",
        [uploadId, mediaId, userId, quarantineKey, Buffer.from(input.sha256, 'hex'), input.sizeBytes, input.contentType],
      );
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
        const uploadUrl = await generateMediaUploadSasUrl(
      quarantineKey,
      input.contentType,
      input.sizeBytes,
      checksum,
      300
    );
    return reply.code(201).send({
      data: {
        uploadId,
        mediaId,
        uploadUrl,
        expiresInSeconds: 300,
        requiredHeaders: {
          'content-type': input.contentType,
          'x-amz-checksum-sha256': checksum,
        },
      },
    });
  } catch (error) {
    return reply.code((error as { statusCode?: number }).statusCode ?? 400).send({
      error: { code: 'MEDIA_UPLOAD_NOT_ACCEPTED', message: 'Medya yükleme isteği kabul edilemedi.' },
    });
  }
});

app.post('/v1/media/uploads/complete', { config: { rateLimit: { max: 12, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const { uploadId } = mediaCompleteBody.parse(request.body);
    const client = await db.connect();
    let row: {
      media_id: string; quarantine_key: string; expected_sha256: Buffer; expected_size_bytes: string; content_type: string; expires_at: Date; completed_at: Date | null;
    } | undefined;
    try {
    await client.query('BEGIN');
    const session = await client.query<{
      media_id: string; quarantine_key: string; expected_sha256: Buffer; expected_size_bytes: string; content_type: string; expires_at: Date; completed_at: Date | null;
    }>(
      'SELECT media_id,quarantine_key,expected_sha256,expected_size_bytes,content_type,expires_at,completed_at FROM media_upload_sessions WHERE id=$1 AND owner_id=$2 FOR UPDATE',
      [uploadId, userId],
    );
    row = session.rows[0];
    if (!row || row.expires_at <= new Date()) {
      await client.query('ROLLBACK');
      return reply.code(410).send({ error: { code: 'UPLOAD_EXPIRED', message: 'Yükleme süresi doldu.' } });
    }
    if (row.completed_at) {
      await client.query('COMMIT');
      return { data: { mediaId: row.media_id, status: 'scanning' } };
    }
        const head = await headMediaBlob(row.quarantine_key);
    if (head.contentLength !== Number(row.expected_size_bytes) || head.contentType !== row.content_type || head.checksumSha256 !== row.expected_sha256.toString('base64')) {
      await client.query('ROLLBACK');
      return reply.code(400).send({ error: { code: 'UPLOAD_VALIDATION_FAILED', message: 'Yüklenen dosya doğrulanamadı.' } });
    }
    await client.query("UPDATE media_upload_sessions SET completed_at=now() WHERE id=$1 AND completed_at IS NULL", [uploadId]);
    await client.query("UPDATE media_assets SET status='scanning' WHERE id=$1 AND owner_id=$2 AND status='quarantined'", [row.media_id, userId]);
    await client.query("INSERT INTO media_processing_jobs(media_id,job_type,status) VALUES($1,'scan','queued') ON CONFLICT DO NOTHING", [row.media_id]);
    await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
    return reply.code(202).send({ data: { mediaId: row!.media_id, status: 'scanning' } });
  } catch (error) {
    return reply.code((error as { statusCode?: number }).statusCode ?? 400).send({
      error: { code: 'MEDIA_COMPLETE_FAILED', message: 'Medya doğrulama kuyruğa alınamadı.' },
    });
  }
});

// Media IDs are not a sharing mechanism. The owner can poll this endpoint
// while an upload is processed; everyone else receives media through an
// already-authorized Community object such as a visible Story.
app.get('/v1/media/:id', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const mediaId = z.string().uuid().parse((request.params as { id: string }).id);
    const media = await db.query<{
      id: string;
      status: 'quarantined' | 'scanning' | 'ready' | 'rejected';
      kind: 'image' | 'video';
      safe_url: string | null;
      thumbnail_url: string | null;
    }>(
      'SELECT id,status,kind,safe_url,thumbnail_url FROM media_assets WHERE id=$1 AND owner_id=$2',
      [mediaId, userId],
    );
    const row = media.rows[0];
    if (!row) {
      return reply.code(404).send({
        error: { code: 'MEDIA_NOT_FOUND', message: 'Medya bulunamadı.' },
      });
    }
    return {
      data: {
        id: row.id,
        status: row.status,
        kind: row.kind,
        url: row.status === 'ready' && row.safe_url
            ? await mediaObjectUrl(row.safe_url)
            : null,
        thumbnailUrl: row.status === 'ready' && row.thumbnail_url
            ? await mediaObjectUrl(row.thumbnail_url)
            : null,
      },
    };
  } catch (error) {
    return reply.code((error as { statusCode?: number }).statusCode ?? 400).send({
      error: { code: 'MEDIA_STATUS_FAILED', message: 'Medya durumu okunamadı.' },
    });
  }
});

// The home surface deliberately returns aggregates, not a copy of full Feed
// records. A new member gets an explicit empty state instead of placeholder
// people, stories, listings or auctions.
app.get('/v1/community/home/summary', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const [profile, connections, localPosts, stories] = await Promise.all([
      db.query<{ city: string; region_code: string; interests: string[] }>('SELECT city,region_code,interests FROM community_profile_projection WHERE user_id=$1', [userId]),
      db.query<{ count: string }>('SELECT count(*) FROM relationship_projection WHERE viewer_id=$1 AND active', [userId]),
      db.query<{ count: string }>(`SELECT count(*) FROM community_posts p JOIN community_profile_projection v ON v.user_id=$1 WHERE p.deleted_at IS NULL AND p.archived_at IS NULL AND p.moderation_state='active' AND p.region_code=v.region_code`, [userId]),
      db.query<{ count: string }>(`SELECT count(*) FROM stories s JOIN relationship_projection r ON r.subject_id=s.author_id WHERE r.viewer_id=$1 AND r.active AND s.expires_at>now()`, [userId]),
    ]);
    const locality = profile.rows[0];
    return {
      data: {
        locality: locality ? { city: locality.city, regionCode: locality.region_code } : null,
        interests: locality?.interests ?? [],
        counts: { connections: Number(connections.rows[0]?.count ?? 0), localPosts: Number(localPosts.rows[0]?.count ?? 0), activeStories: Number(stories.rows[0]?.count ?? 0) },
        isNewMember: Number(connections.rows[0]?.count ?? 0) === 0,
        actions: ['discover_local_feed', 'follow_members', 'create_first_post'],
      },
    };
  } catch {
    return reply.code(401).send({ error: { code: 'HOME_SUMMARY_UNAVAILABLE', message: 'Ana sayfa özeti yüklenemedi.' } });
  }
});

// Verification outcomes are projected into Community by the durable outbox
// worker. The mobile client reads this projection only; it never decides that
// a member is verified or eligible to open an auction by itself.
app.get('/v1/community/me/capabilities', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const result = await db.query<{
      identity_verified: boolean;
      auction_seller_eligible: boolean;
      updated_at: Date;
    }>(
      `SELECT identity_verified, auction_seller_eligible, updated_at
       FROM member_capabilities
       WHERE user_id=$1`,
      [userId],
    );
    const capabilities = result.rows[0];
    return {
      data: {
        identityVerified: capabilities?.identity_verified ?? false,
        auctionSellerEligible: capabilities?.auction_seller_eligible ?? false,
        updatedAt: capabilities?.updated_at?.toISOString() ?? null,
      },
    };
  } catch {
    return reply.code(401).send({
      error: {
        code: 'CAPABILITIES_UNAVAILABLE',
        message: 'Hesap yetkileri yüklenemedi.',
      },
    });
  }
});

app.get('/v1/community/feed', async (request, reply) => {
  try {
    const userId = await viewer(request.headers); const input = feedQuery.parse(request.query); const cursor = decodeCursor(input.cursor);
    const params: unknown[] = [userId]; let where = `p.deleted_at IS NULL AND p.archived_at IS NULL AND p.moderation_state='active' AND (p.visibility='public' OR EXISTS (SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=p.author_id AND r.relationship='friend' AND r.active))`;
    if (input.mode === 'following') where += ` AND EXISTS (SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=p.author_id AND r.active)`;
    if (input.mode === 'nearby') where += ` AND p.location_cell IS NOT NULL AND ST_DWithin(p.location_cell,(SELECT approximate_cell FROM viewer_location_projection WHERE user_id=$1),50000)`;
    if (cursor) { params.push(cursor.createdAt, cursor.id); where += ` AND (p.created_at,p.id) < ($${params.length - 1}::timestamptz,$${params.length}::uuid)`; }
    params.push(input.limit + 1);
    const result = await db.query<{ id: string; created_at: Date; body: string; location_label: string | null; author_name: string; likes: string; comments: string; is_liked: boolean }>(`SELECT p.id,p.created_at,p.body,p.location_label,COALESCE(cp.display_name,'TurkSquare üyesi') author_name,(SELECT count(*) FROM post_reactions x WHERE x.post_id=p.id AND x.kind='like') likes,0 comments,EXISTS(SELECT 1 FROM post_reactions x WHERE x.post_id=p.id AND x.actor_id=$1 AND x.kind='like') is_liked FROM community_posts p LEFT JOIN community_profile_projection cp ON cp.user_id=p.author_id LEFT JOIN community_profile_projection viewer_profile ON viewer_profile.user_id=$1 WHERE ${where} ORDER BY (EXTRACT(EPOCH FROM p.created_at) + CASE WHEN p.region_code IS NOT NULL AND p.region_code=viewer_profile.region_code THEN 1800 ELSE 0 END + CASE WHEN cp.interests && viewer_profile.interests THEN 600 ELSE 0 END) DESC,p.id DESC LIMIT $${params.length}`, params);
    const page = result.rows.slice(0, input.limit); const next = result.rows.length > input.limit ? encodeCursor(page[page.length - 1]!) : null;
    return { data: page.map((p) => ({ id:p.id, authorName:p.author_name, location:p.location_label ?? '', createdAtLabel:p.created_at.toISOString(), message:p.body, likes:Number(p.likes), comments:Number(p.comments), isLiked:p.is_liked })), meta: { nextCursor: next } };
  } catch (error) { return reply.code((error as { statusCode?: number }).statusCode ?? 401).send({ error: { code: 'FEED_UNAVAILABLE', message: 'Akış yüklenemedi.' } }); }
});

app.put('/v1/community/posts/:id/reactions/:kind', async (request, reply) => {
  try { const userId = await viewer(request.headers); const postId = z.string().uuid().parse((request.params as { id: string }).id); const kind = z.enum(['like','save']).parse((request.params as { kind: string }).kind); const input = interactionBody.parse(request.body);
    if (input.enabled) await db.query('INSERT INTO post_reactions(post_id,actor_id,kind) SELECT $1,$2,$3 WHERE EXISTS(SELECT 1 FROM community_posts WHERE id=$1 AND deleted_at IS NULL) ON CONFLICT DO NOTHING', [postId,userId,kind]);
    else await db.query('DELETE FROM post_reactions WHERE post_id=$1 AND actor_id=$2 AND kind=$3', [postId,userId,kind]);
    // Gozcu wants five *different* posts, so the counter is a DISTINCT count and
    // not a tally of taps. Un-reacting therefore walks the progress back, which
    // is the honest reading of "five posts you interacted with".
    if (input.enabled) void grantInBackground('reaction', async (journey) => {
      await touchStreak(journey, userId);
      const seen = await journey.query<{ count: string }>('SELECT count(DISTINCT post_id) FROM post_reactions WHERE actor_id=$1', [userId]);
      await advanceProgress(journey, userId, 'observer', Number(seen.rows[0]!.count), { absolute: true });
    });
    return reply.code(204).send();
  } catch { return reply.code(400).send({ error: { code:'INTERACTION_FAILED', message:'Etkileşim kaydedilemedi.' } }); }
});

app.post('/v1/community/posts/:id/shares', async (request, reply) => {
  try { const userId = await viewer(request.headers); const postId = z.string().uuid().parse((request.params as { id: string }).id); const input = shareBody.parse(request.body);
    await db.query('INSERT INTO post_shares(post_id,actor_id,idempotency_key) SELECT $1,$2,$3 WHERE EXISTS(SELECT 1 FROM community_posts WHERE id=$1 AND deleted_at IS NULL) ON CONFLICT(actor_id,idempotency_key) DO NOTHING', [postId,userId,input.idempotencyKey]);
    return reply.code(204).send();
  } catch { return reply.code(400).send({ error: { code:'SHARE_FAILED', message:'Paylaşım kaydedilemedi.' } }); }
});
app.delete('/v1/community/posts/:id',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);await db.query('UPDATE community_posts SET deleted_at=now() WHERE id=$1 AND author_id=$2 AND deleted_at IS NULL',[id,userId]);return reply.code(204).send();}catch{return reply.code(400).send();}});
app.post('/v1/community/posts', async (request, reply) => {
  try { const userId = await viewer(request.headers);
    // A restriction that only writes a row is theatre. This is the check that
    // makes "eject the abusive user" real: a moderator's decision has to stop
    // the next post, not just record an opinion about the last one.
    const restricted = await activeRestriction(userId); if (restricted) return reply.code(403).send(restrictionError(restricted));
    const input = postBody.parse(request.body); const client = await db.connect(); try { await client.query('BEGIN');
    if (input.marketplaceListingId) { const listing = await client.query('SELECT 1 FROM marketplace_listing_projection WHERE listing_id=$1 AND owner_id=$2 AND status=\'active\'', [input.marketplaceListingId,userId]); if (!listing.rows[0]) return reply.code(403).send({error:{code:'LISTING_NOT_AVAILABLE',message:'Aktif ilan bulunamadı.'}}); }
    const kind = input.poll ? 'poll' : input.marketplaceListingId ? 'marketplace_listing' : 'standard'; const result = await client.query<{id:string}>('INSERT INTO community_posts(author_id,kind,visibility,body,location_label,region_code,marketplace_listing_id) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id',[userId,kind,input.visibility,input.body,input.locationLabel??null,input.locationRegionCode?.toUpperCase()??null,input.marketplaceListingId??null]); const id=result.rows[0]!.id;
    if(input.poll){const poll=await client.query<{post_id:string}>('INSERT INTO post_polls(post_id,selection_mode,closes_at) VALUES($1,$2,$3) RETURNING post_id',[id,input.poll.selectionMode,input.poll.closesAt??null]); for(const [ordinal,label] of input.poll.options.entries()) await client.query('INSERT INTO post_poll_options(post_id,ordinal,label) VALUES($1,$2,$3)',[poll.rows[0]!.post_id,ordinal,label]);}
    await client.query('COMMIT');
    // Awarded after the commit, in its own transaction: the post is the member's
    // work and it is already saved. Kirk Ambar counts from COUNT(*) rather than
    // adding one, so a retried request cannot inflate it.
    void grantInBackground('post', async (journey) => {
      await touchStreak(journey, userId);
      await awardBadge(journey, userId, 'welcome_neighbor');
      const total = await journey.query<{ count: string }>("SELECT count(*) FROM community_posts WHERE author_id=$1 AND deleted_at IS NULL", [userId]);
      await advanceProgress(journey, userId, 'content_machine', Number(total.rows[0]!.count), { absolute: true });
    });
    return reply.code(201).send({data:{id}});
  } catch(e){await client.query('ROLLBACK');throw e;} finally{client.release();} } catch { return reply.code(400).send({error:{code:'POST_CREATE_FAILED',message:'Paylaşım oluşturulamadı.'}}); }
});
app.post('/v1/community/posts/:postId/poll/votes', async (request, reply) => {
  try {const userId=await viewer(request.headers);const postId=z.string().uuid().parse((request.params as {postId:string}).postId);const input=z.object({optionIds:z.array(z.string().uuid()).min(1).max(4)}).parse(request.body);const client=await db.connect();try{await client.query('BEGIN');const poll=await client.query<{selection_mode:string;closes_at:Date|null}>('SELECT selection_mode,closes_at FROM post_polls WHERE post_id=$1 FOR UPDATE',[postId]);if(!poll.rows[0]||(poll.rows[0].closes_at&&poll.rows[0].closes_at<=new Date())||(poll.rows[0].selection_mode==='single'&&input.optionIds.length!==1))throw Error();const valid=await client.query('SELECT id FROM post_poll_options WHERE post_id=$1 AND id=ANY($2::uuid[])',[postId,input.optionIds]);if(valid.rows.length!==input.optionIds.length)throw Error();await client.query('DELETE FROM post_poll_votes WHERE voter_id=$1 AND option_id IN (SELECT id FROM post_poll_options WHERE post_id=$2)',[userId,postId]);for(const id of input.optionIds)await client.query('INSERT INTO post_poll_votes(option_id,voter_id) VALUES($1,$2)',[id,userId]);await client.query('COMMIT');return reply.code(204).send();}catch(e){await client.query('ROLLBACK');throw e;}finally{client.release();}}catch{return reply.code(400).send({error:{code:'POLL_VOTE_FAILED',message:'Anket oyu kaydedilemedi.'}});}
});
const storyAccessWhere = (storyAlias: string, viewerParam: string) => `(${storyAlias}.author_id=${viewerParam} OR (NOT EXISTS(SELECT 1 FROM story_audience_exclusions x WHERE x.story_id=${storyAlias}.id AND x.excluded_user_id=${viewerParam}) AND (EXISTS(SELECT 1 FROM relationship_projection r WHERE r.viewer_id=${viewerParam} AND r.subject_id=${storyAlias}.author_id AND r.active) OR EXISTS(SELECT 1 FROM community_system_accounts o WHERE o.user_id=${storyAlias}.author_id AND o.role='official' AND o.active) OR (${storyAlias}.visibility='public' AND ${storyAlias}.region_code=(SELECT region_code FROM community_profile_projection WHERE user_id=${viewerParam}))))`;
app.get('/v1/community/stories', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const input = storyQuery.parse(request.query);
    const cursor = decodeCursor(input.cursor);
    const params: unknown[] = [userId];
    let where = `s.expires_at>now() AND m.status='ready' AND ${storyAccessWhere('s', '$1')}`;
    if (cursor) {
      params.push(cursor.createdAt, cursor.id);
      where += ` AND (s.created_at,s.id)<($${params.length - 1}::timestamptz,$${params.length}::uuid)`;
    }
    params.push(input.limit + 1);
    const rows = await db.query<{ id: string; author_id: string; author_name: string; created_at: Date; expires_at: Date; visibility: 'network' | 'public'; safe_url: string; thumbnail_url: string | null; kind: 'image' | 'video'; like_count: string; is_liked: boolean; is_viewed: boolean; source: 'self' | 'official' | 'network' | 'local' }>(
      `SELECT s.id,s.author_id,COALESCE(p.display_name,'TurkSquare üyesi') author_name,s.created_at,s.expires_at,s.visibility,m.safe_url,m.thumbnail_url,m.kind,(SELECT count(*) FROM story_likes l WHERE l.story_id=s.id) like_count,EXISTS(SELECT 1 FROM story_likes l WHERE l.story_id=s.id AND l.actor_id=$1) is_liked,EXISTS(SELECT 1 FROM story_views v WHERE v.story_id=s.id AND v.viewer_id=$1) is_viewed,CASE WHEN s.author_id=$1 THEN 'self' WHEN EXISTS(SELECT 1 FROM community_system_accounts o WHERE o.user_id=s.author_id AND o.role='official' AND o.active) THEN 'official' WHEN EXISTS(SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=s.author_id AND r.active) THEN 'network' ELSE 'local' END source FROM stories s JOIN media_assets m ON m.id=s.media_id LEFT JOIN community_profile_projection p ON p.user_id=s.author_id WHERE ${where} ORDER BY s.created_at DESC,s.id DESC LIMIT $${params.length}`,
      params,
    );
    const page = rows.rows.slice(0, input.limit);
    const data = await Promise.all(page.map(async (story) => ({
      id: story.id,
      authorId: story.author_id,
      authorName: story.author_name,
      createdAt: story.created_at.toISOString(),
      expiresAt: story.expires_at.toISOString(),
      visibility: story.visibility,
      media: {
        id: story.id,
        type: story.kind,
        url: await mediaObjectUrl(story.safe_url),
        thumbnailUrl: story.thumbnail_url ? await mediaObjectUrl(story.thumbnail_url) : null,
      },
      likeCount: Number(story.like_count),
      isLiked: story.is_liked,
      isViewed: story.is_viewed,
      source: story.source,
    })));
    return { data, meta: { nextCursor: rows.rows.length > input.limit ? encodeCursor(page[page.length - 1]!) : null } };
  } catch (error) {
    return reply.code((error as { statusCode?: number }).statusCode ?? 401).send({
      error: { code: 'STORIES_FAILED', message: 'Story yüklenemedi.' },
    });
  }
});
// This endpoint is intentionally restricted to the signed-in member's active
// relationship projection. Story privacy must not turn into a public member
// directory or allow arbitrary account discovery.
app.get('/v1/community/me/story-audience-contacts', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const { limit } = storyAudienceContactsQuery.parse(request.query);
    const contacts = await db.query<{ id: string; display_name: string }>(
      `SELECT r.subject_id id,COALESCE(p.display_name,'TurkSquare üyesi') display_name
       FROM relationship_projection r
       LEFT JOIN community_profile_projection p ON p.user_id=r.subject_id
       WHERE r.viewer_id=$1 AND r.active
       ORDER BY p.display_name NULLS LAST,r.subject_id
       LIMIT $2`,
      [userId, limit],
    );
    return { data: contacts.rows.map((contact) => ({ id: contact.id, displayName: contact.display_name })) };
  } catch {
    return reply.code(400).send({ error: { code: 'STORY_AUDIENCE_CONTACTS_UNAVAILABLE', message: 'Story gizlilik kişileri yüklenemedi.' } });
  }
});
app.post('/v1/community/stories',async(request,reply)=>{const client=await db.connect();try{const userId=await viewer(request.headers);const restricted=await activeRestriction(userId);if(restricted)return reply.code(403).send(restrictionError(restricted));const input=storyBody.parse(request.body);await client.query('BEGIN');const media=await client.query('SELECT 1 FROM media_assets WHERE id=$1 AND owner_id=$2 AND status=\'ready\' FOR KEY SHARE',[input.mediaId,userId]);if(!media.rows[0]){await client.query('ROLLBACK');return reply.code(400).send({error:{code:'MEDIA_NOT_READY',message:'Medya hazır değil.'}});}const r=await client.query<{id:string}>('INSERT INTO stories(author_id,media_id,visibility,region_code,expires_at) SELECT $1,$2,$3,p.region_code,now()+($4::text||\' hours\')::interval FROM community_profile_projection p WHERE p.user_id=$1 RETURNING id',[userId,input.mediaId,input.visibility,input.ttlHours]);if(!r.rows[0]){await client.query('ROLLBACK');return reply.code(400).send({error:{code:'PROFILE_REQUIRED',message:'Story paylaşmadan önce profil konumunu tamamlayın.'}});}if(input.excludedUserIds.length)await client.query('INSERT INTO story_audience_exclusions(story_id,excluded_user_id) SELECT $1,unnest($2::uuid[]) ON CONFLICT DO NOTHING',[r.rows[0].id,input.excludedUserIds]);await client.query('COMMIT');
  void grantInBackground('story', async (journey) => { await touchStreak(journey, userId); await awardBadge(journey, userId, 'first_spark'); });
  return reply.code(201).send({data:r.rows[0]});}catch{await client.query('ROLLBACK');return reply.code(400).send({error:{code:'STORY_CREATE_FAILED',message:'Story oluşturulamadı.'}});}finally{client.release();}});
// Audience exclusions are an author-controlled deny list. They are checked by
// every Story read/view/like authorization path, never only by the client UI.
app.put('/v1/community/stories/:id/audience/exclusions',{config:{rateLimit:{max:12,timeWindow:'1 minute'}}},async(request,reply)=>{const client=await db.connect();try{const userId=await viewer(request.headers);const storyId=z.string().uuid().parse((request.params as {id:string}).id);const input=storyAudienceExclusionsBody.parse(request.body);await client.query('BEGIN');const story=await client.query('SELECT 1 FROM stories WHERE id=$1 AND author_id=$2 AND expires_at>now() FOR UPDATE',[storyId,userId]);if(!story.rows[0]){await client.query('ROLLBACK');return reply.code(404).send({error:{code:'STORY_NOT_FOUND'}});}await client.query('DELETE FROM story_audience_exclusions WHERE story_id=$1',[storyId]);if(input.excludedUserIds.length)await client.query('INSERT INTO story_audience_exclusions(story_id,excluded_user_id) SELECT $1,unnest($2::uuid[]) ON CONFLICT DO NOTHING',[storyId,input.excludedUserIds]);await client.query('COMMIT');return reply.code(204).send();}catch{await client.query('ROLLBACK');return reply.code(400).send({error:{code:'STORY_AUDIENCE_UPDATE_FAILED',message:'Story görünürlüğü güncellenemedi.'}});}finally{client.release();}});
app.post('/v1/community/story-highlights',{config:{rateLimit:{max:10,timeWindow:'1 minute'}}},async(request,reply)=>{const client=await db.connect();try{const userId=await viewer(request.headers);const input=storyHighlightBody.parse(request.body);await client.query('BEGIN');const owned=await client.query<{id:string;visibility:'network'|'public'}>('SELECT id,visibility FROM stories WHERE author_id=$1 AND id=ANY($2::uuid[])',[userId,input.storyIds]);if(owned.rows.length!==input.storyIds.length||new Set(input.storyIds).size!==input.storyIds.length||(input.visibility==='public'&&owned.rows.some((story)=>story.visibility!=='public'))){await client.query('ROLLBACK');return reply.code(400).send({error:{code:'HIGHLIGHT_STORY_NOT_AVAILABLE',message:'Seçilen Story öne çıkarılamıyor.'}});}const highlight=await client.query<{id:string}>('INSERT INTO story_highlights(owner_id,title,visibility) VALUES($1,$2,$3) RETURNING id',[userId,input.title,input.visibility]);for(const [position,storyId] of input.storyIds.entries())await client.query('INSERT INTO story_highlight_items(highlight_id,story_id,position) VALUES($1,$2,$3)',[highlight.rows[0]!.id,storyId,position]);await client.query('COMMIT');return reply.code(201).send({data:highlight.rows[0]});}catch{await client.query('ROLLBACK');return reply.code(400).send({error:{code:'HIGHLIGHT_CREATE_FAILED',message:'Öne çıkan Story oluşturulamadı.'}});}finally{client.release();}});
app.get('/v1/community/users/:userId/story-highlights',async(request,reply)=>{try{const viewerId=await viewer(request.headers);const ownerId=z.string().uuid().parse((request.params as {userId:string}).userId);const rows=await db.query<{highlight_id:string;title:string;visibility:'network'|'public';created_at:Date;story_id:string;media_id:string;safe_url:string;thumbnail_url:string|null;kind:'image'|'video'}>(`SELECT h.id highlight_id,h.title,h.visibility,h.created_at,si.story_id,m.id media_id,m.safe_url,m.thumbnail_url,m.kind FROM story_highlights h JOIN story_highlight_items si ON si.highlight_id=h.id JOIN stories s ON s.id=si.story_id JOIN media_assets m ON m.id=s.media_id WHERE h.owner_id=$2 AND m.status='ready' AND (h.owner_id=$1 OR (NOT EXISTS(SELECT 1 FROM story_audience_exclusions x WHERE x.story_id=s.id AND x.excluded_user_id=$1) AND (h.visibility='public' OR EXISTS(SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=h.owner_id AND r.active)))) ORDER BY h.created_at DESC,si.position ASC`,[viewerId,ownerId]);const groups=new Map<string,{id:string;title:string;visibility:string;createdAt:string;items:unknown[]}>();for(const row of rows.rows){const group=groups.get(row.highlight_id)??{id:row.highlight_id,title:row.title,visibility:row.visibility,createdAt:row.created_at.toISOString(),items:[]};group.items.push({storyId:row.story_id,media:{id:row.media_id,type:row.kind,url:await mediaObjectUrl(row.safe_url),thumbnailUrl:row.thumbnail_url?await mediaObjectUrl(row.thumbnail_url):null}});groups.set(row.highlight_id,group);}return{data:[...groups.values()]};}catch{return reply.code(400).send({error:{code:'HIGHLIGHTS_UNAVAILABLE',message:'Öne çıkan Storyler yüklenemedi.'}});}});
app.get('/v1/community/me/story-highlights',async(request,reply)=>{try{const userId=await viewer(request.headers);const rows=await db.query<{highlight_id:string;title:string;visibility:'network'|'public';created_at:Date;story_id:string;media_id:string;safe_url:string;thumbnail_url:string|null;kind:'image'|'video'}>(`SELECT h.id highlight_id,h.title,h.visibility,h.created_at,si.story_id,m.id media_id,m.safe_url,m.thumbnail_url,m.kind FROM story_highlights h JOIN story_highlight_items si ON si.highlight_id=h.id JOIN media_assets m ON m.id=(SELECT media_id FROM stories WHERE id=si.story_id) WHERE h.owner_id=$1 AND m.status='ready' ORDER BY h.created_at DESC,si.position ASC`,[userId]);const groups=new Map<string,{id:string;title:string;visibility:string;createdAt:string;items:unknown[]}>();for(const row of rows.rows){const group=groups.get(row.highlight_id)??{id:row.highlight_id,title:row.title,visibility:row.visibility,createdAt:row.created_at.toISOString(),items:[]};group.items.push({storyId:row.story_id,media:{id:row.media_id,type:row.kind,url:await mediaObjectUrl(row.safe_url),thumbnailUrl:row.thumbnail_url?await mediaObjectUrl(row.thumbnail_url):null}});groups.set(row.highlight_id,group);}return{data:[...groups.values()]};}catch{return reply.code(400).send({error:{code:'HIGHLIGHTS_UNAVAILABLE',message:'Öne çıkan Storyler yüklenemedi.'}});}});
app.post('/v1/community/stories/:id/views',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);const access=await db.query(`SELECT 1 FROM stories s WHERE s.id=$1 AND s.expires_at>now() AND ${storyAccessWhere('s','$2')}`,[id,userId]);if(!access.rows[0])return reply.code(404).send({error:{code:'STORY_NOT_FOUND'}});await db.query('INSERT INTO story_views(story_id,viewer_id) VALUES($1,$2) ON CONFLICT DO NOTHING',[id,userId]);return reply.code(204).send();}catch{return reply.code(400).send();}});
app.put('/v1/community/stories/:id/likes',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);const input=interactionBody.parse(request.body);const access=await db.query(`SELECT 1 FROM stories s WHERE s.id=$1 AND s.expires_at>now() AND ${storyAccessWhere('s','$2')}`,[id,userId]);if(!access.rows[0])return reply.code(404).send({error:{code:'STORY_NOT_FOUND'}});if(input.enabled)await db.query('INSERT INTO story_likes(story_id,actor_id) VALUES($1,$2) ON CONFLICT DO NOTHING',[id,userId]);else await db.query('DELETE FROM story_likes WHERE story_id=$1 AND actor_id=$2',[id,userId]);return reply.code(204).send();}catch{return reply.code(400).send();}});
app.get('/v1/community/posts/:id/comments',async(request,reply)=>{try{const userId=await viewer(request.headers);const postId=z.string().uuid().parse((request.params as {id:string}).id);const rows=await db.query('SELECT id,author_id,parent_id,body,created_at FROM community_comments WHERE post_id=$1 AND deleted_at IS NULL AND moderation_state=\'active\' ORDER BY created_at DESC LIMIT 50',[postId]);return{data:rows.rows};}catch{return reply.code(401).send({error:{code:'COMMENTS_FAILED',message:'Yorumlar yüklenemedi.'}});}});
app.post('/v1/community/posts/:id/comments',async(request,reply)=>{try{const userId=await viewer(request.headers);const restricted=await activeRestriction(userId);if(restricted)return reply.code(403).send(restrictionError(restricted));const postId=z.string().uuid().parse((request.params as {id:string}).id);const input=commentBody.parse(request.body);const post=await db.query('SELECT 1 FROM community_posts WHERE id=$1 AND deleted_at IS NULL AND comments_enabled',[postId]);if(!post.rows[0])return reply.code(403).send({error:{code:'COMMENTS_DISABLED',message:'Yorumlar kapalı.'}});const result=await db.query('INSERT INTO community_comments(post_id,author_id,parent_id,body) VALUES($1,$2,$3,$4) RETURNING id,created_at',[postId,userId,input.parentId??null,input.body]);
    // Ses Ver: the first comment. Everything else about commenting is counted
    // elsewhere; this is the one badge the act itself earns.
    void grantInBackground('comment', async (journey) => { await touchStreak(journey, userId); await awardBadge(journey, userId, 'vocalist'); });
    return reply.code(201).send({data:result.rows[0]});}catch{return reply.code(400).send({error:{code:'COMMENT_CREATE_FAILED',message:'Yorum gönderilemedi.'}});}});
app.delete('/v1/community/comments/:id',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);await db.query('UPDATE community_comments SET deleted_at=now(),moderation_state=\'removed\' WHERE id=$1 AND author_id=$2 AND deleted_at IS NULL',[id,userId]);return reply.code(204).send();}catch{return reply.code(400).send();}});
app.get('/v1/marketplace/listings',async(request,reply)=>{try{const userId=await viewer(request.headers);const input=listingQuery.parse(request.query);const cursor=decodeCursor(input.cursor);const params:unknown[]=[userId];let where="l.status='active'";if(cursor){params.push(cursor.createdAt,cursor.id);where+=` AND (l.created_at,l.id) < ($${params.length-1}::timestamptz,$${params.length}::uuid)`;}params.push(input.limit+1);const rows=await db.query<{id:string;title:string;description:string;price:string;city:string|null;region_code:string|null;created_at:Date;seller_name:string}>(`SELECT l.id,l.title,l.description,l.price,l.city,l.region_code,l.created_at,COALESCE(cp.display_name,'TurkSquare üyesi') seller_name FROM marketplace_listings l LEFT JOIN community_profile_projection cp ON cp.user_id=l.owner_id LEFT JOIN community_profile_projection v ON v.user_id=$1 WHERE ${where} ORDER BY (l.region_code=v.region_code) DESC,l.created_at DESC,l.id DESC LIMIT $${params.length}`,params);const page=rows.rows.slice(0,input.limit);const next=rows.rows.length>input.limit?encodeCursor(page[page.length-1]!):null;return{data:page.map((l)=>({id:l.id,title:l.title,description:l.description,price:Number(l.price),category:'Diğer',condition:'',location:[l.city,l.region_code].filter(Boolean).join(', '),sellerName:l.seller_name,imageUrl:'',isSaved:false,createdAt:l.created_at.toISOString()})),meta:{nextCursor:next}};}catch(error){return reply.code((error as {statusCode?:number}).statusCode??401).send({error:{code:'LISTINGS_UNAVAILABLE'}});}});
app.post('/v1/marketplace/listings',async(request,reply)=>{try{const userId=await viewer(request.headers);const input=listingBody.parse(request.body);const row=await db.query<{id:string}>('INSERT INTO marketplace_listings(owner_id,title,description,price,city,region_code) VALUES($1,$2,$3,$4,$5,$6) RETURNING id',[userId,input.title,input.description,input.price,input.city??null,input.regionCode?.toUpperCase()??null]);return reply.code(201).send({data:row.rows[0]});}catch{return reply.code(400).send({error:{code:'LISTING_CREATE_FAILED'}});}});
app.post('/v1/marketplace/listings/:id/auction',async(request,reply)=>{try{const userId=await viewer(request.headers);const listingId=z.string().uuid().parse((request.params as {id:string}).id);const input=auctionBody.parse(request.body);const eligible=await db.query('SELECT 1 FROM member_capabilities WHERE user_id=$1 AND auction_seller_eligible',[userId]);if(!eligible.rows[0])return reply.code(403).send({error:{code:'VERIFICATION_REQUIRED',message:'İhale açmak için Onaylı Hesap rozeti gerekir.'}});const row=await db.query<{id:string}>('INSERT INTO marketplace_auctions(listing_id,seller_id,starting_price,minimum_increment,starts_at,ends_at) SELECT $1,$2,$3,$4,$5,$6 WHERE EXISTS(SELECT 1 FROM marketplace_listings WHERE id=$1 AND owner_id=$2 AND status=\'active\') RETURNING id',[listingId,userId,input.startingPrice,input.minimumIncrement,input.startsAt,input.endsAt]);if(!row.rows[0])return reply.code(404).send({error:{code:'LISTING_NOT_AVAILABLE'}});return reply.code(201).send({data:row.rows[0]});}catch{return reply.code(400).send({error:{code:'AUCTION_CREATE_FAILED'}});}});
app.post('/v1/marketplace/auctions/:id/bids',async(request,reply)=>{const client=await db.connect();try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);const input=bidBody.parse(request.body);await client.query('BEGIN');const auction=await client.query<{seller_id:string;starting_price:string;minimum_increment:string;starts_at:Date;ends_at:Date}>('SELECT seller_id,starting_price,minimum_increment,starts_at,ends_at FROM marketplace_auctions WHERE id=$1 FOR UPDATE',[id]);const a=auction.rows[0];if(!a||a.seller_id===userId||a.starts_at>new Date()||a.ends_at<=new Date())throw Error();const top=await client.query<{amount:string}>('SELECT amount FROM marketplace_auction_bids WHERE auction_id=$1 ORDER BY amount DESC,created_at ASC LIMIT 1',[id]);const minimum=Number(top.rows[0]?.amount??a.starting_price)+(top.rows[0]?Number(a.minimum_increment):0);if(input.amount<minimum)throw Error();const bid=await client.query<{id:string}>('INSERT INTO marketplace_auction_bids(auction_id,bidder_id,amount) VALUES($1,$2,$3) RETURNING id',[id,userId,input.amount]);await client.query('COMMIT');return reply.code(201).send({data:bid.rows[0]});}catch{await client.query('ROLLBACK');return reply.code(400).send({error:{code:'BID_REJECTED',message:'Teklif kabul edilemedi.'}});}finally{client.release();}});
// --- Blocking -----------------------------------------------------------
// Community owns the block edge because it owns the social graph. Messaging
// only ever sees a projection of it, published through the outbox below.
const blockBody = z.object({ userId: z.string().uuid() });
const blockQuery = z.object({ limit: z.coerce.number().int().min(1).max(200).default(100) });

async function queueBlockEvent(client: pg.PoolClient, eventType: 'messaging.user_blocked' | 'messaging.user_unblocked', blockerId: string, blockedId: string) {
  await client.query(
    `INSERT INTO community_outbox_events(aggregate_type,aggregate_id,event_type,payload)
     VALUES('user_block',$1,$2,$3::jsonb)`,
    [blockerId, eventType, JSON.stringify({ blockerId, blockedId })],
  );
}

app.post('/v1/community/blocks', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const blockerId = await viewer(request.headers);
    const { userId: blockedId } = blockBody.parse(request.body);
    if (blockerId === blockedId) return reply.code(400).send({ error: { code: 'BLOCK_SELF_NOT_ALLOWED', message: 'Kendinizi engelleyemezsiniz.' } });
    await client.query('BEGIN');
    await client.query('INSERT INTO user_blocks(blocker_id,blocked_id) VALUES($1,$2) ON CONFLICT DO NOTHING', [blockerId, blockedId]);
    // A block severs the relationship in both directions, otherwise the blocked
    // account keeps story and friends-only feed access it can no longer be
    // removed from.
    await client.query(
      'UPDATE relationship_projection SET active=false,updated_at=now() WHERE active AND ((viewer_id=$1 AND subject_id=$2) OR (viewer_id=$2 AND subject_id=$1))',
      [blockerId, blockedId],
    );
    // Emitted even when the row already existed: a re-block is the cheapest way
    // for a user to repair a projection whose earlier event was lost, and the
    // consumer is idempotent.
    await queueBlockEvent(client, 'messaging.user_blocked', blockerId, blockedId);
    await client.query('COMMIT');
    void publishCommunityOutbox();
    return reply.code(204).send();
  } catch (error) {
    await client.query('ROLLBACK');
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'BLOCK_FAILED', message: 'Kullanıcı engellenemedi.' } });
  } finally {
    client.release();
  }
});

app.delete('/v1/community/blocks/:userId', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const blockerId = await viewer(request.headers);
    const blockedId = z.string().uuid().parse((request.params as { userId: string }).userId);
    await client.query('BEGIN');
    await client.query('DELETE FROM user_blocks WHERE blocker_id=$1 AND blocked_id=$2', [blockerId, blockedId]);
    // The relationship is not restored: unblocking undoes the block, not the
    // follow that the block removed.
    await queueBlockEvent(client, 'messaging.user_unblocked', blockerId, blockedId);
    await client.query('COMMIT');
    void publishCommunityOutbox();
    return reply.code(204).send();
  } catch (error) {
    await client.query('ROLLBACK');
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'UNBLOCK_FAILED', message: 'Engel kaldırılamadı.' } });
  } finally {
    client.release();
  }
});

app.get('/v1/community/blocks', async (request, reply) => {
  try {
    const blockerId = await viewer(request.headers);
    const { limit } = blockQuery.parse(request.query);
    const rows = await db.query<{ blocked_id: string; display_name: string; created_at: Date }>(
      `SELECT b.blocked_id,COALESCE(p.display_name,'TurkSquare üyesi') display_name,b.created_at
       FROM user_blocks b
       LEFT JOIN community_profile_projection p ON p.user_id=b.blocked_id
       WHERE b.blocker_id=$1
       ORDER BY b.created_at DESC
       LIMIT $2`,
      [blockerId, limit],
    );
    return { data: rows.rows.map((row) => ({ userId: row.blocked_id, displayName: row.display_name, createdAt: row.created_at.toISOString() })) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'BLOCKS_UNAVAILABLE', message: 'Engellenen kullanıcılar yüklenemedi.' } });
  }
});

// --- Content moderation -------------------------------------------------
// Reporting for feed content. The app had a "Raporla" menu item that only
// showed a snackbar, so a report reached nobody. Categories, priorities and the
// SLA clock match messaging-gateway's exactly: the console shows both queues on
// one screen and a moderator should not have to hold two vocabularies.
const REPORT_CATEGORIES = ['child_safety', 'self_harm', 'violence_threat', 'hate_speech', 'harassment', 'sexual_content', 'scam_fraud', 'illegal_goods', 'spam', 'other'] as const;
const URGENT_CATEGORIES = new Set<string>(['child_safety', 'self_harm', 'violence_threat']);
const STANDARD_SLA_HOURS = 24;
const URGENT_SLA_HOURS = 2;
const CONTENT_REVIEW_ROLES: GateworkRole[] = ['owner', 'security_admin', 'moderator', 'auditor'];
const CONTENT_ACT_ROLES: GateworkRole[] = ['owner', 'security_admin', 'moderator'];

const contentReportBody = z.object({
  // Forum content is in this list rather than in a queue of its own: a reported
  // topic is the same job as a reported post, and splitting the queue would mean
  // a moderator has to remember to look in two places.
  targetType: z.enum(['post', 'comment', 'story', 'forum_topic', 'forum_reply']),
  targetId: z.string().uuid(),
  category: z.enum(REPORT_CATEGORIES),
  note: z.string().trim().max(500).optional(),
});
const contentReportQuery = z.object({
  status: z.enum(['unresolved', 'open', 'in_review', 'actioned', 'dismissed']).default('unresolved'),
  category: z.enum(REPORT_CATEGORIES).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});
const contentDecisionBody = z.object({
  action: z.enum(['dismiss', 'remove_content', 'restrict_author']),
  reason: z.string().trim().min(5).max(500),
  // Only read for restrict_author. A restriction that also leaves the reported
  // content up is a real decision - the account is the problem, the one post was
  // not - so removal stays a separate flag rather than being implied.
  removeContent: z.boolean().default(false),
  restriction: z.enum(['muted', 'suspended']).optional(),
  durationHours: z.coerce.number().int().min(1).max(8760).optional(),
  idempotencyKey: z.string().uuid(),
});
const contentReasonBody = z.object({ reason: z.string().trim().min(5).max(500), idempotencyKey: z.string().uuid() });

// The reported object, frozen. Selected inside the same transaction that writes
// the report so a delete racing the report cannot empty the case file.
type ContentTargetType = 'post' | 'comment' | 'story' | 'forum_topic' | 'forum_reply';

async function captureContentEvidence(client: pg.PoolClient, targetType: ContentTargetType, targetId: string) {
  if (targetType === 'post') {
    const row = await client.query<{ author_id: string; body: string; created_at: Date; media_ids: string[] | null }>(
      `SELECT p.author_id,p.body,p.created_at,
              (SELECT array_agg(m.media_id ORDER BY m.ordinal) FROM post_media_refs m WHERE m.post_id=p.id) media_ids
         FROM community_posts p WHERE p.id=$1 AND p.deleted_at IS NULL`,
      [targetId],
    );
    if (!row.rows[0]) return null;
    const post = row.rows[0];
    return { authorId: post.author_id, evidence: { targetType, body: post.body, createdAt: post.created_at.toISOString(), mediaIds: post.media_ids ?? [] } };
  }
  if (targetType === 'comment') {
    const row = await client.query<{ author_id: string; body: string; created_at: Date; post_id: string }>(
      "SELECT author_id,body,created_at,post_id FROM community_comments WHERE id=$1 AND deleted_at IS NULL",
      [targetId],
    );
    if (!row.rows[0]) return null;
    const comment = row.rows[0];
    return { authorId: comment.author_id, evidence: { targetType, body: comment.body, createdAt: comment.created_at.toISOString(), postId: comment.post_id } };
  }
  if (targetType === 'forum_topic') {
    // Title and body together: a topic can be reported for its title alone, and
    // a reviewer opening the case has to see what was actually written.
    const row = await client.query<{ author_id: string; title: string; body: string; created_at: Date; category_id: string }>(
      'SELECT author_id,title,body,created_at,category_id FROM forum_topics WHERE id=$1 AND deleted_at IS NULL',
      [targetId],
    );
    if (!row.rows[0]) return null;
    const topic = row.rows[0];
    return { authorId: topic.author_id, evidence: { targetType, title: topic.title, body: topic.body, createdAt: topic.created_at.toISOString(), categoryId: topic.category_id } };
  }
  if (targetType === 'forum_reply') {
    const row = await client.query<{ author_id: string; body: string; created_at: Date; topic_id: string }>(
      'SELECT author_id,body,created_at,topic_id FROM forum_replies WHERE id=$1 AND deleted_at IS NULL',
      [targetId],
    );
    if (!row.rows[0]) return null;
    const forumReply = row.rows[0];
    return { authorId: forumReply.author_id, evidence: { targetType, body: forumReply.body, createdAt: forumReply.created_at.toISOString(), topicId: forumReply.topic_id } };
  }
  const row = await client.query<{ author_id: string; created_at: Date; media_id: string; safe_url: string | null }>(
    'SELECT s.author_id,s.created_at,s.media_id,m.safe_url FROM stories s JOIN media_assets m ON m.id=s.media_id WHERE s.id=$1',
    [targetId],
  );
  if (!row.rows[0]) return null;
  const story = row.rows[0];
  // Stories expire in at most 24 hours, which is the whole SLA window - the
  // media key is kept so a reviewer still has something to look at after the
  // story itself is gone.
  return { authorId: story.author_id, evidence: { targetType, createdAt: story.created_at.toISOString(), mediaId: story.media_id, mediaKey: story.safe_url } };
}

app.post('/v1/community/reports', { config: { rateLimit: { max: 30, timeWindow: '1 hour' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const reporterId = await viewer(request.headers);
    const input = contentReportBody.parse(request.body);
    await client.query('BEGIN');

    const captured = await captureContentEvidence(client, input.targetType, input.targetId);
    if (!captured) { await client.query('ROLLBACK'); return reply.code(404).send({ error: { code: 'CONTENT_NOT_FOUND', message: 'Bu içerik artık mevcut değil.' } }); }
    if (captured.authorId === reporterId) { await client.query('ROLLBACK'); return reply.code(400).send({ error: { code: 'SELF_REPORT_NOT_ALLOWED', message: 'Kendi içeriğinizi şikâyet edemezsiniz.' } }); }

    // Returning the report already on file instead of erroring: tapping report
    // twice is not a failure a user should have to understand.
    const existing = await client.query<{ id: string; status: string; created_at: Date }>(
      "SELECT id,status,created_at FROM content_reports WHERE reporter_id=$1 AND target_type=$2 AND target_id=$3 AND status IN ('open','in_review')",
      [reporterId, input.targetType, input.targetId],
    );
    if (existing.rows[0]) {
      await client.query('COMMIT');
      const row = existing.rows[0];
      return reply.code(200).send({ data: { id: row.id, status: row.status, createdAt: row.created_at.toISOString(), duplicate: true } });
    }

    const priority = URGENT_CATEGORIES.has(input.category) ? 'urgent' : 'standard';
    const slaHours = priority === 'urgent' ? URGENT_SLA_HOURS : STANDARD_SLA_HOURS;
    // Frozen at report time, for the same reason due_at is: an auditor reading
    // this row a year later has to see the standing the reporter had when they
    // filed, not the standing they have now.
    const trust = await reporterTrust(client, reporterId);
    const inserted = await client.query<{ id: string; created_at: Date; due_at: Date }>(
      `INSERT INTO content_reports(reporter_id,reported_user_id,target_type,target_id,category,note,evidence,priority,due_at,reporter_trust)
       VALUES($1,$2,$3,$4,$5,$6,$7::jsonb,$8,now()+($9::text||' hours')::interval,$10)
       RETURNING id,created_at,due_at`,
      [reporterId, captured.authorId, input.targetType, input.targetId, input.category, input.note ?? null, JSON.stringify(captured.evidence), priority, String(slaHours), trust],
    );
    await client.query('COMMIT');
    const report = inserted.rows[0]!;
    return reply.code(201).send({ data: { id: report.id, status: 'open', createdAt: report.created_at.toISOString(), dueAt: report.due_at.toISOString(), duplicate: false } });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'REPORT_FAILED', message: 'Şikâyet gönderilemedi.' } });
  } finally {
    client.release();
  }
});

// What the app asks before letting someone post: a suspended account may not
// write at all, a muted one may not create new content. Exported as a route so
// the client can explain the state instead of failing a write with no reason.
// Named, not generic. "Paylaşım oluşturulamadı" would send a restricted user to
// support thinking the app is broken; the point of a restriction is that the
// person knows they are restricted.
const restrictionError = (restriction: { kind: string; expires_at: Date | null }) => ({
  error: {
    code: 'ACCOUNT_RESTRICTED',
    message: restriction.kind === 'suspended'
      ? 'Hesabınız askıya alındı. Yeni içerik paylaşamazsınız.'
      : restriction.expires_at
        ? `Hesabınız ${restriction.expires_at.toLocaleDateString('tr-TR')} tarihine kadar kısıtlı. Yeni içerik paylaşamazsınız.`
        : 'Hesabınız kısıtlı. Yeni içerik paylaşamazsınız.',
  },
});

async function activeRestriction(userId: string) {
  const row = await db.query<{ kind: string; reason: string; expires_at: Date | null }>(
    'SELECT kind,reason,expires_at FROM content_author_restrictions WHERE user_id=$1 AND (expires_at IS NULL OR expires_at>now())',
    [userId],
  );
  return row.rows[0] ?? null;
}

app.get('/v1/community/restrictions/me', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const restriction = await activeRestriction(userId);
    return { data: restriction ? { kind: restriction.kind, reason: restriction.reason, expiresAt: restriction.expires_at?.toISOString() ?? null } : null };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'RESTRICTION_UNAVAILABLE', message: 'Hesap durumu okunamadı.' } });
  }
});

const CONTENT_REPORT_SELECT = `
  SELECT r.*,
         COALESCE(rp.display_name,'TurkSquare üyesi') reporter_name,
         COALESCE(tp.display_name,'TurkSquare üyesi') reported_name,
         (SELECT kind FROM content_author_restrictions cr WHERE cr.user_id=r.reported_user_id AND (cr.expires_at IS NULL OR cr.expires_at>now())) active_restriction
    FROM content_reports r
    LEFT JOIN community_profile_projection rp ON rp.user_id=r.reporter_id
    LEFT JOIN community_profile_projection tp ON tp.user_id=r.reported_user_id`;

type ContentReportRow = {
  id: string; reporter_id: string; reporter_name: string; reported_user_id: string; reported_name: string;
  target_type: ContentTargetType; target_id: string; category: string; note: string | null;
  evidence: Record<string, unknown>; priority: 'urgent' | 'standard'; status: string; due_at: Date;
  assigned_to: string | null; resolution: string | null; resolved_by: string | null; resolved_at: Date | null;
  created_at: Date; active_restriction: string | null; reporter_trust: 'standard' | 'high' | null;
};

const toContentReportDto = (row: ContentReportRow) => ({
  id: row.id,
  source: 'content' as const,
  targetType: row.target_type,
  targetId: row.target_id,
  category: row.category,
  note: row.note,
  evidence: row.evidence,
  priority: row.priority,
  status: row.status,
  dueAt: row.due_at.toISOString(),
  overdue: row.due_at.getTime() < Date.now() && (row.status === 'open' || row.status === 'in_review'),
  createdAt: row.created_at.toISOString(),
  reporterId: row.reporter_id,
  reporterName: row.reporter_name,
  reportedUserId: row.reported_user_id,
  reportedUserName: row.reported_name,
  activeRestriction: row.active_restriction,
  // Drawn as a "Yüksek Güvenilirlik" chip in Gatework. It is a hint about who
  // filed the report, never a verdict about the content.
  reporterTrust: row.reporter_trust ?? 'standard',
  assignedTo: row.assigned_to,
  resolution: row.resolution,
  resolvedBy: row.resolved_by,
  resolvedAt: row.resolved_at?.toISOString() ?? null,
});

app.get('/v1/internal/gatework/community/reports', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, CONTENT_REVIEW_ROLES);
    const { status, category, limit, offset } = contentReportQuery.parse(request.query);
    const unresolved = status === 'unresolved';
    const rows = await db.query<ContentReportRow>(
      `${CONTENT_REPORT_SELECT}
        WHERE ($1::boolean OR r.status=$2)
          AND (NOT $1::boolean OR r.status IN ('open','in_review'))
          AND ($3::text IS NULL OR r.category=$3)
        ORDER BY (r.status IN ('open','in_review')) DESC,
                 -- Overdue outranks trust. A trusted reporter's report jumps the
                 -- queue among reports still inside their SLA; it must never
                 -- push a late one further back, or the SLA stops meaning
                 -- anything for everyone without badges.
                 (r.due_at<now()) DESC,
                 (r.reporter_trust='high') DESC,
                 r.due_at ASC, r.id ASC
        LIMIT $4 OFFSET $5`,
      [unresolved, unresolved ? 'open' : status, category ?? null, limit, offset],
    );
    return { data: rows.rows.map(toContentReportDto), nextOffset: rows.rows.length === limit ? offset + limit : null };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'CONTENT_REPORTS_UNAVAILABLE', message: 'Şikâyet kuyruğu okunamadı.' } });
  }
});

app.get('/v1/internal/gatework/community/reports/:id', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, CONTENT_REVIEW_ROLES);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const result = await db.query<ContentReportRow>(`${CONTENT_REPORT_SELECT} WHERE r.id=$1`, [id]);
    if (!result.rows[0]) return reply.code(404).send({ error: { code: 'REPORT_NOT_FOUND', message: 'Şikâyet bulunamadı.' } });
    const row = result.rows[0];
    // Whether the reported content is still standing decides which action makes
    // sense, and a reviewer should not have to guess it from the evidence date.
    const [history, actions, live] = await Promise.all([
      db.query<{ id: string; category: string; status: string; created_at: Date }>(
        'SELECT id,category,status,created_at FROM content_reports WHERE reported_user_id=$1 AND id<>$2 ORDER BY created_at DESC LIMIT 10',
        [row.reported_user_id, row.id],
      ),
      db.query<{ action: string; reason: string; actor_id: string; created_at: Date }>(
        'SELECT action,reason,actor_id,created_at FROM content_moderation_actions WHERE report_id=$1 ORDER BY created_at ASC',
        [row.id],
      ),
      row.target_type === 'post'
        ? db.query<{ state: string }>("SELECT CASE WHEN deleted_at IS NOT NULL THEN 'deleted' ELSE moderation_state END state FROM community_posts WHERE id=$1", [row.target_id])
        : row.target_type === 'comment'
          ? db.query<{ state: string }>("SELECT CASE WHEN deleted_at IS NOT NULL THEN 'deleted' ELSE moderation_state END state FROM community_comments WHERE id=$1", [row.target_id])
          : db.query<{ state: string }>("SELECT CASE WHEN expires_at<=now() THEN 'expired' ELSE 'active' END state FROM stories WHERE id=$1", [row.target_id]),
    ]);
    return {
      data: {
        ...toContentReportDto(row),
        targetState: live.rows[0]?.state ?? 'deleted',
        authorHistory: history.rows.map((h) => ({ id: h.id, category: h.category, status: h.status, createdAt: h.created_at.toISOString() })),
        actions: actions.rows.map((a) => ({ action: a.action, reason: a.reason, actorId: a.actor_id, createdAt: a.created_at.toISOString() })),
      },
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'REPORT_UNAVAILABLE', message: 'Şikâyet okunamadı.' } });
  }
});

app.post('/v1/internal/gatework/community/reports/:id/claim', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, CONTENT_ACT_ROLES);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    // Only an open report can be claimed, and only by one person: the WHERE is
    // the lock, so two moderators opening the queue together cannot both believe
    // the case is theirs.
    const claimed = await db.query<{ id: string }>(
      "UPDATE content_reports SET status='in_review',assigned_to=$2 WHERE id=$1 AND status='open' RETURNING id",
      [id, actor.actorId],
    );
    if (!claimed.rows[0]) return reply.code(409).send({ error: { code: 'REPORT_ALREADY_CLAIMED', message: 'Bu şikâyet başka bir moderatörde.' } });
    await db.query(
      "INSERT INTO content_moderation_actions(report_id,actor_id,actor_roles,action,target_type,target_id,reason) VALUES($1,$2,$3,'claim','report',$4,'Incelemeye alindi')",
      [id, actor.actorId, actor.roles, id],
    );
    return { data: { id, status: 'in_review', assignedTo: actor.actorId } };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'CLAIM_FAILED', message: 'Şikâyet üstlenilemedi.' } });
  }
});

app.post('/v1/internal/gatework/community/reports/:id/decision', async (request, reply) => {
  const client = await db.connect();
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, CONTENT_ACT_ROLES);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = contentDecisionBody.parse(request.body);
    await client.query('BEGIN');

    // Same dedup table the other Gatework commands use: a double-submitted form
    // resolves the report once.
    const prior = await client.query<{ result_id: string | null }>(
      "SELECT result_id FROM gatework_command_dedup WHERE actor_id=$1 AND idempotency_key=$2 AND command_type='content_report.decide' FOR UPDATE",
      [actor.actorId, input.idempotencyKey],
    );
    if (prior.rows[0]) { await client.query('COMMIT'); return { data: { id: prior.rows[0].result_id, duplicate: true } }; }

    const report = await client.query<{ id: string; status: string; target_type: ContentTargetType; target_id: string; reported_user_id: string; reporter_id: string }>(
      'SELECT id,status,target_type,target_id,reported_user_id,reporter_id FROM content_reports WHERE id=$1 FOR UPDATE',
      [id],
    );
    if (!report.rows[0]) { await client.query('ROLLBACK'); return reply.code(404).send({ error: { code: 'REPORT_NOT_FOUND', message: 'Şikâyet bulunamadı.' } }); }
    const row = report.rows[0];
    if (row.status === 'actioned' || row.status === 'dismissed') { await client.query('ROLLBACK'); return reply.code(409).send({ error: { code: 'REPORT_ALREADY_RESOLVED', message: 'Bu şikâyet zaten sonuçlandırılmış.' } }); }

    const removing = input.action === 'remove_content' || (input.action === 'restrict_author' && input.removeContent);
    if (removing) {
      // Soft removal, not a delete: the row has to survive for the audit, and a
      // wrongly removed post has to be restorable.
      if (row.target_type === 'post') await client.query("UPDATE community_posts SET moderation_state='removed' WHERE id=$1", [row.target_id]);
      else if (row.target_type === 'comment') await client.query("UPDATE community_comments SET moderation_state='removed' WHERE id=$1", [row.target_id]);
      else if (row.target_type === 'forum_topic') await client.query("UPDATE forum_topics SET moderation_state='removed' WHERE id=$1", [row.target_id]);
      else if (row.target_type === 'forum_reply') {
        // Removing a reply gives the topic its count back too, otherwise the
        // list keeps advertising an answer nobody can read.
        const removed = await client.query<{ topic_id: string }>("UPDATE forum_replies SET moderation_state='removed' WHERE id=$1 AND moderation_state='active' RETURNING topic_id", [row.target_id]);
        if (removed.rows[0]) await client.query('UPDATE forum_topics SET reply_count=greatest(reply_count-1,0) WHERE id=$1', [removed.rows[0].topic_id]);
      }
      else await client.query('UPDATE stories SET expires_at=now() WHERE id=$1 AND expires_at>now()', [row.target_id]);
      await client.query(
        'INSERT INTO content_moderation_actions(report_id,actor_id,actor_roles,action,target_type,target_id,reason) VALUES($1,$2,$3,$4,$5,$6,$7)',
        [id, actor.actorId, actor.roles, 'remove_content', row.target_type, row.target_id, input.reason],
      );
    }

    if (input.action === 'restrict_author') {
      const kind = input.restriction ?? 'muted';
      await client.query(
        `INSERT INTO content_author_restrictions(user_id,kind,reason,expires_at,created_by)
         VALUES($1,$2,$3,CASE WHEN $4::text IS NULL THEN NULL ELSE now()+($4::text||' hours')::interval END,$5)
         ON CONFLICT (user_id) DO UPDATE SET kind=EXCLUDED.kind,reason=EXCLUDED.reason,expires_at=EXCLUDED.expires_at,created_by=EXCLUDED.created_by,created_at=now()`,
        [row.reported_user_id, kind, input.reason, input.durationHours ? String(input.durationHours) : null, actor.actorId],
      );
      await client.query(
        'INSERT INTO content_moderation_actions(report_id,actor_id,actor_roles,action,target_type,target_id,reason) VALUES($1,$2,$3,$4,$5,$6,$7)',
        [id, actor.actorId, actor.roles, 'restrict_author', 'user', row.reported_user_id, input.reason],
      );
    }

    if (input.action === 'dismiss') {
      await client.query(
        'INSERT INTO content_moderation_actions(report_id,actor_id,actor_roles,action,target_type,target_id,reason) VALUES($1,$2,$3,$4,$5,$6,$7)',
        [id, actor.actorId, actor.roles, 'dismiss', 'report', id, input.reason],
      );
    }

    await client.query(
      'UPDATE content_reports SET status=$2,resolution=$3,resolved_by=$4,resolved_at=now() WHERE id=$1',
      [id, input.action === 'dismiss' ? 'dismissed' : 'actioned', input.reason, actor.actorId],
    );
    await client.query(
      "INSERT INTO gatework_command_dedup(actor_id,idempotency_key,command_type,result_id) VALUES($1,$2,'content_report.decide',$3)",
      [actor.actorId, input.idempotencyKey, id],
    );
    await auditGateworkOperation({
      actorId: actor.actorId, roles: actor.roles, action: `content_report.${input.action}`,
      targetType: row.target_type, targetId: row.target_id, reason: input.reason,
      requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded',
    });
    await client.query('COMMIT');
    // Mahalle Bekcisi is "reported ten things that turned out to be real", so it
    // is earned here - at the moment a moderator agrees - and not when the
    // report was filed. Counting actioned reports rather than adding one keeps a
    // reversed decision from leaving the member with credit for it.
    if (input.action !== 'dismiss') void grantInBackground('moderation', async (journey) => {
      const upheld = await journey.query<{ count: string }>("SELECT count(*) FROM content_reports WHERE reporter_id=$1 AND status='actioned'", [row.reporter_id]);
      await advanceProgress(journey, row.reporter_id, 'neighborhood_sentinel', Number(upheld.rows[0]!.count), { absolute: true });
    });
    return { data: { id, status: input.action === 'dismiss' ? 'dismissed' : 'actioned', duplicate: false } };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'DECISION_FAILED', message: 'Karar kaydedilemedi.' } });
  } finally {
    client.release();
  }
});

app.get('/v1/internal/gatework/community/overview', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, CONTENT_REVIEW_ROLES);
    const summary = await db.query<{ open_reports: string; urgent_reports: string; overdue_reports: string; filed_last_7_days: string; resolved_last_7_days: string; median_minutes: string | null; active_restrictions: string }>(
      `SELECT
         count(*) FILTER (WHERE status IN ('open','in_review')) open_reports,
         count(*) FILTER (WHERE status IN ('open','in_review') AND priority='urgent') urgent_reports,
         count(*) FILTER (WHERE status IN ('open','in_review') AND due_at<now()) overdue_reports,
         count(*) FILTER (WHERE created_at>now()-interval '7 days') filed_last_7_days,
         count(*) FILTER (WHERE resolved_at>now()-interval '7 days') resolved_last_7_days,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (resolved_at-created_at))/60)
           FILTER (WHERE resolved_at>now()-interval '30 days') median_minutes,
         (SELECT count(*) FROM content_author_restrictions WHERE expires_at IS NULL OR expires_at>now()) active_restrictions
       FROM content_reports`,
    );
    const row = summary.rows[0]!;
    return {
      data: {
        openReports: Number(row.open_reports),
        urgentReports: Number(row.urgent_reports),
        overdueReports: Number(row.overdue_reports),
        filedLast7Days: Number(row.filed_last_7_days),
        resolvedLast7Days: Number(row.resolved_last_7_days),
        medianResolutionMinutes: row.median_minutes === null ? null : Math.round(Number(row.median_minutes)),
        activeRestrictions: Number(row.active_restrictions),
        slaHours: { urgent: URGENT_SLA_HOURS, standard: STANDARD_SLA_HOURS },
      },
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'OVERVIEW_UNAVAILABLE', message: 'Özet okunamadı.' } });
  }
});

app.delete('/v1/internal/gatework/community/restrictions/:userId', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, CONTENT_ACT_ROLES);
    const userId = z.string().uuid().parse((request.params as { userId: string }).userId);
    const input = contentReasonBody.parse(request.body);
    const removed = await db.query('DELETE FROM content_author_restrictions WHERE user_id=$1', [userId]);
    if (!removed.rowCount) return reply.code(404).send({ error: { code: 'RESTRICTION_NOT_FOUND', message: 'Etkin kısıtlama yok.' } });
    await db.query(
      "INSERT INTO content_moderation_actions(actor_id,actor_roles,action,target_type,target_id,reason) VALUES($1,$2,'lift_restriction','user',$3,$4)",
      [actor.actorId, actor.roles, userId, input.reason],
    );
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'content_restriction.lift', targetType: 'user', targetId: userId, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    return reply.code(204).send();
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'LIFT_FAILED', message: 'Kısıtlama kaldırılamadı.' } });
  }
});

// --- Member profile -----------------------------------------------------
// The app's profile screen was fed entirely by MockProfileRepository: a
// hardcoded name, a hardcoded origin city, three invented badges and two
// invented restaurants. These endpoints are what replace it. Community owns the
// profile because Community owns the social graph the profile is read through;
// the onboarding answers arrive as a projection and are never edited here, so
// there is exactly one writer for each fact.

const profilePatchBody = z.object({
  bio: z.string().trim().max(280).nullable().optional(),
  avatarMediaId: z.string().uuid().nullable().optional(),
  visibility: z.enum(['public', 'friends_only']).optional(),
  showcasedBadges: z.array(z.string().regex(/^[a-z0-9_]{3,60}$/)).max(3).optional(),
});
const profilePostsQuery = z.object({
  state: z.enum(['active', 'archived']).default('active'),
  cursor: z.string().max(128).optional(),
  limit: z.coerce.number().int().min(1).max(60).default(24),
});
const leaderboardQuery = z.object({
  scope: z.enum(['city', 'region', 'global']).default('city'),
  window: z.enum(['week', 'all']).default('week'),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});

/// A badge is only ever granted as a side effect of something the member did,
/// so a failure to grant it must never fail that action. Wrapped in its own
/// transaction and swallowed on error: losing a badge to a deadlock is a bug
/// worth logging, not a reason a post fails to publish.
async function grantInBackground(label: string, work: (client: pg.PoolClient) => Promise<void>) {
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    await work(client);
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    app.log.warn({ err: error, label }, 'Journey award skipped');
  } finally {
    client.release();
  }
}

/// Whether [viewerId] may see the full profile of [ownerId].
///
/// Decided here, on the server. The client draws a lock; it does not get the
/// data and choose to hide it. A block in either direction closes the profile
/// regardless of visibility - the point of a block is not to be seen.
async function profileAccess(viewerId: string, ownerId: string) {
  if (viewerId === ownerId) return { self: true, blocked: false, full: true };
  const row = await db.query<{ blocked: boolean; friend: boolean; visibility: string }>(
    `SELECT
       EXISTS(SELECT 1 FROM user_blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=$2) OR (b.blocker_id=$2 AND b.blocked_id=$1)) blocked,
       EXISTS(SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=$2 AND r.relationship='friend' AND r.active) friend,
       COALESCE((SELECT visibility FROM member_profiles WHERE user_id=$2),'friends_only') visibility`,
    [viewerId, ownerId],
  );
  const access = row.rows[0]!;
  return { self: false, blocked: access.blocked, full: !access.blocked && (access.visibility === 'public' || access.friend) };
}

type ProfileRow = {
  user_id: string; display_name: string; city: string | null; region_code: string | null; interests: string[];
  born_in_us: boolean; arrived_month: number | null; arrived_year: number | null; origin_country: string | null;
  origin_city: string | null; primary_intent: string | null; bio: string | null; visibility: string | null;
  showcased_badges: string[] | null; avatar_url: string | null; identity_verified: boolean;
  post_count: string; friend_count: string; points: number | null; level: number | null; badge_count: number | null;
  streak_days: number | null; level_title: string | null; next_level_points: number | null;
};

const PROFILE_SELECT = `
  SELECT p.user_id,p.display_name,p.city,p.region_code,p.interests,
         p.born_in_us,p.arrived_month,p.arrived_year,p.origin_country,p.origin_city,p.primary_intent,
         mp.bio,mp.visibility,mp.showcased_badges,
         (SELECT m.safe_url FROM media_assets m WHERE m.id=mp.avatar_media_id AND m.status='ready') avatar_url,
         COALESCE(mc.identity_verified,false) identity_verified,
         (SELECT count(*) FROM community_posts cp WHERE cp.author_id=p.user_id AND cp.deleted_at IS NULL AND cp.archived_at IS NULL AND cp.moderation_state='active') post_count,
         (SELECT count(*) FROM relationship_projection r WHERE r.viewer_id=p.user_id AND r.relationship='friend' AND r.active) friend_count,
         ms.points,ms.level,ms.badge_count,ms.streak_days,
         (SELECT l.title FROM journey_levels l WHERE l.level=COALESCE(ms.level,1)) level_title,
         (SELECT min(l.min_points) FROM journey_levels l WHERE l.min_points>COALESCE(ms.points,0)) next_level_points
    FROM community_profile_projection p
    LEFT JOIN member_profiles mp ON mp.user_id=p.user_id
    LEFT JOIN member_capabilities mc ON mc.user_id=p.user_id
    LEFT JOIN member_scores ms ON ms.user_id=p.user_id`;

async function toProfileDto(row: ProfileRow, access: { self: boolean; full: boolean }) {
  const showcased = row.showcased_badges ?? [];
  const badges = showcased.length
    ? await db.query<{ code: string; title: string; icon: string; tier: string }>(
        'SELECT code,title,icon,tier FROM badge_definitions WHERE code=ANY($1::text[])',
        [showcased],
      )
    : { rows: [] as { code: string; title: string; icon: string; tier: string }[] };
  return {
    id: row.user_id,
    displayName: row.display_name,
    city: row.city,
    regionCode: row.region_code,
    // Everything below the fold is withheld from a viewer the member has not
    // let in. The name and city stay so a locked profile is still identifiable
    // enough to send a friend request to.
    interests: access.full ? row.interests : [],
    bornInUs: row.born_in_us,
    arrivedMonth: access.full ? row.arrived_month : null,
    arrivedYear: access.full ? row.arrived_year : null,
    originCountry: access.full ? row.origin_country : null,
    originCity: access.full ? row.origin_city : null,
    primaryIntent: access.full ? row.primary_intent : null,
    bio: access.full ? row.bio ?? '' : '',
    avatarUrl: row.avatar_url ? await mediaObjectUrl(row.avatar_url) : null,
    visibility: row.visibility ?? 'friends_only',
    identityVerified: row.identity_verified,
    showcasedBadges: badges.rows.map((badge) => ({ code: badge.code, title: badge.title, icon: badge.icon, tier: badge.tier })),
    counts: {
      posts: Number(row.post_count),
      friends: Number(row.friend_count),
      badges: row.badge_count ?? 0,
    },
    journey: {
      points: row.points ?? 0,
      level: row.level ?? 1,
      levelTitle: row.level_title ?? 'Fresh off the Boat',
      nextLevelPoints: row.next_level_points,
      streakDays: row.streak_days ?? 0,
    },
    isSelf: access.self,
    canViewFullProfile: access.full,
  };
}

app.get('/v1/community/profiles/me', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const row = await db.query<ProfileRow>(`${PROFILE_SELECT} WHERE p.user_id=$1`, [userId]);
    if (!row.rows[0]) return reply.code(404).send({ error: { code: 'PROFILE_NOT_FOUND', message: 'Profil bulunamadı. Önce kurulumu tamamlayın.' } });
    return { data: await toProfileDto(row.rows[0], { self: true, full: true }) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'PROFILE_UNAVAILABLE', message: 'Profil yüklenemedi.' } });
  }
});

app.get('/v1/community/profiles/:userId', async (request, reply) => {
  try {
    const viewerId = await viewer(request.headers);
    const ownerId = z.string().uuid().parse((request.params as { userId: string }).userId);
    const access = await profileAccess(viewerId, ownerId);
    // A blocked profile answers 404, not 403: confirming the account exists
    // would make the block a discovery tool.
    if (access.blocked) return reply.code(404).send({ error: { code: 'PROFILE_NOT_FOUND', message: 'Profil bulunamadı.' } });
    const row = await db.query<ProfileRow>(`${PROFILE_SELECT} WHERE p.user_id=$1`, [ownerId]);
    if (!row.rows[0]) return reply.code(404).send({ error: { code: 'PROFILE_NOT_FOUND', message: 'Profil bulunamadı.' } });
    return { data: await toProfileDto(row.rows[0], access) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'PROFILE_UNAVAILABLE', message: 'Profil yüklenemedi.' } });
  }
});

// Origin city and arrival date are deliberately not editable here. They are
// onboarding answers owned by identity, and the profile screen sends the member
// to PUT /v1/auth/onboarding to change them; accepting them in both places would
// give one fact two writers and let a replayed projection event silently undo
// what the member just typed.
app.patch('/v1/community/profiles/me', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const userId = await viewer(request.headers);
    const input = profilePatchBody.parse(request.body);
    await client.query('BEGIN');

    if (input.avatarMediaId) {
      // The avatar must be the member's own, fully scanned image. Anything else
      // would let a profile picture point at a blob that never passed the
      // quarantine the rest of the media pipeline enforces.
      const media = await client.query("SELECT 1 FROM media_assets WHERE id=$1 AND owner_id=$2 AND status='ready' AND kind='image'", [input.avatarMediaId, userId]);
      if (!media.rows[0]) { await client.query('ROLLBACK'); return reply.code(400).send({ error: { code: 'AVATAR_NOT_READY', message: 'Profil fotoğrafı henüz hazır değil.' } }); }
    }
    if (input.showcasedBadges?.length) {
      const owned = await client.query('SELECT badge_code FROM member_badges WHERE user_id=$1 AND badge_code=ANY($2::text[])', [userId, input.showcasedBadges]);
      if (owned.rows.length !== new Set(input.showcasedBadges).size) {
        await client.query('ROLLBACK');
        return reply.code(400).send({ error: { code: 'BADGE_NOT_EARNED', message: 'Vitrine yalnızca kazandığın rozetleri koyabilirsin.' } });
      }
    }

    await client.query(
      `INSERT INTO member_profiles(user_id,bio,avatar_media_id,visibility,showcased_badges)
       VALUES($1,$2,$3,COALESCE($4,'friends_only'),COALESCE($5::text[],'{}'))
       ON CONFLICT(user_id) DO UPDATE SET
         bio=CASE WHEN $6::boolean THEN $2 ELSE member_profiles.bio END,
         avatar_media_id=CASE WHEN $7::boolean THEN $3 ELSE member_profiles.avatar_media_id END,
         visibility=COALESCE($4,member_profiles.visibility),
         showcased_badges=COALESCE($5::text[],member_profiles.showcased_badges),
         updated_at=now()`,
      [
        userId,
        input.bio ?? null,
        input.avatarMediaId ?? null,
        input.visibility ?? null,
        input.showcasedBadges ?? null,
        // Distinguishes "clear it" from "leave it alone": an absent key keeps
        // the stored value, an explicit null wipes it.
        Object.prototype.hasOwnProperty.call(request.body ?? {}, 'bio'),
        Object.prototype.hasOwnProperty.call(request.body ?? {}, 'avatarMediaId'),
      ],
    );

    // Profil Sampiyonu: photo, bio and verification all present. Checked here
    // because this is the only place the first two can become true.
    const complete = await client.query<{ done: boolean }>(
      `SELECT (mp.bio IS NOT NULL AND char_length(trim(mp.bio))>0 AND mp.avatar_media_id IS NOT NULL AND COALESCE(mc.identity_verified,false)) done
         FROM member_profiles mp LEFT JOIN member_capabilities mc ON mc.user_id=mp.user_id WHERE mp.user_id=$1`,
      [userId],
    );
    if (complete.rows[0]?.done) await awardBadge(client, userId, 'profile_champion');
    await client.query('COMMIT');

    const row = await db.query<ProfileRow>(`${PROFILE_SELECT} WHERE p.user_id=$1`, [userId]);
    if (!row.rows[0]) return reply.code(404).send({ error: { code: 'PROFILE_NOT_FOUND', message: 'Profil bulunamadı.' } });
    return { data: await toProfileDto(row.rows[0], { self: true, full: true }) };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'PROFILE_UPDATE_FAILED', message: 'Profil güncellenemedi.' } });
  } finally {
    client.release();
  }
});

// The grid behind the "Paylasimlar" tab. Archived posts are visible to their
// author and to nobody else, which is the difference between archiving and
// deleting: the member keeps them, the app stops showing them.
app.get('/v1/community/profiles/:userId/posts', async (request, reply) => {
  try {
    const viewerId = await viewer(request.headers);
    const ownerId = z.string().uuid().parse((request.params as { userId: string }).userId);
    const input = profilePostsQuery.parse(request.query);
    const access = await profileAccess(viewerId, ownerId);
    if (access.blocked) return reply.code(404).send({ error: { code: 'PROFILE_NOT_FOUND', message: 'Profil bulunamadı.' } });
    if (input.state === 'archived' && !access.self) return reply.code(403).send({ error: { code: 'ARCHIVE_IS_PRIVATE', message: 'Arşiv yalnızca sahibine açıktır.' } });
    if (!access.full) return { data: [], meta: { nextCursor: null, locked: true } };

    const cursor = decodeCursor(input.cursor);
    const params: unknown[] = [ownerId, viewerId];
    let where = `p.author_id=$1 AND p.deleted_at IS NULL AND p.moderation_state='active' AND p.archived_at IS ${input.state === 'archived' ? 'NOT NULL' : 'NULL'}`;
    if (!access.self) where += " AND p.visibility='public'";
    if (cursor) { params.push(cursor.createdAt, cursor.id); where += ` AND (p.created_at,p.id) < ($${params.length - 1}::timestamptz,$${params.length}::uuid)`; }
    params.push(input.limit + 1);
    const rows = await db.query<{ id: string; created_at: Date; body: string; location_label: string | null; visibility: string; likes: string; comments: string; is_liked: boolean; thumbnail_url: string | null; safe_url: string | null }>(
      `SELECT p.id,p.created_at,p.body,p.location_label,p.visibility,
              (SELECT count(*) FROM post_reactions x WHERE x.post_id=p.id AND x.kind='like') likes,
              (SELECT count(*) FROM community_comments c WHERE c.post_id=p.id AND c.deleted_at IS NULL AND c.moderation_state='active') comments,
              EXISTS(SELECT 1 FROM post_reactions x WHERE x.post_id=p.id AND x.actor_id=$2 AND x.kind='like') is_liked,
              (SELECT m.thumbnail_url FROM post_media_refs r JOIN media_assets m ON m.id=r.media_id WHERE r.post_id=p.id AND m.status='ready' ORDER BY r.ordinal LIMIT 1) thumbnail_url,
              (SELECT m.safe_url FROM post_media_refs r JOIN media_assets m ON m.id=r.media_id WHERE r.post_id=p.id AND m.status='ready' ORDER BY r.ordinal LIMIT 1) safe_url
         FROM community_posts p
        WHERE ${where}
        ORDER BY p.created_at DESC,p.id DESC
        LIMIT $${params.length}`,
      params,
    );
    const page = rows.rows.slice(0, input.limit);
    const data = await Promise.all(page.map(async (post) => ({
      id: post.id,
      message: post.body,
      createdAt: post.created_at.toISOString(),
      location: post.location_label ?? '',
      visibility: post.visibility,
      likes: Number(post.likes),
      comments: Number(post.comments),
      isLiked: post.is_liked,
      archived: input.state === 'archived',
      thumbnailUrl: post.thumbnail_url ? await mediaObjectUrl(post.thumbnail_url) : post.safe_url ? await mediaObjectUrl(post.safe_url) : null,
    })));
    return { data, meta: { nextCursor: rows.rows.length > input.limit ? encodeCursor(page[page.length - 1]!) : null, locked: false } };
  } catch (error) {
    return reply.code((error as { statusCode?: number }).statusCode ?? ((error as Error).message === 'UNAUTHORIZED' ? 401 : 400)).send({ error: { code: 'PROFILE_POSTS_UNAVAILABLE', message: 'Paylaşımlar yüklenemedi.' } });
  }
});

app.post('/v1/community/posts/:id/archive', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const updated = await db.query('UPDATE community_posts SET archived_at=now() WHERE id=$1 AND author_id=$2 AND deleted_at IS NULL AND archived_at IS NULL', [id, userId]);
    if (!updated.rowCount) return reply.code(404).send({ error: { code: 'POST_NOT_FOUND', message: 'Paylaşım bulunamadı.' } });
    return reply.code(204).send();
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'ARCHIVE_FAILED', message: 'Paylaşım arşivlenemedi.' } });
  }
});

app.delete('/v1/community/posts/:id/archive', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const updated = await db.query('UPDATE community_posts SET archived_at=NULL WHERE id=$1 AND author_id=$2 AND deleted_at IS NULL AND archived_at IS NOT NULL', [id, userId]);
    if (!updated.rowCount) return reply.code(404).send({ error: { code: 'POST_NOT_FOUND', message: 'Paylaşım bulunamadı.' } });
    return reply.code(204).send();
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'UNARCHIVE_FAILED', message: 'Paylaşım geri alınamadı.' } });
  }
});

// --- Gurbet Yolculugu ---------------------------------------------------

/// The catalogue, annotated for one member: which badges they hold, how far
/// along they are on the ones they do not, and how rare each is.
///
/// A secret badge that has not been earned yet is returned without its title or
/// description. Sending them and asking the client to blur would put the answer
/// in the response body of a hidden achievement.
app.get('/v1/community/badges', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const rows = await db.query<{
      code: string; title: string; description: string; icon: string; category: string; tier: string;
      points: number; is_secret: boolean; earned_at: Date | null; current: number | null; target: number | null; holders: string; members: string;
    }>(
      `SELECT d.code,d.title,d.description,d.icon,d.category,d.tier,d.points,d.is_secret,
              b.earned_at,pr.current,pr.target,
              (SELECT count(*) FROM member_badges mb WHERE mb.badge_code=d.code) holders,
              (SELECT count(*) FROM community_profile_projection) members
         FROM badge_definitions d
         LEFT JOIN member_badges b ON b.badge_code=d.code AND b.user_id=$1
         LEFT JOIN member_badge_progress pr ON pr.badge_code=d.code AND pr.user_id=$1
        ORDER BY d.sort_order,d.code`,
      [userId],
    );
    return {
      data: rows.rows.map((badge) => {
        const earned = badge.earned_at !== null;
        const hidden = badge.is_secret && !earned;
        const members = Math.max(1, Number(badge.members));
        return {
          code: badge.code,
          title: hidden ? 'Gizli rozet' : badge.title,
          description: hidden ? 'Kriteri açıklanmıyor. Kazandığında burada belirecek.' : badge.description,
          icon: hidden ? 'lock' : badge.icon,
          category: badge.category,
          tier: badge.tier,
          points: badge.points,
          isSecret: badge.is_secret,
          earned,
          earnedAt: badge.earned_at?.toISOString() ?? null,
          current: hidden ? 0 : badge.current ?? 0,
          target: hidden ? null : badge.target,
          // "Uyelerin %3'u aldi" - the number that makes a badge worth chasing.
          rarityPercent: Math.round((Number(badge.holders) / members) * 1000) / 10,
        };
      }),
    };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'BADGES_UNAVAILABLE', message: 'Rozetler yüklenemedi.' } });
  }
});

app.get('/v1/community/users/:userId/badges', async (request, reply) => {
  try {
    const viewerId = await viewer(request.headers);
    const ownerId = z.string().uuid().parse((request.params as { userId: string }).userId);
    const access = await profileAccess(viewerId, ownerId);
    if (access.blocked) return reply.code(404).send({ error: { code: 'PROFILE_NOT_FOUND', message: 'Profil bulunamadı.' } });
    const rows = await db.query<{ code: string; title: string; description: string; icon: string; tier: string; points: number; earned_at: Date }>(
      `SELECT d.code,d.title,d.description,d.icon,d.tier,d.points,b.earned_at
         FROM member_badges b JOIN badge_definitions d ON d.code=b.badge_code
        WHERE b.user_id=$1 ORDER BY d.points DESC,b.earned_at DESC`,
      [ownerId],
    );
    return { data: rows.rows.map((badge) => ({ code: badge.code, title: badge.title, description: badge.description, icon: badge.icon, tier: badge.tier, points: badge.points, earnedAt: badge.earned_at.toISOString() })) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'BADGES_UNAVAILABLE', message: 'Rozetler yüklenemedi.' } });
  }
});

/// The journey screen: where the member stands, and what the next task is.
app.get('/v1/community/me/journey', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const [score, stages, tasks] = await Promise.all([
      db.query<{ points: number; level: number; badge_count: number; streak_days: number; streak_best: number; perks_frozen_until: Date | null; level_title: string; next_level: number | null; next_points: number | null; next_title: string | null }>(
        `SELECT COALESCE(s.points,0) points,COALESCE(s.level,1) level,COALESCE(s.badge_count,0) badge_count,
                COALESCE(s.streak_days,0) streak_days,COALESCE(s.streak_best,0) streak_best,s.perks_frozen_until,
                (SELECT l.title FROM journey_levels l WHERE l.level=COALESCE(s.level,1)) level_title,
                (SELECT l.level FROM journey_levels l WHERE l.min_points>COALESCE(s.points,0) ORDER BY l.min_points LIMIT 1) next_level,
                (SELECT l.min_points FROM journey_levels l WHERE l.min_points>COALESCE(s.points,0) ORDER BY l.min_points LIMIT 1) next_points,
                (SELECT l.title FROM journey_levels l WHERE l.min_points>COALESCE(s.points,0) ORDER BY l.min_points LIMIT 1) next_title
           FROM (SELECT 1) one LEFT JOIN member_scores s ON s.user_id=$1`,
        [userId],
      ),
      db.query<{ ordinal: number; title: string; level_title: string; reward: string }>('SELECT ordinal,title,level_title,reward FROM journey_stages ORDER BY ordinal'),
      db.query<{ code: string; stage_ordinal: number; ordinal: number; title: string; description: string; points: number; badge_code: string; earned_at: Date | null; current: number | null; target: number | null }>(
        `SELECT t.code,t.stage_ordinal,t.ordinal,t.title,t.description,t.points,t.badge_code,
                b.earned_at,pr.current,pr.target
           FROM journey_tasks t
           LEFT JOIN member_badges b ON b.badge_code=t.badge_code AND b.user_id=$1
           LEFT JOIN member_badge_progress pr ON pr.badge_code=t.badge_code AND pr.user_id=$1
          ORDER BY t.stage_ordinal,t.ordinal`,
        [userId],
      ),
    ]);
    const row = score.rows[0]!;
    const taskDto = tasks.rows.map((task) => ({
      code: task.code,
      stage: task.stage_ordinal,
      title: task.title,
      description: task.description,
      points: task.points,
      badgeCode: task.badge_code,
      completed: task.earned_at !== null,
      current: task.earned_at !== null ? task.target ?? 1 : task.current ?? 0,
      target: task.target ?? 1,
    }));
    return {
      data: {
        points: row.points,
        level: row.level,
        levelTitle: row.level_title,
        nextLevel: row.next_level,
        nextLevelTitle: row.next_title,
        nextLevelPoints: row.next_points,
        badgeCount: row.badge_count,
        streakDays: row.streak_days,
        streakBest: row.streak_best,
        perksFrozenUntil: row.perks_frozen_until?.toISOString() ?? null,
        stages: stages.rows.map((stage) => ({
          ordinal: stage.ordinal,
          title: stage.title,
          levelTitle: stage.level_title,
          reward: stage.reward,
          tasks: taskDto.filter((task) => task.stage === stage.ordinal),
        })),
        // The one thing the profile card shows. Null when everything on the map
        // is done, which the client renders as a finished journey rather than an
        // empty row.
        nextTask: taskDto.find((task) => !task.completed) ?? null,
      },
    };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'JOURNEY_UNAVAILABLE', message: 'Gurbet Yolculuğu yüklenemedi.' } });
  }
});

/// The weekly race. `week` sums the XP of badges earned in the last seven days
/// rather than reading total points, so a member who earned everything a year
/// ago does not sit at the top of a leaderboard called "this week".
app.get('/v1/community/leaderboard', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const input = leaderboardQuery.parse(request.query);
    const rows = await db.query<{ user_id: string; display_name: string; city: string | null; region_code: string | null; score: string; level: number; rank: string }>(
      `WITH me AS (SELECT city,region_code FROM member_scores WHERE user_id=$1),
       scoped AS (
         SELECT s.user_id,s.city,s.region_code,s.level,
                CASE WHEN $2='week'
                  THEN COALESCE((SELECT sum(d.points) FROM member_badges b JOIN badge_definitions d ON d.code=b.badge_code WHERE b.user_id=s.user_id AND b.earned_at>now()-interval '7 days'),0)
                  ELSE s.points END::int score
           FROM member_scores s
          WHERE ($3='global')
             OR ($3='region' AND s.region_code IS NOT NULL AND s.region_code=(SELECT region_code FROM me))
             OR ($3='city'   AND s.city IS NOT NULL AND s.city=(SELECT city FROM me) AND s.region_code IS NOT DISTINCT FROM (SELECT region_code FROM me))
       )
       SELECT scoped.user_id,COALESCE(p.display_name,'TurkSquare üyesi') display_name,scoped.city,scoped.region_code,scoped.score,scoped.level,
              rank() OVER (ORDER BY scoped.score DESC,scoped.user_id) rank
         FROM scoped LEFT JOIN community_profile_projection p ON p.user_id=scoped.user_id
        WHERE scoped.score>0
        ORDER BY scoped.score DESC,scoped.user_id
        LIMIT $4`,
      [userId, input.window, input.scope, input.limit],
    );
    return {
      data: rows.rows.map((entry) => ({
        userId: entry.user_id,
        displayName: entry.display_name,
        city: entry.city,
        regionCode: entry.region_code,
        score: Number(entry.score),
        level: entry.level,
        rank: Number(entry.rank),
        isSelf: entry.user_id === userId,
      })),
      meta: { scope: input.scope, window: input.window },
    };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'LEADERBOARD_UNAVAILABLE', message: 'Liderlik tablosu yüklenemedi.' } });
  }
});

// --- Haber Merkezi ------------------------------------------------------
// One table read from two places: the drawer's news centre and the home
// screen's "Amerika'dan Mansetler" strip. The strip is not a second feed, it is
// this list filtered by `headline_rank IS NOT NULL` - which is what makes the
// two stay in step without anyone syncing them.
//
// Articles are written from Gatework (see the internal endpoint below). What a
// member contributes is a reaction and a comment, and both reuse the shapes the
// feed already has so that the app can reuse the feed's comment editor and the
// moderation queue in 014 already knows what to do with a row.

const newsCategories = ['gundem', 'gocmenlik', 'ekonomi', 'yasam', 'spor', 'kultur', 'topluluk'] as const;
const newsQuery = z.object({ cursor: z.string().max(128).optional(), limit: z.coerce.number().int().min(1).max(50).default(20), category: z.enum(newsCategories).optional() });
const newsHeadlineQuery = z.object({ limit: z.coerce.number().int().min(1).max(10).default(5) });
// `null` is "take my reaction back". A tap on the icon that is already lit is a
// removal, not a second vote, and the table's primary key says the same thing.
const newsReactionBody = z.object({ value: z.enum(['like', 'dislike']).nullable() });
const gateworkNewsBody = z.object({
  title: z.string().trim().min(3).max(200),
  summary: z.string().trim().min(3).max(500),
  body: z.string().trim().min(1).max(20000),
  category: z.enum(newsCategories),
  authorId: z.string().uuid(),
  heroMediaId: z.string().uuid().optional(),
  regionCode: z.string().trim().regex(/^[A-Za-z]{2}$/).optional(),
  headlineRank: z.coerce.number().int().min(1).max(20).optional(),
  publishedAt: z.string().datetime().optional(),
  commentsEnabled: z.boolean().default(true),
  reason: z.string().trim().min(5).max(500),
  idempotencyKey: z.string().uuid(),
});

type NewsRow = {
  id: string; title: string; summary: string; body?: string; category: string; author_name: string;
  region_code: string | null; published_at: Date; headline_rank: number | null; hero_url: string | null;
  comments_enabled?: boolean; like_count: string; dislike_count: string; comment_count: string;
  viewer_reaction: 'like' | 'dislike' | null;
};

// $1 is always the viewer: their own reaction travels with the row so the app
// can draw the icons in the right state without a second round trip. [extra] is
// what only the detail screen needs - the list must not carry 20kB of body text
// per row.
const newsSelect = (extra = '') => `
  SELECT a.id,a.title,a.summary,${extra}a.category,a.author_name,a.region_code,a.published_at,a.headline_rank,
         m.safe_url hero_url,
         (SELECT count(*) FROM news_reactions r WHERE r.article_id=a.id AND r.value='like') like_count,
         (SELECT count(*) FROM news_reactions r WHERE r.article_id=a.id AND r.value='dislike') dislike_count,
         (SELECT count(*) FROM news_comments c WHERE c.article_id=a.id AND c.deleted_at IS NULL AND c.moderation_state='active') comment_count,
         (SELECT r.value FROM news_reactions r WHERE r.article_id=a.id AND r.user_id=$1) viewer_reaction
    FROM news_articles a
    LEFT JOIN media_assets m ON m.id=a.hero_media_id AND m.status='ready'`;

// Published, not deleted, not scheduled for later. Every read path shares it;
// a listing that forgets one of the three is how a draft reaches a reader.
const NEWS_VISIBLE = "a.deleted_at IS NULL AND a.published_at IS NOT NULL AND a.published_at<=now()";

const newsArticleJson = async (row: NewsRow) => ({
  id: row.id,
  title: row.title,
  summary: row.summary,
  ...(row.body === undefined ? {} : { body: row.body }),
  category: row.category,
  authorName: row.author_name,
  regionCode: row.region_code,
  publishedAt: row.published_at.toISOString(),
  headlineRank: row.headline_rank,
  // Signed on the way out, never stored: the same rule posts and stories follow.
  imageUrl: row.hero_url ? await mediaObjectUrl(row.hero_url) : null,
  ...(row.comments_enabled === undefined ? {} : { commentsEnabled: row.comments_enabled }),
  likeCount: Number(row.like_count),
  dislikeCount: Number(row.dislike_count),
  commentCount: Number(row.comment_count),
  viewerReaction: row.viewer_reaction,
});

app.get('/v1/community/news', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const input = newsQuery.parse(request.query);
    const cursor = decodeCursor(input.cursor);
    const params: unknown[] = [userId];
    let where = NEWS_VISIBLE;
    if (input.category) { params.push(input.category); where += ` AND a.category=$${params.length}`; }
    if (cursor) { params.push(cursor.createdAt, cursor.id); where += ` AND (a.published_at,a.id) < ($${params.length - 1}::timestamptz,$${params.length}::uuid)`; }
    params.push(input.limit + 1);
    const rows = await db.query<NewsRow>(`${newsSelect()} WHERE ${where} ORDER BY a.published_at DESC,a.id DESC LIMIT $${params.length}`, params);
    const page = rows.rows.slice(0, input.limit);
    const last = page[page.length - 1];
    return {
      data: await Promise.all(page.map(newsArticleJson)),
      meta: { nextCursor: rows.rows.length > input.limit && last ? encodeCursor({ created_at: last.published_at, id: last.id }) : null },
    };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : (error as { statusCode?: number }).statusCode ?? 400)
      .send({ error: { code: 'NEWS_UNAVAILABLE', message: 'Haberler yüklenemedi.' } });
  }
});

/// What the home screen's headline strip is: the same articles, ordered by the
/// rank an editor gave them rather than by when they went out.
app.get('/v1/community/news/headlines', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const input = newsHeadlineQuery.parse(request.query);
    const rows = await db.query<NewsRow>(
      `${newsSelect()} WHERE ${NEWS_VISIBLE} AND a.headline_rank IS NOT NULL ORDER BY a.headline_rank ASC,a.published_at DESC LIMIT $2`,
      [userId, input.limit],
    );
    return { data: await Promise.all(rows.rows.map(newsArticleJson)) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'NEWS_UNAVAILABLE', message: 'Manşetler yüklenemedi.' } });
  }
});

app.get('/v1/community/news/:id', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const rows = await db.query<NewsRow>(
      `${newsSelect('a.body,a.comments_enabled,')} WHERE ${NEWS_VISIBLE} AND a.id=$2`,
      [userId, id],
    );
    const article = rows.rows[0];
    if (!article) return reply.code(404).send({ error: { code: 'NEWS_NOT_FOUND', message: 'Haber bulunamadı.' } });
    return { data: await newsArticleJson(article) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'NEWS_UNAVAILABLE', message: 'Haber yüklenemedi.' } });
  }
});

app.put('/v1/community/news/:id/reactions', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = newsReactionBody.parse(request.body);
    if (input.value === null) {
      await db.query('DELETE FROM news_reactions WHERE article_id=$1 AND user_id=$2', [id, userId]);
    } else {
      // Guarded by the same visibility rule as the read: an unpublished article
      // is not something anyone can be voting on.
      const written = await db.query(
        `INSERT INTO news_reactions(article_id,user_id,value)
         SELECT a.id,$2,$3 FROM news_articles a WHERE a.id=$1 AND ${NEWS_VISIBLE}
         ON CONFLICT(article_id,user_id) DO UPDATE SET value=EXCLUDED.value,created_at=now()`,
        [id, userId, input.value],
      );
      if (!written.rowCount) return reply.code(404).send({ error: { code: 'NEWS_NOT_FOUND', message: 'Haber bulunamadı.' } });
    }
    const tally = await db.query<{ like_count: string; dislike_count: string }>(
      `SELECT count(*) FILTER (WHERE value='like') like_count,count(*) FILTER (WHERE value='dislike') dislike_count FROM news_reactions WHERE article_id=$1`,
      [id],
    );
    return { data: { likeCount: Number(tally.rows[0]!.like_count), dislikeCount: Number(tally.rows[0]!.dislike_count), viewerReaction: input.value } };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'NEWS_REACTION_FAILED', message: 'Tepkin kaydedilemedi.' } });
  }
});

// The display name is joined here and not left to the client. The feed's own
// comment list still omits it, which is why comments there render under whatever
// the caller happens to know; a news article has no such context to fall back on.
const NEWS_COMMENT_SELECT = `
  SELECT c.id,c.author_id,c.parent_id,c.body,c.created_at,
         COALESCE(p.display_name,'TurkSquare üyesi') author_name
    FROM news_comments c
    LEFT JOIN community_profile_projection p ON p.user_id=c.author_id`;

type NewsCommentRow = { id: string; author_id: string; parent_id: string | null; body: string; created_at: Date; author_name: string };
const newsCommentJson = (row: NewsCommentRow) => ({
  id: row.id,
  authorId: row.author_id,
  authorName: row.author_name,
  parentId: row.parent_id,
  body: row.body,
  createdAt: row.created_at.toISOString(),
});

app.get('/v1/community/news/:id/comments', async (request, reply) => {
  try {
    await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const rows = await db.query<NewsCommentRow>(
      `${NEWS_COMMENT_SELECT} WHERE c.article_id=$1 AND c.deleted_at IS NULL AND c.moderation_state='active' ORDER BY c.created_at ASC LIMIT 100`,
      [id],
    );
    return { data: rows.rows.map(newsCommentJson) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'NEWS_COMMENTS_FAILED', message: 'Yorumlar yüklenemedi.' } });
  }
});

app.post('/v1/community/news/:id/comments', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const restricted = await activeRestriction(userId);
    if (restricted) return reply.code(403).send(restrictionError(restricted));
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = commentBody.parse(request.body);
    const article = await db.query(`SELECT 1 FROM news_articles a WHERE a.id=$1 AND ${NEWS_VISIBLE} AND a.comments_enabled`, [id]);
    if (!article.rows[0]) return reply.code(403).send({ error: { code: 'COMMENTS_DISABLED', message: 'Bu haber yorumlara kapalı.' } });
    const inserted = await db.query<{ id: string }>(
      'INSERT INTO news_comments(article_id,author_id,parent_id,body) VALUES($1,$2,$3,$4) RETURNING id',
      [id, userId, input.parentId ?? null, input.body],
    );
    const row = await db.query<NewsCommentRow>(`${NEWS_COMMENT_SELECT} WHERE c.id=$1`, [inserted.rows[0]!.id]);
    // Streak only. `vocalist` counts comments on the feed, and quietly earning a
    // feed badge somewhere else would make its own description untrue.
    void grantInBackground('news_comment', async (journey) => { await touchStreak(journey, userId); });
    return reply.code(201).send({ data: newsCommentJson(row.rows[0]!) });
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'NEWS_COMMENT_CREATE_FAILED', message: 'Yorum gönderilemedi.' } });
  }
});

app.delete('/v1/community/news/comments/:id', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    await db.query("UPDATE news_comments SET deleted_at=now(),moderation_state='removed' WHERE id=$1 AND author_id=$2 AND deleted_at IS NULL", [id, userId]);
    return reply.code(204).send();
  } catch {
    return reply.code(400).send({ error: { code: 'NEWS_COMMENT_DELETE_FAILED', message: 'Yorum silinemedi.' } });
  }
});

/// Publishing from Gatework, with the same guarantees as an official post: the
/// author has to be an active system account, the command is idempotent, and the
/// operation is audited whether it succeeds or not.
app.post('/v1/internal/gatework/news', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const input = gateworkNewsBody.parse(request.body);
    const client = await db.connect();
    try {
      await client.query('BEGIN');
      const prior = await client.query<{ result_id: string | null }>(
        "SELECT result_id FROM gatework_command_dedup WHERE actor_id=$1 AND idempotency_key=$2 AND command_type='news_article.create' FOR UPDATE",
        [actor.actorId, input.idempotencyKey],
      );
      if (prior.rows[0]?.result_id) {
        await client.query('COMMIT');
        return reply.code(200).send({ data: { id: prior.rows[0].result_id } });
      }
      const author = await client.query<{ display_name: string }>(
        `SELECT COALESCE(p.display_name,'TurkSquare') display_name
           FROM community_system_accounts s LEFT JOIN community_profile_projection p ON p.user_id=s.user_id
          WHERE s.user_id=$1 AND s.role='official' AND s.active`,
        [input.authorId],
      );
      if (!author.rows[0]) throw Error('OFFICIAL_NOT_ACTIVE');
      // Media is verified before it is stored, not when it is served: an article
      // pointing at a rejected upload would fail silently at read time and leave
      // an editor wondering where the picture went.
      if (input.heroMediaId) {
        const media = await client.query("SELECT 1 FROM media_assets WHERE id=$1 AND status='ready'", [input.heroMediaId]);
        if (!media.rows[0]) throw Error('MEDIA_NOT_READY');
      }
      const article = await client.query<{ id: string }>(
        `INSERT INTO news_articles(title,summary,body,hero_media_id,category,author_id,author_name,region_code,published_at,headline_rank,comments_enabled,created_by)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,COALESCE($9::timestamptz,now()),$10,$11,$12) RETURNING id`,
        [input.title, input.summary, input.body, input.heroMediaId ?? null, input.category, input.authorId, author.rows[0].display_name,
          input.regionCode?.toUpperCase() ?? null, input.publishedAt ?? null, input.headlineRank ?? null, input.commentsEnabled, actor.actorId],
      );
      await client.query("INSERT INTO gatework_command_dedup(actor_id,idempotency_key,command_type,result_id) VALUES($1,$2,'news_article.create',$3)", [actor.actorId, input.idempotencyKey, article.rows[0]!.id]);
      await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'news_article.publish', targetType: 'news_article', targetId: article.rows[0]!.id, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
      await client.query('COMMIT');
      return reply.code(201).send({ data: article.rows[0] });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'GATEWORK_NEWS_REJECTED' } });
  }
});

/// Retracting a published article. A soft delete, so the comments and any report
/// filed against it still resolve to something after it comes down.
app.delete('/v1/internal/gatework/news/:id', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const reason = z.string().trim().min(5).max(500).parse((request.body as { reason?: string } | undefined)?.reason);
    const removed = await db.query('UPDATE news_articles SET deleted_at=now(),updated_at=now() WHERE id=$1 AND deleted_at IS NULL', [id]);
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'news_article.retract', targetType: 'news_article', targetId: id, reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: removed.rowCount ? 'succeeded' : 'failed' });
    return reply.code(204).send();
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'GATEWORK_NEWS_RETRACT_REJECTED' } });
  }
});

// --- Tanitim Yap ---------------------------------------------------------
// Sponsored placements: the featured story slot, the in-app banner and the
// "Sana Ozel One Cikanlar" cards. Members ask for the first two and an operator
// decides; the third is placed from the console only, because it is editorial
// space rather than something anyone can buy into.
//
// Nothing here charges anybody. A request is approved on its merits, and the
// pricing question is left to a later phase on purpose - see 018_promotions.sql.

const memberPlacements = ['story_slot', 'app_banner'] as const;
const promotionPlacements = [...memberPlacements, 'featured_card'] as const;
const promotionTargetKinds = ['post', 'listing', 'news', 'event', 'external'] as const;

// A window has to be finite and a promotion cannot start in the past: both are
// there so an approval today cannot silently turn into a placement that ran
// last week or one that never ends.
const MAX_PROMOTION_DAYS = 30;
const promotionWindow = {
  startsAt: z.string().datetime(),
  endsAt: z.string().datetime(),
};
const withCheckedWindow = <T extends { startsAt: string; endsAt: string }>(schema: z.ZodType<T>) =>
  schema.refine((value) => {
    const start = new Date(value.startsAt).getTime();
    const end = new Date(value.endsAt).getTime();
    return end > start && end - start <= MAX_PROMOTION_DAYS * 86_400_000 && end > Date.now();
  }, { message: 'INVALID_WINDOW' });

const promotionTarget = {
  targetKind: z.enum(promotionTargetKinds).optional(),
  targetValue: z.string().trim().min(1).max(500).optional(),
};
const promotionAudience = {
  regionCode: z.string().trim().regex(/^[A-Za-z]{2}$/).optional(),
  city: z.string().trim().min(2).max(80).optional(),
};

const promotionRequestBody = withCheckedWindow(z.object({
  placement: z.enum(memberPlacements),
  title: z.string().trim().min(3).max(120),
  subtitle: z.string().trim().min(1).max(200).optional(),
  mediaId: z.string().uuid(),
  ...promotionTarget,
  ...promotionAudience,
  ...promotionWindow,
  note: z.string().trim().min(3).max(500),
}));

const gateworkPromotionBody = withCheckedWindow(z.object({
  placement: z.enum(promotionPlacements),
  ownerId: z.string().uuid(),
  title: z.string().trim().min(3).max(120),
  subtitle: z.string().trim().min(1).max(200).optional(),
  mediaId: z.string().uuid().optional(),
  ...promotionTarget,
  ...promotionAudience,
  ...promotionWindow,
  reason: z.string().trim().min(5).max(500),
  idempotencyKey: z.string().uuid(),
}));

const promotionDecisionBody = z.object({
  action: z.enum(['approve', 'reject', 'end']),
  reason: z.string().trim().min(3).max(500),
  idempotencyKey: z.string().uuid(),
});
const promotionQueueQuery = z.object({
  status: z.enum(['pending', 'approved', 'rejected', 'ended']).default('pending'),
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});
const promotionEventBody = z.object({ kind: z.enum(['impression', 'click']) });

type PromotionRow = {
  id: string; owner_id: string; placement: string; title: string; subtitle: string | null;
  media_url: string | null; target_kind: string | null; target_value: string | null;
  region_code: string | null; city: string | null; starts_at: Date; ends_at: Date;
  status: string; decision_reason: string | null; request_note?: string | null;
  created_at: Date; owner_name?: string; impressions?: string; clicks?: string;
};

const PROMOTION_SELECT = `
  SELECT p.id,p.owner_id,p.placement,p.title,p.subtitle,m.safe_url media_url,p.target_kind,p.target_value,
         p.region_code,p.city,p.starts_at,p.ends_at,p.status,p.decision_reason,p.request_note,p.created_at
    FROM promotions p
    LEFT JOIN media_assets m ON m.id=p.media_id AND m.status='ready'`;

const promotionJson = async (row: PromotionRow) => ({
  id: row.id,
  placement: row.placement,
  title: row.title,
  subtitle: row.subtitle,
  // Signed on the way out, never stored - the same rule posts, stories and news
  // articles follow.
  imageUrl: row.media_url ? await mediaObjectUrl(row.media_url) : null,
  targetKind: row.target_kind,
  targetValue: row.target_value,
  regionCode: row.region_code,
  city: row.city,
  startsAt: row.starts_at.toISOString(),
  endsAt: row.ends_at.toISOString(),
  status: row.status,
  decisionReason: row.decision_reason,
  createdAt: row.created_at.toISOString(),
});

/// What the home screen reads. "Live" is computed here rather than stored: an
/// approved promotion is showing exactly when the clock is inside its window,
/// and nothing has to run on a schedule for that to be true.
app.get('/v1/community/promotions/active', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const rows = await db.query<PromotionRow>(
      `${PROMOTION_SELECT}
        LEFT JOIN community_profile_projection v ON v.user_id=$1
        WHERE p.status='approved' AND p.starts_at<=now() AND p.ends_at>now()
          -- Nationwide placements reach everyone; a targeted one only reaches
          -- the place it was bought for. An unknown viewer location sees the
          -- nationwide ones, never somebody else's city.
          AND (p.region_code IS NULL OR p.region_code=v.region_code)
          AND (p.city IS NULL OR p.city=v.city)
        ORDER BY p.starts_at DESC,p.id DESC LIMIT 20`,
      [userId],
    );
    return { data: await Promise.all(rows.rows.map(promotionJson)) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'PROMOTIONS_UNAVAILABLE', message: 'Tanıtımlar yüklenemedi.' } });
  }
});

/// The member's own requests, decisions included. A rejection is only useful if
/// the person who asked can read why.
app.get('/v1/community/promotions/me', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const rows = await db.query<PromotionRow>(
      `${PROMOTION_SELECT} WHERE p.owner_id=$1 ORDER BY p.created_at DESC LIMIT 50`,
      [userId],
    );
    const totals = await db.query<{ promotion_id: string; impressions: string; clicks: string }>(
      `SELECT i.promotion_id,sum(i.impressions) impressions,sum(i.clicks) clicks
         FROM promotion_impressions i JOIN promotions p ON p.id=i.promotion_id
        WHERE p.owner_id=$1 GROUP BY i.promotion_id`,
      [userId],
    );
    const byId = new Map(totals.rows.map((row) => [row.promotion_id, row]));
    return {
      data: await Promise.all(rows.rows.map(async (row) => ({
        ...await promotionJson(row),
        requestNote: row.request_note ?? null,
        impressions: Number(byId.get(row.id)?.impressions ?? 0),
        clicks: Number(byId.get(row.id)?.clicks ?? 0),
      }))),
    };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'PROMOTIONS_UNAVAILABLE', message: 'Tanıtım taleplerin yüklenemedi.' } });
  }
});

app.post('/v1/community/promotions', { config: { rateLimit: { max: 10, timeWindow: '1 hour' } } }, async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    // A muted member cannot buy their way back onto the home screen.
    const restricted = await activeRestriction(userId);
    if (restricted) return reply.code(403).send(restrictionError(restricted));
    const input = promotionRequestBody.parse(request.body);
    // The media has to be theirs and scanned, checked at write time: a request
    // pointing at a rejected upload would only fail once a reviewer opened it.
    const media = await db.query("SELECT 1 FROM media_assets WHERE id=$1 AND owner_id=$2 AND status='ready'", [input.mediaId, userId]);
    if (!media.rows[0]) return reply.code(400).send({ error: { code: 'MEDIA_NOT_READY', message: 'Görsel hazır değil.' } });
    const row = await db.query<{ id: string }>(
      `INSERT INTO promotions(owner_id,placement,title,subtitle,media_id,target_kind,target_value,region_code,city,starts_at,ends_at,request_note)
       VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING id`,
      [userId, input.placement, input.title, input.subtitle ?? null, input.mediaId, input.targetKind ?? null, input.targetValue ?? null,
        input.regionCode?.toUpperCase() ?? null, input.city ?? null, input.startsAt, input.endsAt, input.note],
    );
    return reply.code(201).send({ data: { id: row.rows[0]!.id, status: 'pending' } });
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'PROMOTION_REQUEST_FAILED', message: 'Tanıtım talebin gönderilemedi.' } });
  }
});

/// Counted per day and upserted, so the write is one row per placement per day
/// no matter how busy the home screen is. Only a promotion that is actually
/// showing can be counted; otherwise the numbers stop meaning "was seen".
app.post('/v1/community/promotions/:id/events', { config: { rateLimit: { max: 240, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = promotionEventBody.parse(request.body);
    const counted = await db.query(
      `INSERT INTO promotion_impressions(promotion_id,day,impressions,clicks)
       SELECT p.id,current_date,$2::int,$3::int FROM promotions p
        WHERE p.id=$1 AND p.status='approved' AND p.starts_at<=now() AND p.ends_at>now()
       ON CONFLICT (promotion_id,day) DO UPDATE
         SET impressions=promotion_impressions.impressions+EXCLUDED.impressions,
             clicks=promotion_impressions.clicks+EXCLUDED.clicks`,
      [id, input.kind === 'impression' ? 1 : 0, input.kind === 'click' ? 1 : 0],
    );
    return reply.code(counted.rowCount ? 204 : 404).send();
  } catch {
    return reply.code(400).send({ error: { code: 'PROMOTION_EVENT_FAILED' } });
  }
});

app.get('/v1/internal/gatework/promotions', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor', 'moderator']);
    const input = promotionQueueQuery.parse(request.query);
    const rows = await db.query<PromotionRow>(
      `${PROMOTION_SELECT} WHERE p.status=$1 ORDER BY p.created_at ASC LIMIT $2 OFFSET $3`,
      [input.status, input.limit, input.offset],
    );
    const owners = await db.query<{ user_id: string; display_name: string }>(
      'SELECT user_id,display_name FROM community_profile_projection WHERE user_id=ANY($1::uuid[])',
      [rows.rows.map((row) => row.owner_id)],
    );
    const names = new Map(owners.rows.map((row) => [row.user_id, row.display_name]));
    return {
      data: await Promise.all(rows.rows.map(async (row) => ({
        ...await promotionJson(row),
        ownerId: row.owner_id,
        ownerName: names.get(row.owner_id) ?? 'TurkSquare üyesi',
        requestNote: row.request_note ?? null,
      }))),
      nextOffset: rows.rows.length === input.limit ? input.offset + input.limit : null,
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'PROMOTION_QUEUE_UNAVAILABLE', message: 'Tanıtım kuyruğu okunamadı.' } });
  }
});

app.post('/v1/internal/gatework/promotions/:id/decision', async (request, reply) => {
  const client = await db.connect();
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = promotionDecisionBody.parse(request.body);
    await client.query('BEGIN');
    const prior = await client.query<{ result_id: string | null }>(
      "SELECT result_id FROM gatework_command_dedup WHERE actor_id=$1 AND idempotency_key=$2 AND command_type='promotion.decide' FOR UPDATE",
      [actor.actorId, input.idempotencyKey],
    );
    if (prior.rows[0]) { await client.query('COMMIT'); return { data: { id: prior.rows[0].result_id, duplicate: true } }; }

    const promotion = await client.query<{ id: string; status: string }>('SELECT id,status FROM promotions WHERE id=$1 FOR UPDATE', [id]);
    if (!promotion.rows[0]) { await client.query('ROLLBACK'); return reply.code(404).send({ error: { code: 'PROMOTION_NOT_FOUND', message: 'Tanıtım bulunamadı.' } }); }
    // 'end' pulls a running placement; the other two are first decisions. A
    // rejected request is not re-openable here - the member submits a new one,
    // so the trail keeps both the refusal and what changed.
    const current = promotion.rows[0].status;
    const allowed = input.action === 'end' ? current === 'approved' : current === 'pending';
    if (!allowed) { await client.query('ROLLBACK'); return reply.code(409).send({ error: { code: 'PROMOTION_ALREADY_DECIDED', message: 'Bu tanıtım zaten sonuçlandırılmış.' } }); }

    const next = input.action === 'approve' ? 'approved' : input.action === 'reject' ? 'rejected' : 'ended';
    await client.query(
      'UPDATE promotions SET status=$2,decision_reason=$3,decided_by=$4,decided_at=now(),updated_at=now() WHERE id=$1',
      [id, next, input.reason, actor.actorId],
    );
    await client.query("INSERT INTO gatework_command_dedup(actor_id,idempotency_key,command_type,result_id) VALUES($1,$2,'promotion.decide',$3)", [actor.actorId, input.idempotencyKey, id]);
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: `promotion.${input.action}`, targetType: 'promotion', targetId: id, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    await client.query('COMMIT');
    return { data: { id, status: next, duplicate: false } };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'PROMOTION_DECISION_FAILED', message: 'Karar kaydedilemedi.' } });
  } finally {
    client.release();
  }
});

/// Placing one straight from the console - the sponsored story slot the panel
/// fills itself, and the "Sana Ozel One Cikanlar" cards, which have no member
/// request behind them. Approved on creation, since the person creating it is
/// the person who would have approved it, and audited for exactly that reason.
app.post('/v1/internal/gatework/promotions', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const input = gateworkPromotionBody.parse(request.body);
    await client.query('BEGIN');
    const prior = await client.query<{ result_id: string | null }>(
      "SELECT result_id FROM gatework_command_dedup WHERE actor_id=$1 AND idempotency_key=$2 AND command_type='promotion.place' FOR UPDATE",
      [actor.actorId, input.idempotencyKey],
    );
    if (prior.rows[0]?.result_id) { await client.query('COMMIT'); return reply.code(200).send({ data: { id: prior.rows[0].result_id } }); }
    if (input.mediaId) {
      const media = await client.query("SELECT 1 FROM media_assets WHERE id=$1 AND status='ready'", [input.mediaId]);
      if (!media.rows[0]) throw Error('MEDIA_NOT_READY');
    }
    const row = await client.query<{ id: string }>(
      `INSERT INTO promotions(owner_id,placement,title,subtitle,media_id,target_kind,target_value,region_code,city,starts_at,ends_at,status,decision_reason,decided_by,decided_at)
       VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'approved',$12,$13,now()) RETURNING id`,
      [input.ownerId, input.placement, input.title, input.subtitle ?? null, input.mediaId ?? null, input.targetKind ?? null, input.targetValue ?? null,
        input.regionCode?.toUpperCase() ?? null, input.city ?? null, input.startsAt, input.endsAt, input.reason, actor.actorId],
    );
    await client.query("INSERT INTO gatework_command_dedup(actor_id,idempotency_key,command_type,result_id) VALUES($1,$2,'promotion.place',$3)", [actor.actorId, input.idempotencyKey, row.rows[0]!.id]);
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'promotion.place', targetType: 'promotion', targetId: row.rows[0]!.id, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    await client.query('COMMIT');
    return reply.code(201).send({ data: row.rows[0] });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'GATEWORK_PROMOTION_REJECTED' } });
  } finally {
    client.release();
  }
});

// --- Forum ---------------------------------------------------------------
// Separate endpoints from the feed because they are separate tables, for the
// reason migration 019 gives: the feed is today, the forum is the archive.
//
// The ordering lives here rather than in the client. "Son hareket" and "en cok
// yanit" differ, and if each client recomputed them, two app versions in the
// wild would show two different forums.
const forumTopicsQuery = z.object({
  categoryId: z.string().uuid().optional(),
  cursor: z.string().max(200).optional(),
  limit: z.coerce.number().int().min(1).max(50).default(20),
  sort: z.enum(['latestActivity', 'newest', 'mostReplies']).default('latestActivity'),
});
const forumTopicBody = z.object({ categoryId: z.string().uuid(), title: z.string().trim().min(8).max(160), body: z.string().trim().min(20).max(8000) });
const forumReplyBody = z.object({ body: z.string().trim().min(1).max(4000) });
const forumLikeBody = z.object({ value: z.boolean() });
const forumRepliesQuery = z.object({ cursor: z.string().max(200).optional(), limit: z.coerce.number().int().min(1).max(100).default(30) });
const forumTrendingQuery = z.object({ limit: z.coerce.number().int().min(1).max(20).default(5) });
const forumSort = {
  latestActivity: { expr: 'COALESCE(t.last_reply_at,t.created_at)', cast: 'timestamptz' },
  newest: { expr: 't.created_at', cast: 'timestamptz' },
  mostReplies: { expr: 't.reply_count', cast: 'int' },
} as const;

type ForumTopicRow = {
  id: string; category_id: string; category_title: string; title: string; body: string;
  author_id: string; author_name: string; created_at: Date; reply_count: number; view_count: string;
  like_count: string; is_liked: boolean; is_pinned: boolean; is_locked: boolean;
  last_reply_at: Date | null; last_reply_author_name: string | null; sort_value: Date | number;
};
type ForumReplyRow = {
  id: string; topic_id: string; author_id: string; author_name: string; body: string;
  created_at: Date; like_count: string; is_liked: boolean; is_accepted_answer: boolean;
};

// The cursor carries the pinned flag as well as the sort value. The ordering
// starts with `is_pinned DESC`, so a cursor that left it out would show the
// pinned topic again at the top of page two.
const forumCursorEncode = (row: { is_pinned: boolean; sort_value: Date | number; id: string }) =>
  Buffer.from(`${row.is_pinned ? 1 : 0}|${row.sort_value instanceof Date ? row.sort_value.toISOString() : row.sort_value}|${row.id}`).toString('base64url');
const forumCursorDecode = (cursor?: string) => {
  if (!cursor) return null;
  try {
    const [pinned, value, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|');
    if (pinned === undefined || !value || !id) throw Error();
    return { pinned: pinned === '1', value, id };
  } catch { throw Object.assign(new Error('Invalid cursor'), { statusCode: 400 }); }
};

const forumTopicSelect = (bodyExpr: string, sortExpr: string) => `
  SELECT t.id,t.category_id,c.title category_title,t.title,${bodyExpr} body,t.author_id,
         COALESCE(p.display_name,'TurkSquare üyesi') author_name,t.created_at,t.reply_count,t.view_count,
         (SELECT count(*) FROM forum_reactions x WHERE x.target_type='topic' AND x.target_id=t.id) like_count,
         EXISTS(SELECT 1 FROM forum_reactions x WHERE x.target_type='topic' AND x.target_id=t.id AND x.actor_id=$1) is_liked,
         t.is_pinned,t.is_locked,t.last_reply_at,
         (SELECT display_name FROM community_profile_projection WHERE user_id=t.last_reply_author_id) last_reply_author_name,
         ${sortExpr} sort_value
    FROM forum_topics t
    JOIN forum_categories c ON c.id=t.category_id
    LEFT JOIN community_profile_projection p ON p.user_id=t.author_id
   WHERE t.deleted_at IS NULL AND t.moderation_state='active'`;

const forumReplySelect = `
  SELECT r.id,r.topic_id,r.author_id,COALESCE(p.display_name,'TurkSquare üyesi') author_name,r.body,r.created_at,
         (SELECT count(*) FROM forum_reactions x WHERE x.target_type='reply' AND x.target_id=r.id) like_count,
         EXISTS(SELECT 1 FROM forum_reactions x WHERE x.target_type='reply' AND x.target_id=r.id AND x.actor_id=$1) is_liked,
         r.is_accepted_answer
    FROM forum_replies r
    LEFT JOIN community_profile_projection p ON p.user_id=r.author_id
   WHERE r.deleted_at IS NULL AND r.moderation_state='active'`;

const forumTopicJson = (row: ForumTopicRow) => ({
  id: row.id,
  categoryId: row.category_id,
  categoryTitle: row.category_title,
  title: row.title,
  body: row.body,
  authorId: row.author_id,
  authorName: row.author_name,
  createdAt: row.created_at.toISOString(),
  replyCount: Number(row.reply_count),
  viewCount: Number(row.view_count),
  likeCount: Number(row.like_count),
  isLiked: row.is_liked,
  isPinned: row.is_pinned,
  isLocked: row.is_locked,
  lastReplyAt: row.last_reply_at ? row.last_reply_at.toISOString() : null,
  lastReplyAuthorName: row.last_reply_author_name,
});

const forumReplyJson = (row: ForumReplyRow) => ({
  id: row.id,
  topicId: row.topic_id,
  authorId: row.author_id,
  authorName: row.author_name,
  body: row.body,
  createdAt: row.created_at.toISOString(),
  likeCount: Number(row.like_count),
  isLiked: row.is_liked,
  isAcceptedAnswer: row.is_accepted_answer,
});

app.get('/v1/community/forum/categories', async (request, reply) => {
  try {
    await viewer(request.headers);
    // Counted on read rather than denormalised like reply_count: the category
    // bar is drawn once per visit, and a stale "0 konu" on a category somebody
    // just wrote in is the one error that would make the forum look empty.
    const rows = await db.query<{ id: string; slug: string; title: string; emoji: string; description: string; topic_count: string; reply_count: string; last_activity_at: Date | null }>(
      `SELECT c.id,c.slug,c.title,c.emoji,c.description,
              count(t.id) topic_count,COALESCE(sum(t.reply_count),0) reply_count,
              max(COALESCE(t.last_reply_at,t.created_at)) last_activity_at
         FROM forum_categories c
         LEFT JOIN forum_topics t ON t.category_id=c.id AND t.deleted_at IS NULL AND t.moderation_state='active'
        WHERE c.is_active
        GROUP BY c.id
        ORDER BY c.ordinal,c.title`,
    );
    return {
      data: rows.rows.map((row) => ({
        id: row.id, slug: row.slug, title: row.title, emoji: row.emoji, description: row.description,
        topicCount: Number(row.topic_count), replyCount: Number(row.reply_count),
        lastActivityAt: row.last_activity_at ? row.last_activity_at.toISOString() : null,
      })),
    };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FORUM_CATEGORIES_UNAVAILABLE', message: 'Forum kategorileri yüklenemedi.' } });
  }
});

app.get('/v1/community/forum/topics', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const input = forumTopicsQuery.parse(request.query);
    const cursor = forumCursorDecode(input.cursor);
    const sort = forumSort[input.sort];
    const params: unknown[] = [userId];
    let where = '';
    if (input.categoryId) { params.push(input.categoryId); where += ` AND t.category_id=$${params.length}::uuid`; }
    if (cursor) {
      params.push(cursor.pinned, cursor.value, cursor.id);
      where += ` AND (t.is_pinned,${sort.expr},t.id) < ($${params.length - 2}::boolean,$${params.length - 1}::${sort.cast},$${params.length}::uuid)`;
    }
    params.push(input.limit + 1);
    // Only the first 240 characters of the body on a list: the card shows two
    // lines of it, and sending 8000 for each of twenty topics to draw them is
    // the kind of waste that is invisible on wifi and obvious on a train.
    const rows = await db.query<ForumTopicRow>(
      `${forumTopicSelect('left(t.body,240)', sort.expr)}${where} ORDER BY t.is_pinned DESC,${sort.expr} DESC,t.id DESC LIMIT $${params.length}`,
      params,
    );
    const page = rows.rows.slice(0, input.limit);
    const last = page[page.length - 1];
    return { data: page.map(forumTopicJson), meta: { nextCursor: rows.rows.length > input.limit && last ? forumCursorEncode(last) : null } };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : (error as { statusCode?: number }).statusCode ?? 400)
      .send({ error: { code: 'FORUM_TOPICS_UNAVAILABLE', message: 'Konular yüklenemedi.' } });
  }
});

// What the home screen's strip is. Not "son hareket": trending is how much a
// topic is being talked about, so it is reply count among topics that moved in
// the last week. Pinned topics stay out - they are at the top because a
// moderator put them there, which says nothing about interest.
app.get('/v1/community/forum/topics/trending', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const input = forumTrendingQuery.parse(request.query);
    const rows = await db.query<ForumTopicRow>(
      `${forumTopicSelect('left(t.body,240)', 't.created_at')}
         AND NOT t.is_pinned AND COALESCE(t.last_reply_at,t.created_at)>now()-interval '7 days'
       ORDER BY t.reply_count DESC,COALESCE(t.last_reply_at,t.created_at) DESC LIMIT $2`,
      [userId, input.limit],
    );
    return { data: rows.rows.map(forumTopicJson) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FORUM_TRENDING_UNAVAILABLE', message: 'Trend tartışmalar yüklenemedi.' } });
  }
});

app.get('/v1/community/forum/topics/:id', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    // The insert is the dedupe: it succeeds once per member, and only then does
    // the counter move. Reopening a topic does not make it look more read.
    const seen = await db.query(
      'INSERT INTO forum_topic_views(topic_id,viewer_id) SELECT $1,$2 WHERE EXISTS(SELECT 1 FROM forum_topics WHERE id=$1 AND deleted_at IS NULL) ON CONFLICT DO NOTHING',
      [id, userId],
    );
    if (seen.rowCount) await db.query('UPDATE forum_topics SET view_count=view_count+1 WHERE id=$1', [id]);
    const rows = await db.query<ForumTopicRow>(`${forumTopicSelect('t.body', 't.created_at')} AND t.id=$2`, [userId, id]);
    if (!rows.rows[0]) return reply.code(404).send({ error: { code: 'FORUM_TOPIC_NOT_FOUND', message: 'Konu bulunamadı.' } });
    return { data: forumTopicJson(rows.rows[0]) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FORUM_TOPIC_UNAVAILABLE', message: 'Konu yüklenemedi.' } });
  }
});

app.post('/v1/community/forum/topics', { config: { rateLimit: { max: 10, timeWindow: '1 hour' } } }, async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const restricted = await activeRestriction(userId);
    if (restricted) return reply.code(403).send(restrictionError(restricted));
    const input = forumTopicBody.parse(request.body);
    // The category check is inside the insert rather than a read before it: a
    // category deactivated between the two would otherwise still take a topic.
    const created = await db.query<{ id: string }>(
      'INSERT INTO forum_topics(category_id,author_id,title,body) SELECT $1,$2,$3,$4 WHERE EXISTS(SELECT 1 FROM forum_categories WHERE id=$1 AND is_active) RETURNING id',
      [input.categoryId, userId, input.title, input.body],
    );
    if (!created.rows[0]) return reply.code(404).send({ error: { code: 'FORUM_CATEGORY_NOT_FOUND', message: 'Kategori bulunamadı.' } });
    const rows = await db.query<ForumTopicRow>(`${forumTopicSelect('t.body', 't.created_at')} AND t.id=$2`, [userId, created.rows[0].id]);
    return reply.code(201).send({ data: forumTopicJson(rows.rows[0]!) });
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FORUM_TOPIC_CREATE_FAILED', message: 'Konu açılamadı.' } });
  }
});

app.get('/v1/community/forum/topics/:id/replies', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = forumRepliesQuery.parse(request.query);
    const cursor = decodeCursor(input.cursor);
    const params: unknown[] = [userId, id];
    let where = '';
    // Oldest first, and the cursor walks forward: a thread is read downwards,
    // which is the opposite of every other list in this service.
    if (cursor) { params.push(cursor.createdAt, cursor.id); where += ` AND (r.created_at,r.id) > ($${params.length - 1}::timestamptz,$${params.length}::uuid)`; }
    params.push(input.limit + 1);
    const rows = await db.query<ForumReplyRow>(`${forumReplySelect} AND r.topic_id=$2${where} ORDER BY r.created_at,r.id LIMIT $${params.length}`, params);
    const page = rows.rows.slice(0, input.limit);
    const last = page[page.length - 1];
    return { data: page.map(forumReplyJson), meta: { nextCursor: rows.rows.length > input.limit && last ? encodeCursor(last) : null } };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : (error as { statusCode?: number }).statusCode ?? 400)
      .send({ error: { code: 'FORUM_REPLIES_UNAVAILABLE', message: 'Yanıtlar yüklenemedi.' } });
  }
});

app.post('/v1/community/forum/topics/:id/replies', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const userId = await viewer(request.headers);
    const restricted = await activeRestriction(userId);
    if (restricted) return reply.code(403).send(restrictionError(restricted));
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = forumReplyBody.parse(request.body);
    await client.query('BEGIN');
    // The lock check and the counter update are one transaction under FOR
    // UPDATE: a topic closed at this exact moment has to refuse the reply, and
    // two replies arriving together have to count as two.
    const topic = await client.query<{ is_locked: boolean }>(
      "SELECT is_locked FROM forum_topics WHERE id=$1 AND deleted_at IS NULL AND moderation_state='active' FOR UPDATE",
      [id],
    );
    if (!topic.rows[0]) { await client.query('ROLLBACK'); return reply.code(404).send({ error: { code: 'FORUM_TOPIC_NOT_FOUND', message: 'Konu bulunamadı.' } }); }
    if (topic.rows[0].is_locked) { await client.query('ROLLBACK'); return reply.code(403).send({ error: { code: 'FORUM_TOPIC_LOCKED', message: 'Bu konu kapatıldı, yeni yanıt yazılamıyor.' } }); }
    const created = await client.query<{ id: string }>('INSERT INTO forum_replies(topic_id,author_id,body) VALUES($1,$2,$3) RETURNING id', [id, userId, input.body]);
    await client.query('UPDATE forum_topics SET reply_count=reply_count+1,last_reply_at=now(),last_reply_author_id=$2 WHERE id=$1', [id, userId]);
    await client.query('COMMIT');
    const rows = await db.query<ForumReplyRow>(`${forumReplySelect} AND r.id=$2`, [userId, created.rows[0]!.id]);
    return reply.code(201).send({ data: forumReplyJson(rows.rows[0]!) });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FORUM_REPLY_FAILED', message: 'Yanıt gönderilemedi.' } });
  } finally {
    client.release();
  }
});

// PUT with the value rather than POST toggling: sending the same request twice
// leaves the same one row, so a retry on a bad connection cannot double a count.
app.put('/v1/community/forum/topics/:id/like', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = forumLikeBody.parse(request.body);
    if (input.value) {
      await db.query(
        "INSERT INTO forum_reactions(target_type,target_id,actor_id) SELECT 'topic',$1,$2 WHERE EXISTS(SELECT 1 FROM forum_topics WHERE id=$1 AND deleted_at IS NULL AND moderation_state='active') ON CONFLICT DO NOTHING",
        [id, userId],
      );
    } else {
      await db.query("DELETE FROM forum_reactions WHERE target_type='topic' AND target_id=$1 AND actor_id=$2", [id, userId]);
    }
    // The whole topic comes back, not just the count: the strip on the home
    // screen and the list behind it both hold this record, and returning the
    // full row is what lets them agree without a second request.
    const rows = await db.query<ForumTopicRow>(`${forumTopicSelect('t.body', 't.created_at')} AND t.id=$2`, [userId, id]);
    if (!rows.rows[0]) return reply.code(404).send({ error: { code: 'FORUM_TOPIC_NOT_FOUND', message: 'Konu bulunamadı.' } });
    return { data: forumTopicJson(rows.rows[0]) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FORUM_LIKE_FAILED', message: 'Beğeni kaydedilemedi.' } });
  }
});

app.put('/v1/community/forum/replies/:id/like', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = forumLikeBody.parse(request.body);
    if (input.value) {
      await db.query(
        "INSERT INTO forum_reactions(target_type,target_id,actor_id) SELECT 'reply',$1,$2 WHERE EXISTS(SELECT 1 FROM forum_replies WHERE id=$1 AND deleted_at IS NULL AND moderation_state='active') ON CONFLICT DO NOTHING",
        [id, userId],
      );
    } else {
      await db.query("DELETE FROM forum_reactions WHERE target_type='reply' AND target_id=$1 AND actor_id=$2", [id, userId]);
    }
    const rows = await db.query<ForumReplyRow>(`${forumReplySelect} AND r.id=$2`, [userId, id]);
    if (!rows.rows[0]) return reply.code(404).send({ error: { code: 'FORUM_REPLY_NOT_FOUND', message: 'Yanıt bulunamadı.' } });
    return { data: forumReplyJson(rows.rows[0]) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FORUM_LIKE_FAILED', message: 'Beğeni kaydedilemedi.' } });
  }
});

// --- Forum administration -----------------------------------------------
// The categories in migration 019 are seeded, not fixed. A forum whose sections
// can only change by shipping a migration is a forum that stops matching what
// people actually ask about, so opening, renaming and retiring one is an
// operator action with an audit line behind it.
const FORUM_EDIT_ROLES: GateworkRole[] = ['owner', 'operations_admin', 'content_editor'];
const FORUM_MODERATE_ROLES: GateworkRole[] = ['owner', 'security_admin', 'operations_admin', 'moderator'];

const gateworkForumCategoryBody = z.object({
  slug: z.string().trim().toLowerCase().regex(/^[a-z0-9-]{2,48}$/),
  title: z.string().trim().min(2).max(80),
  emoji: z.string().trim().min(1).max(8).default('💬'),
  description: z.string().trim().max(240).default(''),
  ordinal: z.coerce.number().int().min(0).max(999).default(0),
  reason: z.string().trim().min(5).max(500),
  idempotencyKey: z.string().uuid(),
});
// Every field optional but at least one present: a PATCH that changes nothing is
// a mistake worth refusing rather than an audit line saying nothing happened.
const gateworkForumCategoryPatch = z.object({
  title: z.string().trim().min(2).max(80).optional(),
  emoji: z.string().trim().min(1).max(8).optional(),
  description: z.string().trim().max(240).optional(),
  ordinal: z.coerce.number().int().min(0).max(999).optional(),
  isActive: z.boolean().optional(),
  reason: z.string().trim().min(5).max(500),
}).refine((value) => value.title !== undefined || value.emoji !== undefined || value.description !== undefined || value.ordinal !== undefined || value.isActive !== undefined);

const gateworkForumTopicState = z.object({
  isPinned: z.boolean().optional(),
  isLocked: z.boolean().optional(),
  reason: z.string().trim().min(5).max(500),
}).refine((value) => value.isPinned !== undefined || value.isLocked !== undefined);

app.get('/v1/internal/gatework/forum/categories', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, [...FORUM_EDIT_ROLES, 'moderator', 'analyst', 'auditor']);
    // Inactive ones included, unlike the member-facing list: retiring a category
    // is reversible, and the operator who has to reverse it needs to see it.
    const rows = await db.query<{ id: string; slug: string; title: string; emoji: string; description: string; ordinal: number; is_active: boolean; topic_count: string; reply_count: string; last_activity_at: Date | null }>(
      `SELECT c.id,c.slug,c.title,c.emoji,c.description,c.ordinal,c.is_active,
              count(t.id) topic_count,COALESCE(sum(t.reply_count),0) reply_count,
              max(COALESCE(t.last_reply_at,t.created_at)) last_activity_at
         FROM forum_categories c
         LEFT JOIN forum_topics t ON t.category_id=c.id AND t.deleted_at IS NULL AND t.moderation_state='active'
        GROUP BY c.id
        ORDER BY c.ordinal,c.title`,
    );
    return {
      data: rows.rows.map((row) => ({
        id: row.id, slug: row.slug, title: row.title, emoji: row.emoji, description: row.description,
        ordinal: row.ordinal, isActive: row.is_active, topicCount: Number(row.topic_count), replyCount: Number(row.reply_count),
        lastActivityAt: row.last_activity_at ? row.last_activity_at.toISOString() : null,
      })),
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'FORUM_CATEGORIES_UNAVAILABLE', message: 'Kategoriler okunamadı.' } });
  }
});

app.post('/v1/internal/gatework/forum/categories', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, FORUM_EDIT_ROLES);
    const input = gateworkForumCategoryBody.parse(request.body);
    // Same dedup table every other Gatework command uses: a double-submitted
    // form opens one category, not two with the same name.
    const prior = await db.query<{ result_id: string | null }>(
      "SELECT result_id FROM gatework_command_dedup WHERE actor_id=$1 AND idempotency_key=$2 AND command_type='forum_category.create'",
      [actor.actorId, input.idempotencyKey],
    );
    if (prior.rows[0]) return { data: { id: prior.rows[0].result_id, duplicate: true } };
    const created = await db.query<{ id: string }>(
      'INSERT INTO forum_categories(slug,title,emoji,description,ordinal) VALUES($1,$2,$3,$4,$5) ON CONFLICT (slug) DO NOTHING RETURNING id',
      [input.slug, input.title, input.emoji, input.description, input.ordinal],
    );
    if (!created.rows[0]) return reply.code(409).send({ error: { code: 'FORUM_CATEGORY_SLUG_TAKEN', message: 'Bu kısa ad zaten kullanılıyor.' } });
    await db.query(
      "INSERT INTO gatework_command_dedup(actor_id,idempotency_key,command_type,result_id) VALUES($1,$2,'forum_category.create',$3)",
      [actor.actorId, input.idempotencyKey, created.rows[0].id],
    );
    await auditGateworkOperation({
      actorId: actor.actorId, roles: actor.roles, action: 'forum_category.create', targetType: 'forum_category',
      targetId: created.rows[0].id, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded',
    });
    return reply.code(201).send({ data: { id: created.rows[0].id, duplicate: false } });
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'FORUM_CATEGORY_CREATE_REJECTED', message: 'Kategori açılamadı.' } });
  }
});

app.patch('/v1/internal/gatework/forum/categories/:id', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, FORUM_EDIT_ROLES);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = gateworkForumCategoryPatch.parse(request.body);
    // The slug is not in the patch on purpose: it is the stable name a saved
    // filter and a link hang off, and renaming it silently breaks both.
    const updated = await db.query<{ id: string }>(
      `UPDATE forum_categories
          SET title=COALESCE($2,title),emoji=COALESCE($3,emoji),description=COALESCE($4,description),
              ordinal=COALESCE($5,ordinal),is_active=COALESCE($6,is_active)
        WHERE id=$1 RETURNING id`,
      [id, input.title ?? null, input.emoji ?? null, input.description ?? null, input.ordinal ?? null, input.isActive ?? null],
    );
    if (!updated.rows[0]) return reply.code(404).send({ error: { code: 'FORUM_CATEGORY_NOT_FOUND', message: 'Kategori bulunamadı.' } });
    await auditGateworkOperation({
      actorId: actor.actorId, roles: actor.roles, action: input.isActive === false ? 'forum_category.deactivate' : 'forum_category.update',
      targetType: 'forum_category', targetId: id, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded',
    });
    return { data: { id } };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'FORUM_CATEGORY_UPDATE_REJECTED', message: 'Kategori güncellenemedi.' } });
  }
});

// The member-facing topic list is not reusable here: it filters to active rows
// and answers a member token. An operator has to be able to reach the topic that
// is already hidden, which is usually the one they are looking for.
const gateworkForumTopicsQuery = z.object({
  categoryId: z.string().uuid().optional(),
  state: z.enum(['active', 'hidden', 'removed', 'all']).default('active'),
  query: z.string().trim().min(2).max(120).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

app.get('/v1/internal/gatework/forum/topics', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, [...FORUM_MODERATE_ROLES, 'content_editor', 'analyst', 'auditor']);
    const input = gateworkForumTopicsQuery.parse(request.query);
    const rows = await db.query<{ id: string; title: string; category_title: string; author_id: string; author_name: string | null; reply_count: number; view_count: string; is_pinned: boolean; is_locked: boolean; moderation_state: string; created_at: Date; last_activity_at: Date }>(
      `SELECT t.id,t.title,c.title category_title,t.author_id,p.display_name author_name,
              t.reply_count,t.view_count,t.is_pinned,t.is_locked,t.moderation_state,
              t.created_at,COALESCE(t.last_reply_at,t.created_at) last_activity_at
         FROM forum_topics t
         JOIN forum_categories c ON c.id=t.category_id
         LEFT JOIN community_profile_projection p ON p.user_id=t.author_id
        WHERE t.deleted_at IS NULL
          AND ($1::uuid IS NULL OR t.category_id=$1)
          AND ($2::text = 'all' OR t.moderation_state=$2)
          AND ($3::text IS NULL OR t.title ILIKE '%'||$3||'%')
        ORDER BY t.is_pinned DESC,COALESCE(t.last_reply_at,t.created_at) DESC
        LIMIT $4`,
      [input.categoryId ?? null, input.state, input.query ?? null, input.limit],
    );
    return {
      data: rows.rows.map((row) => ({
        id: row.id, title: row.title, categoryTitle: row.category_title, authorId: row.author_id,
        authorName: row.author_name, replyCount: row.reply_count, viewCount: Number(row.view_count),
        isPinned: row.is_pinned, isLocked: row.is_locked, moderationState: row.moderation_state,
        createdAt: row.created_at.toISOString(), lastActivityAt: row.last_activity_at.toISOString(),
      })),
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'FORUM_TOPICS_UNAVAILABLE', message: 'Konular okunamadı.' } });
  }
});

// Pinning and locking are moderation, not editing: the rules topic sits at the
// top and takes no replies because someone decided that, and the decision has to
// be as reversible and as recorded as a takedown.
app.post('/v1/internal/gatework/forum/topics/:id/state', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, FORUM_MODERATE_ROLES);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = gateworkForumTopicState.parse(request.body);
    const updated = await db.query<{ is_pinned: boolean; is_locked: boolean }>(
      'UPDATE forum_topics SET is_pinned=COALESCE($2,is_pinned),is_locked=COALESCE($3,is_locked) WHERE id=$1 AND deleted_at IS NULL RETURNING is_pinned,is_locked',
      [id, input.isPinned ?? null, input.isLocked ?? null],
    );
    if (!updated.rows[0]) return reply.code(404).send({ error: { code: 'FORUM_TOPIC_NOT_FOUND', message: 'Konu bulunamadı.' } });
    await auditGateworkOperation({
      actorId: actor.actorId, roles: actor.roles, action: 'forum_topic.state', targetType: 'forum_topic', targetId: id,
      reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded',
    });
    return { data: { id, isPinned: updated.rows[0].is_pinned, isLocked: updated.rows[0].is_locked } };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'FORUM_TOPIC_STATE_REJECTED', message: 'Konu durumu değiştirilemedi.' } });
  }
});

// --- Member operations ---------------------------------------------------
// What the console's Uyeler screen needs from Community. Identity owns the
// account - email, roles, sessions - and is asked separately; this is only what
// the member has done here and what has been decided about them.
app.get('/v1/internal/gatework/community/members/:userId', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, CONTENT_REVIEW_ROLES);
    const userId = z.string().uuid().parse((request.params as { userId: string }).userId);
    const profile = await db.query<{ display_name: string | null; city: string | null; region_code: string | null; origin_country: string | null; created_at: Date | null }>(
      'SELECT p.display_name,p.city,p.region_code,p.origin_country,p.updated_at created_at FROM community_profile_projection p WHERE p.user_id=$1',
      [userId],
    );
    const activity = await db.query<{ posts: string; comments: string; topics: string; replies: string; listings: string }>(
      `SELECT (SELECT count(*) FROM community_posts WHERE author_id=$1 AND deleted_at IS NULL) posts,
              (SELECT count(*) FROM community_comments WHERE author_id=$1 AND deleted_at IS NULL) comments,
              (SELECT count(*) FROM forum_topics WHERE author_id=$1 AND deleted_at IS NULL) topics,
              (SELECT count(*) FROM forum_replies WHERE author_id=$1 AND deleted_at IS NULL) replies,
              (SELECT count(*) FROM marketplace_listings WHERE owner_id=$1) listings`,
      [userId],
    );
    // "Reported how often, upheld how often" is the number that decides whether
    // a restriction is proportionate; one report says almost nothing.
    const reports = await db.query<{ filed: string; upheld: string; open: string }>(
      `SELECT count(*) filed,
              count(*) FILTER (WHERE status='actioned') upheld,
              count(*) FILTER (WHERE status IN ('open','in_review')) open
         FROM content_reports WHERE reported_user_id=$1`,
      [userId],
    );
    const restriction = await activeRestriction(userId);
    const capability = await db.query<{ identity_verified: boolean; auction_seller_eligible: boolean }>(
      'SELECT identity_verified,auction_seller_eligible FROM member_capabilities WHERE user_id=$1',
      [userId],
    );
    const row = activity.rows[0]!;
    const reported = reports.rows[0]!;
    return {
      data: {
        userId,
        displayName: profile.rows[0]?.display_name ?? null,
        city: profile.rows[0]?.city ?? null,
        regionCode: profile.rows[0]?.region_code ?? null,
        originCountry: profile.rows[0]?.origin_country ?? null,
        identityVerified: capability.rows[0]?.identity_verified ?? false,
        auctionSellerEligible: capability.rows[0]?.auction_seller_eligible ?? false,
        activity: { posts: Number(row.posts), comments: Number(row.comments), forumTopics: Number(row.topics), forumReplies: Number(row.replies), listings: Number(row.listings) },
        reports: { filedAgainst: Number(reported.filed), upheld: Number(reported.upheld), open: Number(reported.open) },
        restriction: restriction ? { kind: restriction.kind, reason: restriction.reason, expiresAt: restriction.expires_at?.toISOString() ?? null } : null,
      },
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'MEMBER_UNAVAILABLE', message: 'Üye bilgisi okunamadı.' } });
  }
});

// The Onayli Hesap badge and what it unlocks. `identityVerified` is what the
// verification provider found and is not settable here - the console must not be
// able to declare a document checked that nobody checked. `auctionSellerEligible`
// is the decision made on top of it, which is exactly an operator's call.
const gateworkCapabilityBody = z.object({
  auctionSellerEligible: z.boolean(),
  reason: z.string().trim().min(5).max(500),
});

app.put('/v1/internal/gatework/community/members/:userId/capabilities', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin']);
    const userId = z.string().uuid().parse((request.params as { userId: string }).userId);
    const input = gateworkCapabilityBody.parse(request.body);
    await db.query(
      `INSERT INTO member_capabilities(user_id,auction_seller_eligible) VALUES($1,$2)
       ON CONFLICT (user_id) DO UPDATE SET auction_seller_eligible=EXCLUDED.auction_seller_eligible,updated_at=now()`,
      [userId, input.auctionSellerEligible],
    );
    await auditGateworkOperation({
      actorId: actor.actorId, roles: actor.roles, action: input.auctionSellerEligible ? 'member.capability.grant' : 'member.capability.revoke',
      targetType: 'user', targetId: userId, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded',
    });
    return { data: { userId, auctionSellerEligible: input.auctionSellerEligible } };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'MEMBER_CAPABILITY_REJECTED', message: 'Yetki güncellenemedi.' } });
  }
});

// Restricting straight from the member screen rather than only from a report.
// Some accounts are dealt with before anyone files anything - a spam run seen in
// the feed - and making a moderator invent a report first would put a fictional
// case in the audit trail.
const gateworkRestrictionBody = z.object({
  kind: z.enum(['muted', 'suspended']),
  reason: z.string().trim().min(5).max(500),
  durationHours: z.coerce.number().int().min(1).max(8760).optional(),
  idempotencyKey: z.string().uuid(),
});

app.post('/v1/internal/gatework/community/restrictions/:userId', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, CONTENT_ACT_ROLES);
    const userId = z.string().uuid().parse((request.params as { userId: string }).userId);
    const input = gateworkRestrictionBody.parse(request.body);
    if (userId === actor.actorId) return reply.code(400).send({ error: { code: 'SELF_RESTRICTION_NOT_ALLOWED', message: 'Kendi hesabınızı kısıtlayamazsınız.' } });
    await client.query('BEGIN');
    const prior = await client.query<{ result_id: string | null }>(
      "SELECT result_id FROM gatework_command_dedup WHERE actor_id=$1 AND idempotency_key=$2 AND command_type='member.restrict' FOR UPDATE",
      [actor.actorId, input.idempotencyKey],
    );
    if (prior.rows[0]) { await client.query('COMMIT'); return { data: { userId, duplicate: true } }; }
    await client.query(
      `INSERT INTO content_author_restrictions(user_id,kind,reason,expires_at,created_by)
       VALUES($1,$2,$3,CASE WHEN $4::text IS NULL THEN NULL ELSE now()+($4::text||' hours')::interval END,$5)
       ON CONFLICT (user_id) DO UPDATE SET kind=EXCLUDED.kind,reason=EXCLUDED.reason,expires_at=EXCLUDED.expires_at,created_by=EXCLUDED.created_by,created_at=now()`,
      [userId, input.kind, input.reason, input.durationHours ? String(input.durationHours) : null, actor.actorId],
    );
    await client.query(
      "INSERT INTO content_moderation_actions(report_id,actor_id,actor_roles,action,target_type,target_id,reason) VALUES(NULL,$1,$2,'restrict_author','user',$3,$4)",
      [actor.actorId, actor.roles, userId, input.reason],
    );
    await client.query(
      "INSERT INTO gatework_command_dedup(actor_id,idempotency_key,command_type,result_id) VALUES($1,$2,'member.restrict',$3)",
      [actor.actorId, input.idempotencyKey, userId],
    );
    await auditGateworkOperation({
      actorId: actor.actorId, roles: actor.roles, action: `member.restrict.${input.kind}`, targetType: 'user', targetId: userId,
      reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded',
    });
    await client.query('COMMIT');
    return { data: { userId, duplicate: false } };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'MEMBER_RESTRICTION_REJECTED', message: 'Kısıtlama uygulanamadı.' } });
  } finally {
    client.release();
  }
});

// --- Outbox publisher ---------------------------------------------------
// Same contract as Identity's: the domain write and the outbox row commit
// together, delivery is retried until the broker accepts it, and `occurredAt`
// is the row's commit time so the consumer can discard stale writes.
let publishing = false;

async function publishCommunityOutbox(): Promise<void> {
  if (publishing || !isMessagingProjectionConfigured()) return;
  publishing = true;
  try {
    const pending = await db.query<{ id: string; event_type: string; payload: unknown; created_at: Date }>(
      `SELECT id,event_type,payload,created_at FROM community_outbox_events
       WHERE published_at IS NULL ORDER BY created_at ASC LIMIT 20`,
    );
    for (const event of pending.rows) {
      try {
        await sendMessagingProjectionEvent({ eventId: event.id, eventType: event.event_type, occurredAt: event.created_at.toISOString(), payload: event.payload });
        await db.query('UPDATE community_outbox_events SET published_at=now(),attempts=attempts+1 WHERE id=$1 AND published_at IS NULL', [event.id]);
      } catch (error) {
        await db.query('UPDATE community_outbox_events SET attempts=attempts+1 WHERE id=$1', [event.id]);
        app.log.warn({ err: error, eventId: event.id, eventType: event.event_type }, 'Community outbox delivery deferred');
        break; // The broker is unavailable; the remaining rows wait for the next tick.
      }
    }
  } catch (error) {
    app.log.warn({ err: error }, 'Community outbox drain failed');
  } finally {
    publishing = false;
  }
}

if (isMessagingProjectionConfigured()) {
  setInterval(() => { void publishCommunityOutbox(); }, 5_000).unref();
} else {
  app.log.warn('AZURE_MESSAGING_PROJECTION_QUEUE_NAME is not configured; blocks will not reach messaging');
}

for (const signal of ['SIGTERM', 'SIGINT'] as const) {
  process.once(signal, () => {
    void (async () => {
      await app.close().catch(() => undefined);
      await closeServiceBus();
      await db.end().catch(() => undefined);
      process.exit(0);
    })();
  });
}

await app.listen({ port: Number(process.env.PORT ?? 8081), host: '0.0.0.0' });
