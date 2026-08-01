import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import { createPublicKey, randomUUID } from 'node:crypto';
import { GetPublicKeyCommand, KMSClient } from '@aws-sdk/client-kms';
import {
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { importSPKI, jwtVerify } from 'jose';
import { z } from 'zod';
import { createDatabasePool } from './database.js';

const required = (key: string) => { const value = process.env[key]; if (!value) throw new Error(`Missing ${key}`); return value; };
const db = createDatabasePool();
const identityKms = new KMSClient({});
const mediaS3 = new S3Client({});
const mediaBucket = required('COMMUNITY_MEDIA_BUCKET');
const identityVerificationKey = await (async () => {
  const key = await identityKms.send(new GetPublicKeyCommand({ KeyId: required('IDENTITY_JWT_SIGNING_KMS_KEY_ARN') }));
  if (!key.PublicKey) throw new Error('Identity signing public key is unavailable');
  const pem = createPublicKey({ key: Buffer.from(key.PublicKey), format: 'der', type: 'spki' }).export({ format: 'pem', type: 'spki' }).toString();
  return importSPKI(pem, 'RS256');
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
const decodeCursor = (cursor?: string) => { if (!cursor) return null; try { const [createdAt, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|'); if (!createdAt || !id) throw Error(); return { createdAt, id }; } catch { throw Object.assign(new Error('Invalid cursor'), { statusCode: 400 }); } };
const encodeCursor = (row: { created_at: Date; id: string }) => Buffer.from(`${row.created_at.toISOString()}|${row.id}`).toString('base64url');
const sha256Base64 = (hex: string) => Buffer.from(hex, 'hex').toString('base64');
const mediaObjectUrl = async (safeUrlOrKey: string) => {
  if (/^https:\/\//.test(safeUrlOrKey)) return safeUrlOrKey;
  return getSignedUrl(mediaS3, new GetObjectCommand({ Bucket: mediaBucket, Key: safeUrlOrKey }), { expiresIn: 300 });
};

async function viewer(headers: { authorization?: string }) { const token = headers.authorization?.replace(/^Bearer\s+/i, ''); if (!token) throw Error('UNAUTHORIZED'); const verified = await jwtVerify(token, identityVerificationKey, { issuer: required('JWT_ISSUER'), audience: required('JWT_AUDIENCE'), algorithms: ['RS256'] }); if (!verified.payload.sub) throw Error('UNAUTHORIZED'); return verified.payload.sub; }
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
    const uploadUrl = await getSignedUrl(mediaS3, new PutObjectCommand({
      Bucket: mediaBucket,
      Key: quarantineKey,
      ContentType: input.contentType,
      ContentLength: input.sizeBytes,
      ChecksumSHA256: checksum,
      Metadata: { uploadid: uploadId },
    }), { expiresIn: 300 });
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
    const head = await mediaS3.send(new HeadObjectCommand({ Bucket: mediaBucket, Key: row.quarantine_key, ChecksumMode: 'ENABLED' }));
    if (head.ContentLength !== Number(row.expected_size_bytes) || head.ContentType !== row.content_type || head.ChecksumSHA256 !== row.expected_sha256.toString('base64')) {
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
  try { const userId = await viewer(request.headers); const input = postBody.parse(request.body); const client = await db.connect(); try { await client.query('BEGIN');
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
app.post('/v1/community/stories',async(request,reply)=>{const client=await db.connect();try{const userId=await viewer(request.headers);const input=storyBody.parse(request.body);await client.query('BEGIN');const media=await client.query('SELECT 1 FROM media_assets WHERE id=$1 AND owner_id=$2 AND status=\'ready\' FOR KEY SHARE',[input.mediaId,userId]);if(!media.rows[0]){await client.query('ROLLBACK');return reply.code(400).send({error:{code:'MEDIA_NOT_READY',message:'Medya hazır değil.'}});}const r=await client.query<{id:string}>('INSERT INTO stories(author_id,media_id,visibility,region_code,expires_at) SELECT $1,$2,$3,p.region_code,now()+($4::text||\' hours\')::interval FROM community_profile_projection p WHERE p.user_id=$1 RETURNING id',[userId,input.mediaId,input.visibility,input.ttlHours]);if(!r.rows[0]){await client.query('ROLLBACK');return reply.code(400).send({error:{code:'PROFILE_REQUIRED',message:'Story paylaşmadan önce profil konumunu tamamlayın.'}});}if(input.excludedUserIds.length)await client.query('INSERT INTO story_audience_exclusions(story_id,excluded_user_id) SELECT $1,unnest($2::uuid[]) ON CONFLICT DO NOTHING',[r.rows[0].id,input.excludedUserIds]);await client.query('COMMIT');return reply.code(201).send({data:r.rows[0]});}catch{await client.query('ROLLBACK');return reply.code(400).send({error:{code:'STORY_CREATE_FAILED',message:'Story oluşturulamadı.'}});}finally{client.release();}});
// Audience exclusions are an author-controlled deny list. They are checked by
// every Story read/view/like authorization path, never only by the client UI.
app.put('/v1/community/stories/:id/audience/exclusions',{config:{rateLimit:{max:12,timeWindow:'1 minute'}}},async(request,reply)=>{const client=await db.connect();try{const userId=await viewer(request.headers);const storyId=z.string().uuid().parse((request.params as {id:string}).id);const input=storyAudienceExclusionsBody.parse(request.body);await client.query('BEGIN');const story=await client.query('SELECT 1 FROM stories WHERE id=$1 AND author_id=$2 AND expires_at>now() FOR UPDATE',[storyId,userId]);if(!story.rows[0]){await client.query('ROLLBACK');return reply.code(404).send({error:{code:'STORY_NOT_FOUND'}});}await client.query('DELETE FROM story_audience_exclusions WHERE story_id=$1',[storyId]);if(input.excludedUserIds.length)await client.query('INSERT INTO story_audience_exclusions(story_id,excluded_user_id) SELECT $1,unnest($2::uuid[]) ON CONFLICT DO NOTHING',[storyId,input.excludedUserIds]);await client.query('COMMIT');return reply.code(204).send();}catch{await client.query('ROLLBACK');return reply.code(400).send({error:{code:'STORY_AUDIENCE_UPDATE_FAILED',message:'Story görünürlüğü güncellenemedi.'}});}finally{client.release();}});
app.post('/v1/community/story-highlights',{config:{rateLimit:{max:10,timeWindow:'1 minute'}}},async(request,reply)=>{const client=await db.connect();try{const userId=await viewer(request.headers);const input=storyHighlightBody.parse(request.body);await client.query('BEGIN');const owned=await client.query<{id:string;visibility:'network'|'public'}>('SELECT id,visibility FROM stories WHERE author_id=$1 AND id=ANY($2::uuid[])',[userId,input.storyIds]);if(owned.rows.length!==input.storyIds.length||new Set(input.storyIds).size!==input.storyIds.length||(input.visibility==='public'&&owned.rows.some((story)=>story.visibility!=='public'))){await client.query('ROLLBACK');return reply.code(400).send({error:{code:'HIGHLIGHT_STORY_NOT_AVAILABLE',message:'Seçilen Story öne çıkarılamıyor.'}});}const highlight=await client.query<{id:string}>('INSERT INTO story_highlights(owner_id,title,visibility) VALUES($1,$2,$3) RETURNING id',[userId,input.title,input.visibility]);for(const [position,storyId] of input.storyIds.entries())await client.query('INSERT INTO story_highlight_items(highlight_id,story_id,position) VALUES($1,$2,$3)',[highlight.rows[0]!.id,storyId,position]);await client.query('COMMIT');return reply.code(201).send({data:highlight.rows[0]});}catch{await client.query('ROLLBACK');return reply.code(400).send({error:{code:'HIGHLIGHT_CREATE_FAILED',message:'Öne çıkan Story oluşturulamadı.'}});}finally{client.release();}});
app.get('/v1/community/users/:userId/story-highlights',async(request,reply)=>{try{const viewerId=await viewer(request.headers);const ownerId=z.string().uuid().parse((request.params as {userId:string}).userId);const rows=await db.query<{highlight_id:string;title:string;visibility:'network'|'public';created_at:Date;story_id:string;media_id:string;safe_url:string;thumbnail_url:string|null;kind:'image'|'video'}>(`SELECT h.id highlight_id,h.title,h.visibility,h.created_at,si.story_id,m.id media_id,m.safe_url,m.thumbnail_url,m.kind FROM story_highlights h JOIN story_highlight_items si ON si.highlight_id=h.id JOIN stories s ON s.id=si.story_id JOIN media_assets m ON m.id=s.media_id WHERE h.owner_id=$2 AND m.status='ready' AND (h.owner_id=$1 OR (NOT EXISTS(SELECT 1 FROM story_audience_exclusions x WHERE x.story_id=s.id AND x.excluded_user_id=$1) AND (h.visibility='public' OR EXISTS(SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=h.owner_id AND r.active)))) ORDER BY h.created_at DESC,si.position ASC`,[viewerId,ownerId]);const groups=new Map<string,{id:string;title:string;visibility:string;createdAt:string;items:unknown[]}>();for(const row of rows.rows){const group=groups.get(row.highlight_id)??{id:row.highlight_id,title:row.title,visibility:row.visibility,createdAt:row.created_at.toISOString(),items:[]};group.items.push({storyId:row.story_id,media:{id:row.media_id,type:row.kind,url:await mediaObjectUrl(row.safe_url),thumbnailUrl:row.thumbnail_url?await mediaObjectUrl(row.thumbnail_url):null}});groups.set(row.highlight_id,group);}return{data:[...groups.values()]};}catch{return reply.code(400).send({error:{code:'HIGHLIGHTS_UNAVAILABLE',message:'Öne çıkan Storyler yüklenemedi.'}});}});
app.get('/v1/community/me/story-highlights',async(request,reply)=>{try{const userId=await viewer(request.headers);const rows=await db.query<{highlight_id:string;title:string;visibility:'network'|'public';created_at:Date;story_id:string;media_id:string;safe_url:string;thumbnail_url:string|null;kind:'image'|'video'}>(`SELECT h.id highlight_id,h.title,h.visibility,h.created_at,si.story_id,m.id media_id,m.safe_url,m.thumbnail_url,m.kind FROM story_highlights h JOIN story_highlight_items si ON si.highlight_id=h.id JOIN media_assets m ON m.id=(SELECT media_id FROM stories WHERE id=si.story_id) WHERE h.owner_id=$1 AND m.status='ready' ORDER BY h.created_at DESC,si.position ASC`,[userId]);const groups=new Map<string,{id:string;title:string;visibility:string;createdAt:string;items:unknown[]}>();for(const row of rows.rows){const group=groups.get(row.highlight_id)??{id:row.highlight_id,title:row.title,visibility:row.visibility,createdAt:row.created_at.toISOString(),items:[]};group.items.push({storyId:row.story_id,media:{id:row.media_id,type:row.kind,url:await mediaObjectUrl(row.safe_url),thumbnailUrl:row.thumbnail_url?await mediaObjectUrl(row.thumbnail_url):null}});groups.set(row.highlight_id,group);}return{data:[...groups.values()]};}catch{return reply.code(400).send({error:{code:'HIGHLIGHTS_UNAVAILABLE',message:'Öne çıkan Storyler yüklenemedi.'}});}});
app.post('/v1/community/stories/:id/views',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);const access=await db.query(`SELECT 1 FROM stories s WHERE s.id=$1 AND s.expires_at>now() AND ${storyAccessWhere('s','$2')}`,[id,userId]);if(!access.rows[0])return reply.code(404).send({error:{code:'STORY_NOT_FOUND'}});await db.query('INSERT INTO story_views(story_id,viewer_id) VALUES($1,$2) ON CONFLICT DO NOTHING',[id,userId]);return reply.code(204).send();}catch{return reply.code(400).send();}});
app.put('/v1/community/stories/:id/likes',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);const input=interactionBody.parse(request.body);const access=await db.query(`SELECT 1 FROM stories s WHERE s.id=$1 AND s.expires_at>now() AND ${storyAccessWhere('s','$2')}`,[id,userId]);if(!access.rows[0])return reply.code(404).send({error:{code:'STORY_NOT_FOUND'}});if(input.enabled)await db.query('INSERT INTO story_likes(story_id,actor_id) VALUES($1,$2) ON CONFLICT DO NOTHING',[id,userId]);else await db.query('DELETE FROM story_likes WHERE story_id=$1 AND actor_id=$2',[id,userId]);return reply.code(204).send();}catch{return reply.code(400).send();}});
app.get('/v1/community/posts/:id/comments',async(request,reply)=>{try{const userId=await viewer(request.headers);const postId=z.string().uuid().parse((request.params as {id:string}).id);const rows=await db.query('SELECT id,author_id,parent_id,body,created_at FROM community_comments WHERE post_id=$1 AND deleted_at IS NULL AND moderation_state=\'active\' ORDER BY created_at DESC LIMIT 50',[postId]);return{data:rows.rows};}catch{return reply.code(401).send({error:{code:'COMMENTS_FAILED',message:'Yorumlar yüklenemedi.'}});}});
app.post('/v1/community/posts/:id/comments',async(request,reply)=>{try{const userId=await viewer(request.headers);const postId=z.string().uuid().parse((request.params as {id:string}).id);const input=commentBody.parse(request.body);const post=await db.query('SELECT 1 FROM community_posts WHERE id=$1 AND deleted_at IS NULL AND comments_enabled',[postId]);if(!post.rows[0])return reply.code(403).send({error:{code:'COMMENTS_DISABLED',message:'Yorumlar kapalı.'}});const result=await db.query('INSERT INTO community_comments(post_id,author_id,parent_id,body) VALUES($1,$2,$3,$4) RETURNING id,created_at',[postId,userId,input.parentId??null,input.body]);return reply.code(201).send({data:result.rows[0]});}catch{return reply.code(400).send({error:{code:'COMMENT_CREATE_FAILED',message:'Yorum gönderilemedi.'}});}});
app.delete('/v1/community/comments/:id',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);await db.query('UPDATE community_comments SET deleted_at=now(),moderation_state=\'removed\' WHERE id=$1 AND author_id=$2 AND deleted_at IS NULL',[id,userId]);return reply.code(204).send();}catch{return reply.code(400).send();}});
app.get('/v1/marketplace/listings',async(request,reply)=>{try{const userId=await viewer(request.headers);const input=listingQuery.parse(request.query);const cursor=decodeCursor(input.cursor);const params:unknown[]=[userId];let where="l.status='active'";if(cursor){params.push(cursor.createdAt,cursor.id);where+=` AND (l.created_at,l.id) < ($${params.length-1}::timestamptz,$${params.length}::uuid)`;}params.push(input.limit+1);const rows=await db.query<{id:string;title:string;description:string;price:string;city:string|null;region_code:string|null;created_at:Date;seller_name:string}>(`SELECT l.id,l.title,l.description,l.price,l.city,l.region_code,l.created_at,COALESCE(cp.display_name,'TurkSquare üyesi') seller_name FROM marketplace_listings l LEFT JOIN community_profile_projection cp ON cp.user_id=l.owner_id LEFT JOIN community_profile_projection v ON v.user_id=$1 WHERE ${where} ORDER BY (l.region_code=v.region_code) DESC,l.created_at DESC,l.id DESC LIMIT $${params.length}`,params);const page=rows.rows.slice(0,input.limit);const next=rows.rows.length>input.limit?encodeCursor(page[page.length-1]!):null;return{data:page.map((l)=>({id:l.id,title:l.title,description:l.description,price:Number(l.price),category:'Diğer',condition:'',location:[l.city,l.region_code].filter(Boolean).join(', '),sellerName:l.seller_name,imageUrl:'',isSaved:false,createdAt:l.created_at.toISOString()})),meta:{nextCursor:next}};}catch(error){return reply.code((error as {statusCode?:number}).statusCode??401).send({error:{code:'LISTINGS_UNAVAILABLE'}});}});
app.post('/v1/marketplace/listings',async(request,reply)=>{try{const userId=await viewer(request.headers);const input=listingBody.parse(request.body);const row=await db.query<{id:string}>('INSERT INTO marketplace_listings(owner_id,title,description,price,city,region_code) VALUES($1,$2,$3,$4,$5,$6) RETURNING id',[userId,input.title,input.description,input.price,input.city??null,input.regionCode?.toUpperCase()??null]);return reply.code(201).send({data:row.rows[0]});}catch{return reply.code(400).send({error:{code:'LISTING_CREATE_FAILED'}});}});
app.post('/v1/marketplace/listings/:id/auction',async(request,reply)=>{try{const userId=await viewer(request.headers);const listingId=z.string().uuid().parse((request.params as {id:string}).id);const input=auctionBody.parse(request.body);const eligible=await db.query('SELECT 1 FROM member_capabilities WHERE user_id=$1 AND auction_seller_eligible',[userId]);if(!eligible.rows[0])return reply.code(403).send({error:{code:'VERIFICATION_REQUIRED',message:'İhale açmak için Onaylı Hesap rozeti gerekir.'}});const row=await db.query<{id:string}>('INSERT INTO marketplace_auctions(listing_id,seller_id,starting_price,minimum_increment,starts_at,ends_at) SELECT $1,$2,$3,$4,$5,$6 WHERE EXISTS(SELECT 1 FROM marketplace_listings WHERE id=$1 AND owner_id=$2 AND status=\'active\') RETURNING id',[listingId,userId,input.startingPrice,input.minimumIncrement,input.startsAt,input.endsAt]);if(!row.rows[0])return reply.code(404).send({error:{code:'LISTING_NOT_AVAILABLE'}});return reply.code(201).send({data:row.rows[0]});}catch{return reply.code(400).send({error:{code:'AUCTION_CREATE_FAILED'}});}});
app.post('/v1/marketplace/auctions/:id/bids',async(request,reply)=>{const client=await db.connect();try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);const input=bidBody.parse(request.body);await client.query('BEGIN');const auction=await client.query<{seller_id:string;starting_price:string;minimum_increment:string;starts_at:Date;ends_at:Date}>('SELECT seller_id,starting_price,minimum_increment,starts_at,ends_at FROM marketplace_auctions WHERE id=$1 FOR UPDATE',[id]);const a=auction.rows[0];if(!a||a.seller_id===userId||a.starts_at>new Date()||a.ends_at<=new Date())throw Error();const top=await client.query<{amount:string}>('SELECT amount FROM marketplace_auction_bids WHERE auction_id=$1 ORDER BY amount DESC,created_at ASC LIMIT 1',[id]);const minimum=Number(top.rows[0]?.amount??a.starting_price)+(top.rows[0]?Number(a.minimum_increment):0);if(input.amount<minimum)throw Error();const bid=await client.query<{id:string}>('INSERT INTO marketplace_auction_bids(auction_id,bidder_id,amount) VALUES($1,$2,$3) RETURNING id',[id,userId,input.amount]);await client.query('COMMIT');return reply.code(201).send({data:bid.rows[0]});}catch{await client.query('ROLLBACK');return reply.code(400).send({error:{code:'BID_REJECTED',message:'Teklif kabul edilemedi.'}});}finally{client.release();}});
await app.listen({ port: Number(process.env.PORT ?? 8081), host: '0.0.0.0' });
