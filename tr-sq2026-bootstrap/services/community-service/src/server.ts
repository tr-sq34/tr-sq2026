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
      db.query<{ count: string }>(`SELECT count(*) FROM community_posts p JOIN community_profile_projection v ON v.user_id=$1 WHERE p.deleted_at IS NULL AND p.moderation_state='active' AND p.region_code=v.region_code`, [userId]),
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
    const params: unknown[] = [userId]; let where = `p.deleted_at IS NULL AND p.moderation_state='active' AND (p.visibility='public' OR EXISTS (SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=p.author_id AND r.relationship='friend' AND r.active))`;
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
    await client.query('COMMIT'); return reply.code(201).send({data:{id}});
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
app.post('/v1/community/stories',async(request,reply)=>{const client=await db.connect();try{const userId=await viewer(request.headers);const restricted=await activeRestriction(userId);if(restricted)return reply.code(403).send(restrictionError(restricted));const input=storyBody.parse(request.body);await client.query('BEGIN');const media=await client.query('SELECT 1 FROM media_assets WHERE id=$1 AND owner_id=$2 AND status=\'ready\' FOR KEY SHARE',[input.mediaId,userId]);if(!media.rows[0]){await client.query('ROLLBACK');return reply.code(400).send({error:{code:'MEDIA_NOT_READY',message:'Medya hazır değil.'}});}const r=await client.query<{id:string}>('INSERT INTO stories(author_id,media_id,visibility,region_code,expires_at) SELECT $1,$2,$3,p.region_code,now()+($4::text||\' hours\')::interval FROM community_profile_projection p WHERE p.user_id=$1 RETURNING id',[userId,input.mediaId,input.visibility,input.ttlHours]);if(!r.rows[0]){await client.query('ROLLBACK');return reply.code(400).send({error:{code:'PROFILE_REQUIRED',message:'Story paylaşmadan önce profil konumunu tamamlayın.'}});}if(input.excludedUserIds.length)await client.query('INSERT INTO story_audience_exclusions(story_id,excluded_user_id) SELECT $1,unnest($2::uuid[]) ON CONFLICT DO NOTHING',[r.rows[0].id,input.excludedUserIds]);await client.query('COMMIT');return reply.code(201).send({data:r.rows[0]});}catch{await client.query('ROLLBACK');return reply.code(400).send({error:{code:'STORY_CREATE_FAILED',message:'Story oluşturulamadı.'}});}finally{client.release();}});
// Audience exclusions are an author-controlled deny list. They are checked by
// every Story read/view/like authorization path, never only by the client UI.
app.put('/v1/community/stories/:id/audience/exclusions',{config:{rateLimit:{max:12,timeWindow:'1 minute'}}},async(request,reply)=>{const client=await db.connect();try{const userId=await viewer(request.headers);const storyId=z.string().uuid().parse((request.params as {id:string}).id);const input=storyAudienceExclusionsBody.parse(request.body);await client.query('BEGIN');const story=await client.query('SELECT 1 FROM stories WHERE id=$1 AND author_id=$2 AND expires_at>now() FOR UPDATE',[storyId,userId]);if(!story.rows[0]){await client.query('ROLLBACK');return reply.code(404).send({error:{code:'STORY_NOT_FOUND'}});}await client.query('DELETE FROM story_audience_exclusions WHERE story_id=$1',[storyId]);if(input.excludedUserIds.length)await client.query('INSERT INTO story_audience_exclusions(story_id,excluded_user_id) SELECT $1,unnest($2::uuid[]) ON CONFLICT DO NOTHING',[storyId,input.excludedUserIds]);await client.query('COMMIT');return reply.code(204).send();}catch{await client.query('ROLLBACK');return reply.code(400).send({error:{code:'STORY_AUDIENCE_UPDATE_FAILED',message:'Story görünürlüğü güncellenemedi.'}});}finally{client.release();}});
app.post('/v1/community/story-highlights',{config:{rateLimit:{max:10,timeWindow:'1 minute'}}},async(request,reply)=>{const client=await db.connect();try{const userId=await viewer(request.headers);const input=storyHighlightBody.parse(request.body);await client.query('BEGIN');const owned=await client.query<{id:string;visibility:'network'|'public'}>('SELECT id,visibility FROM stories WHERE author_id=$1 AND id=ANY($2::uuid[])',[userId,input.storyIds]);if(owned.rows.length!==input.storyIds.length||new Set(input.storyIds).size!==input.storyIds.length||(input.visibility==='public'&&owned.rows.some((story)=>story.visibility!=='public'))){await client.query('ROLLBACK');return reply.code(400).send({error:{code:'HIGHLIGHT_STORY_NOT_AVAILABLE',message:'Seçilen Story öne çıkarılamıyor.'}});}const highlight=await client.query<{id:string}>('INSERT INTO story_highlights(owner_id,title,visibility) VALUES($1,$2,$3) RETURNING id',[userId,input.title,input.visibility]);for(const [position,storyId] of input.storyIds.entries())await client.query('INSERT INTO story_highlight_items(highlight_id,story_id,position) VALUES($1,$2,$3)',[highlight.rows[0]!.id,storyId,position]);await client.query('COMMIT');return reply.code(201).send({data:highlight.rows[0]});}catch{await client.query('ROLLBACK');return reply.code(400).send({error:{code:'HIGHLIGHT_CREATE_FAILED',message:'Öne çıkan Story oluşturulamadı.'}});}finally{client.release();}});
app.get('/v1/community/users/:userId/story-highlights',async(request,reply)=>{try{const viewerId=await viewer(request.headers);const ownerId=z.string().uuid().parse((request.params as {userId:string}).userId);const rows=await db.query<{highlight_id:string;title:string;visibility:'network'|'public';created_at:Date;story_id:string;media_id:string;safe_url:string;thumbnail_url:string|null;kind:'image'|'video'}>(`SELECT h.id highlight_id,h.title,h.visibility,h.created_at,si.story_id,m.id media_id,m.safe_url,m.thumbnail_url,m.kind FROM story_highlights h JOIN story_highlight_items si ON si.highlight_id=h.id JOIN stories s ON s.id=si.story_id JOIN media_assets m ON m.id=s.media_id WHERE h.owner_id=$2 AND m.status='ready' AND (h.owner_id=$1 OR (NOT EXISTS(SELECT 1 FROM story_audience_exclusions x WHERE x.story_id=s.id AND x.excluded_user_id=$1) AND (h.visibility='public' OR EXISTS(SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=h.owner_id AND r.active)))) ORDER BY h.created_at DESC,si.position ASC`,[viewerId,ownerId]);const groups=new Map<string,{id:string;title:string;visibility:string;createdAt:string;items:unknown[]}>();for(const row of rows.rows){const group=groups.get(row.highlight_id)??{id:row.highlight_id,title:row.title,visibility:row.visibility,createdAt:row.created_at.toISOString(),items:[]};group.items.push({storyId:row.story_id,media:{id:row.media_id,type:row.kind,url:await mediaObjectUrl(row.safe_url),thumbnailUrl:row.thumbnail_url?await mediaObjectUrl(row.thumbnail_url):null}});groups.set(row.highlight_id,group);}return{data:[...groups.values()]};}catch{return reply.code(400).send({error:{code:'HIGHLIGHTS_UNAVAILABLE',message:'Öne çıkan Storyler yüklenemedi.'}});}});
app.get('/v1/community/me/story-highlights',async(request,reply)=>{try{const userId=await viewer(request.headers);const rows=await db.query<{highlight_id:string;title:string;visibility:'network'|'public';created_at:Date;story_id:string;media_id:string;safe_url:string;thumbnail_url:string|null;kind:'image'|'video'}>(`SELECT h.id highlight_id,h.title,h.visibility,h.created_at,si.story_id,m.id media_id,m.safe_url,m.thumbnail_url,m.kind FROM story_highlights h JOIN story_highlight_items si ON si.highlight_id=h.id JOIN media_assets m ON m.id=(SELECT media_id FROM stories WHERE id=si.story_id) WHERE h.owner_id=$1 AND m.status='ready' ORDER BY h.created_at DESC,si.position ASC`,[userId]);const groups=new Map<string,{id:string;title:string;visibility:string;createdAt:string;items:unknown[]}>();for(const row of rows.rows){const group=groups.get(row.highlight_id)??{id:row.highlight_id,title:row.title,visibility:row.visibility,createdAt:row.created_at.toISOString(),items:[]};group.items.push({storyId:row.story_id,media:{id:row.media_id,type:row.kind,url:await mediaObjectUrl(row.safe_url),thumbnailUrl:row.thumbnail_url?await mediaObjectUrl(row.thumbnail_url):null}});groups.set(row.highlight_id,group);}return{data:[...groups.values()]};}catch{return reply.code(400).send({error:{code:'HIGHLIGHTS_UNAVAILABLE',message:'Öne çıkan Storyler yüklenemedi.'}});}});
app.post('/v1/community/stories/:id/views',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);const access=await db.query(`SELECT 1 FROM stories s WHERE s.id=$1 AND s.expires_at>now() AND ${storyAccessWhere('s','$2')}`,[id,userId]);if(!access.rows[0])return reply.code(404).send({error:{code:'STORY_NOT_FOUND'}});await db.query('INSERT INTO story_views(story_id,viewer_id) VALUES($1,$2) ON CONFLICT DO NOTHING',[id,userId]);return reply.code(204).send();}catch{return reply.code(400).send();}});
app.put('/v1/community/stories/:id/likes',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);const input=interactionBody.parse(request.body);const access=await db.query(`SELECT 1 FROM stories s WHERE s.id=$1 AND s.expires_at>now() AND ${storyAccessWhere('s','$2')}`,[id,userId]);if(!access.rows[0])return reply.code(404).send({error:{code:'STORY_NOT_FOUND'}});if(input.enabled)await db.query('INSERT INTO story_likes(story_id,actor_id) VALUES($1,$2) ON CONFLICT DO NOTHING',[id,userId]);else await db.query('DELETE FROM story_likes WHERE story_id=$1 AND actor_id=$2',[id,userId]);return reply.code(204).send();}catch{return reply.code(400).send();}});
app.get('/v1/community/posts/:id/comments',async(request,reply)=>{try{const userId=await viewer(request.headers);const postId=z.string().uuid().parse((request.params as {id:string}).id);const rows=await db.query('SELECT id,author_id,parent_id,body,created_at FROM community_comments WHERE post_id=$1 AND deleted_at IS NULL AND moderation_state=\'active\' ORDER BY created_at DESC LIMIT 50',[postId]);return{data:rows.rows};}catch{return reply.code(401).send({error:{code:'COMMENTS_FAILED',message:'Yorumlar yüklenemedi.'}});}});
app.post('/v1/community/posts/:id/comments',async(request,reply)=>{try{const userId=await viewer(request.headers);const restricted=await activeRestriction(userId);if(restricted)return reply.code(403).send(restrictionError(restricted));const postId=z.string().uuid().parse((request.params as {id:string}).id);const input=commentBody.parse(request.body);const post=await db.query('SELECT 1 FROM community_posts WHERE id=$1 AND deleted_at IS NULL AND comments_enabled',[postId]);if(!post.rows[0])return reply.code(403).send({error:{code:'COMMENTS_DISABLED',message:'Yorumlar kapalı.'}});const result=await db.query('INSERT INTO community_comments(post_id,author_id,parent_id,body) VALUES($1,$2,$3,$4) RETURNING id,created_at',[postId,userId,input.parentId??null,input.body]);return reply.code(201).send({data:result.rows[0]});}catch{return reply.code(400).send({error:{code:'COMMENT_CREATE_FAILED',message:'Yorum gönderilemedi.'}});}});
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
  targetType: z.enum(['post', 'comment', 'story']),
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
async function captureContentEvidence(client: pg.PoolClient, targetType: 'post' | 'comment' | 'story', targetId: string) {
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
    const inserted = await client.query<{ id: string; created_at: Date; due_at: Date }>(
      `INSERT INTO content_reports(reporter_id,reported_user_id,target_type,target_id,category,note,evidence,priority,due_at)
       VALUES($1,$2,$3,$4,$5,$6,$7::jsonb,$8,now()+($9::text||' hours')::interval)
       RETURNING id,created_at,due_at`,
      [reporterId, captured.authorId, input.targetType, input.targetId, input.category, input.note ?? null, JSON.stringify(captured.evidence), priority, String(slaHours)],
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
  target_type: 'post' | 'comment' | 'story'; target_id: string; category: string; note: string | null;
  evidence: Record<string, unknown>; priority: 'urgent' | 'standard'; status: string; due_at: Date;
  assigned_to: string | null; resolution: string | null; resolved_by: string | null; resolved_at: Date | null;
  created_at: Date; active_restriction: string | null;
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
        ORDER BY (r.status IN ('open','in_review')) DESC, r.due_at ASC, r.id ASC
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

    const report = await client.query<{ id: string; status: string; target_type: 'post' | 'comment' | 'story'; target_id: string; reported_user_id: string }>(
      'SELECT id,status,target_type,target_id,reported_user_id FROM content_reports WHERE id=$1 FOR UPDATE',
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
