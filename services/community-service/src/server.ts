import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import { createPublicKey } from 'node:crypto';
import { GetPublicKeyCommand, KMSClient } from '@aws-sdk/client-kms';
import { importSPKI, jwtVerify } from 'jose';
import { z } from 'zod';
import { createDatabasePool } from './database.js';

const required = (key: string) => { const value = process.env[key]; if (!value) throw new Error(`Missing ${key}`); return value; };
const db = createDatabasePool();
const identityKms = new KMSClient({});
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
const storyBody=z.object({mediaId:z.string().uuid(),visibility:z.enum(['network','public']),ttlHours:z.union([z.literal(6),z.literal(12),z.literal(24)])});
const commentBody=z.object({body:z.string().trim().min(1).max(1000),parentId:z.string().uuid().optional()});
const listingBody=z.object({title:z.string().trim().min(3).max(140),description:z.string().trim().min(10).max(4000),price:z.coerce.number().nonnegative(),city:z.string().trim().min(2).max(100).optional(),regionCode:z.string().regex(/^[A-Za-z]{2}$/).optional()});
const listingQuery=z.object({cursor:z.string().max(128).optional(),limit:z.coerce.number().int().min(1).max(50).default(20)});
const auctionBody=z.object({startingPrice:z.coerce.number().nonnegative(),minimumIncrement:z.coerce.number().positive(),startsAt:z.string().datetime(),endsAt:z.string().datetime()}).refine((v)=>Date.parse(v.endsAt)>Date.parse(v.startsAt));
const bidBody=z.object({amount:z.coerce.number().positive()});
const decodeCursor = (cursor?: string) => { if (!cursor) return null; try { const [createdAt, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|'); if (!createdAt || !id) throw Error(); return { createdAt, id }; } catch { throw Object.assign(new Error('Invalid cursor'), { statusCode: 400 }); } };
const encodeCursor = (row: { created_at: Date; id: string }) => Buffer.from(`${row.created_at.toISOString()}|${row.id}`).toString('base64url');

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
app.get('/v1/community/stories',async(request,reply)=>{try{const userId=await viewer(request.headers);const rows=await db.query<{id:string;author_id:string;created_at:Date;expires_at:Date;visibility:string;safe_url:string;thumbnail_url:string|null;kind:string}>('SELECT s.id,s.author_id,s.created_at,s.expires_at,s.visibility,m.safe_url,m.thumbnail_url,m.kind FROM stories s JOIN media_assets m ON m.id=s.media_id WHERE s.expires_at>now() AND m.status=\'ready\' AND (s.visibility=\'public\' OR s.author_id=$1 OR EXISTS(SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=s.author_id AND r.active)) ORDER BY s.created_at DESC LIMIT 30',[userId]);return{data:rows.rows};}catch{return reply.code(401).send({error:{code:'STORIES_FAILED',message:'Story yüklenemedi.'}});}});
app.post('/v1/community/stories',async(request,reply)=>{try{const userId=await viewer(request.headers);const input=storyBody.parse(request.body);const media=await db.query('SELECT 1 FROM media_assets WHERE id=$1 AND owner_id=$2 AND status=\'ready\'',[input.mediaId,userId]);if(!media.rows[0])return reply.code(400).send({error:{code:'MEDIA_NOT_READY',message:'Medya hazır değil.'}});const r=await db.query<{id:string}>('INSERT INTO stories(author_id,media_id,visibility,expires_at) VALUES($1,$2,$3,now()+($4::text||\' hours\')::interval) RETURNING id',[userId,input.mediaId,input.visibility,input.ttlHours]);return reply.code(201).send({data:r.rows[0]});}catch{return reply.code(400).send({error:{code:'STORY_CREATE_FAILED',message:'Story oluşturulamadı.'}});}});
app.post('/v1/community/stories/:id/views',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);await db.query('INSERT INTO story_views(story_id,viewer_id) SELECT $1,$2 WHERE EXISTS(SELECT 1 FROM stories WHERE id=$1 AND expires_at>now()) ON CONFLICT DO NOTHING',[id,userId]);return reply.code(204).send();}catch{return reply.code(400).send();}});
app.put('/v1/community/stories/:id/likes',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);const input=interactionBody.parse(request.body);if(input.enabled)await db.query('INSERT INTO story_likes(story_id,actor_id) VALUES($1,$2) ON CONFLICT DO NOTHING',[id,userId]);else await db.query('DELETE FROM story_likes WHERE story_id=$1 AND actor_id=$2',[id,userId]);return reply.code(204).send();}catch{return reply.code(400).send();}});
app.get('/v1/community/posts/:id/comments',async(request,reply)=>{try{const userId=await viewer(request.headers);const postId=z.string().uuid().parse((request.params as {id:string}).id);const rows=await db.query('SELECT id,author_id,parent_id,body,created_at FROM community_comments WHERE post_id=$1 AND deleted_at IS NULL AND moderation_state=\'active\' ORDER BY created_at DESC LIMIT 50',[postId]);return{data:rows.rows};}catch{return reply.code(401).send({error:{code:'COMMENTS_FAILED',message:'Yorumlar yüklenemedi.'}});}});
app.post('/v1/community/posts/:id/comments',async(request,reply)=>{try{const userId=await viewer(request.headers);const postId=z.string().uuid().parse((request.params as {id:string}).id);const input=commentBody.parse(request.body);const post=await db.query('SELECT 1 FROM community_posts WHERE id=$1 AND deleted_at IS NULL AND comments_enabled',[postId]);if(!post.rows[0])return reply.code(403).send({error:{code:'COMMENTS_DISABLED',message:'Yorumlar kapalı.'}});const result=await db.query('INSERT INTO community_comments(post_id,author_id,parent_id,body) VALUES($1,$2,$3,$4) RETURNING id,created_at',[postId,userId,input.parentId??null,input.body]);return reply.code(201).send({data:result.rows[0]});}catch{return reply.code(400).send({error:{code:'COMMENT_CREATE_FAILED',message:'Yorum gönderilemedi.'}});}});
app.delete('/v1/community/comments/:id',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);await db.query('UPDATE community_comments SET deleted_at=now(),moderation_state=\'removed\' WHERE id=$1 AND author_id=$2 AND deleted_at IS NULL',[id,userId]);return reply.code(204).send();}catch{return reply.code(400).send();}});
app.get('/v1/marketplace/listings',async(request,reply)=>{try{const userId=await viewer(request.headers);const input=listingQuery.parse(request.query);const cursor=decodeCursor(input.cursor);const params:unknown[]=[userId];let where="l.status='active'";if(cursor){params.push(cursor.createdAt,cursor.id);where+=` AND (l.created_at,l.id) < ($${params.length-1}::timestamptz,$${params.length}::uuid)`;}params.push(input.limit+1);const rows=await db.query<{id:string;title:string;description:string;price:string;city:string|null;region_code:string|null;created_at:Date;seller_name:string}>(`SELECT l.id,l.title,l.description,l.price,l.city,l.region_code,l.created_at,COALESCE(cp.display_name,'TurkSquare üyesi') seller_name FROM marketplace_listings l LEFT JOIN community_profile_projection cp ON cp.user_id=l.owner_id LEFT JOIN community_profile_projection v ON v.user_id=$1 WHERE ${where} ORDER BY (l.region_code=v.region_code) DESC,l.created_at DESC,l.id DESC LIMIT $${params.length}`,params);const page=rows.rows.slice(0,input.limit);const next=rows.rows.length>input.limit?encodeCursor(page[page.length-1]!):null;return{data:page.map((l)=>({id:l.id,title:l.title,description:l.description,price:Number(l.price),category:'Diğer',condition:'',location:[l.city,l.region_code].filter(Boolean).join(', '),sellerName:l.seller_name,imageUrl:'',isSaved:false,createdAt:l.created_at.toISOString()})),meta:{nextCursor:next}};}catch(error){return reply.code((error as {statusCode?:number}).statusCode??401).send({error:{code:'LISTINGS_UNAVAILABLE'}});}});
app.post('/v1/marketplace/listings',async(request,reply)=>{try{const userId=await viewer(request.headers);const input=listingBody.parse(request.body);const row=await db.query<{id:string}>('INSERT INTO marketplace_listings(owner_id,title,description,price,city,region_code) VALUES($1,$2,$3,$4,$5,$6) RETURNING id',[userId,input.title,input.description,input.price,input.city??null,input.regionCode?.toUpperCase()??null]);return reply.code(201).send({data:row.rows[0]});}catch{return reply.code(400).send({error:{code:'LISTING_CREATE_FAILED'}});}});
app.post('/v1/marketplace/listings/:id/auction',async(request,reply)=>{try{const userId=await viewer(request.headers);const listingId=z.string().uuid().parse((request.params as {id:string}).id);const input=auctionBody.parse(request.body);const eligible=await db.query('SELECT 1 FROM member_capabilities WHERE user_id=$1 AND auction_seller_eligible',[userId]);if(!eligible.rows[0])return reply.code(403).send({error:{code:'VERIFICATION_REQUIRED',message:'İhale açmak için Onaylı Hesap rozeti gerekir.'}});const row=await db.query<{id:string}>('INSERT INTO marketplace_auctions(listing_id,seller_id,starting_price,minimum_increment,starts_at,ends_at) SELECT $1,$2,$3,$4,$5,$6 WHERE EXISTS(SELECT 1 FROM marketplace_listings WHERE id=$1 AND owner_id=$2 AND status=\'active\') RETURNING id',[listingId,userId,input.startingPrice,input.minimumIncrement,input.startsAt,input.endsAt]);if(!row.rows[0])return reply.code(404).send({error:{code:'LISTING_NOT_AVAILABLE'}});return reply.code(201).send({data:row.rows[0]});}catch{return reply.code(400).send({error:{code:'AUCTION_CREATE_FAILED'}});}});
app.post('/v1/marketplace/auctions/:id/bids',async(request,reply)=>{const client=await db.connect();try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);const input=bidBody.parse(request.body);await client.query('BEGIN');const auction=await client.query<{seller_id:string;starting_price:string;minimum_increment:string;starts_at:Date;ends_at:Date}>('SELECT seller_id,starting_price,minimum_increment,starts_at,ends_at FROM marketplace_auctions WHERE id=$1 FOR UPDATE',[id]);const a=auction.rows[0];if(!a||a.seller_id===userId||a.starts_at>new Date()||a.ends_at<=new Date())throw Error();const top=await client.query<{amount:string}>('SELECT amount FROM marketplace_auction_bids WHERE auction_id=$1 ORDER BY amount DESC,created_at ASC LIMIT 1',[id]);const minimum=Number(top.rows[0]?.amount??a.starting_price)+(top.rows[0]?Number(a.minimum_increment):0);if(input.amount<minimum)throw Error();const bid=await client.query<{id:string}>('INSERT INTO marketplace_auction_bids(auction_id,bidder_id,amount) VALUES($1,$2,$3) RETURNING id',[id,userId,input.amount]);await client.query('COMMIT');return reply.code(201).send({data:bid.rows[0]});}catch{await client.query('ROLLBACK');return reply.code(400).send({error:{code:'BID_REJECTED',message:'Teklif kabul edilemedi.'}});}finally{client.release();}});
await app.listen({ port: Number(process.env.PORT ?? 8081), host: '0.0.0.0' });
