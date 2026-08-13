import Fastify from 'fastify';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import { jwtVerify } from 'jose';
import pg from 'pg';
import { z } from 'zod';

const required = (key: string) => { const value = process.env[key]; if (!value) throw new Error(`Missing ${key}`); return value; };
const db = new pg.Pool({ connectionString: required('DATABASE_URL'), max: 20, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: true } : undefined });
const jwtKey = new TextEncoder().encode(required('JWT_SECRET'));
const app = Fastify({ logger: { redact: ['req.headers.authorization'] } });
const feedQuery = z.object({ mode: z.enum(['forYou', 'nearby', 'following']).default('forYou'), cursor: z.string().max(128).optional(), limit: z.coerce.number().int().min(1).max(50).default(20) });
const interactionBody = z.object({ enabled: z.boolean(), idempotencyKey: z.string().uuid() });
const shareBody = z.object({ idempotencyKey: z.string().uuid() });
const postBody = z.object({ body:z.string().trim().min(1).max(2200), visibility:z.enum(['public','friends_only']).default('public'), locationLabel:z.string().trim().max(120).optional(), marketplaceListingId:z.string().uuid().optional(), poll:z.object({ question:z.string().trim().min(1).max(300), selectionMode:z.enum(['single','multiple']), options:z.array(z.string().trim().min(1).max(160)).min(2).max(4), closesAt:z.string().datetime().optional() }).optional(), idempotencyKey:z.string().uuid() });
const storyBody=z.object({mediaId:z.string().uuid(),visibility:z.enum(['network','public']),ttlHours:z.union([z.literal(6),z.literal(12),z.literal(24)])});
const commentBody=z.object({body:z.string().trim().min(1).max(1000),parentId:z.string().uuid().optional()});
const decodeCursor = (cursor?: string) => { if (!cursor) return null; try { const [createdAt, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|'); if (!createdAt || !id) throw Error(); return { createdAt, id }; } catch { throw Object.assign(new Error('Invalid cursor'), { statusCode: 400 }); } };
const encodeCursor = (row: { created_at: Date; id: string }) => Buffer.from(`${row.created_at.toISOString()}|${row.id}`).toString('base64url');

async function viewer(headers: { authorization?: string }) { const token = headers.authorization?.replace(/^Bearer\s+/i, ''); if (!token) throw Error('UNAUTHORIZED'); const verified = await jwtVerify(token, jwtKey, { issuer: required('JWT_ISSUER'), audience: required('JWT_AUDIENCE') }); if (!verified.payload.sub) throw Error('UNAUTHORIZED'); return verified.payload.sub; }
await app.register(helmet); await app.register(rateLimit, { global: true, max: 120, timeWindow: '1 minute' });

app.get('/v1/community/feed', async (request, reply) => {
  try {
    const userId = await viewer(request.headers); const input = feedQuery.parse(request.query); const cursor = decodeCursor(input.cursor);
    const params: unknown[] = [userId]; let where = `p.deleted_at IS NULL AND p.moderation_state='active' AND (p.visibility='public' OR EXISTS (SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=p.author_id AND r.relationship='friend' AND r.active))`;
    if (input.mode === 'following') where += ` AND EXISTS (SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=p.author_id AND r.active)`;
    if (input.mode === 'nearby') where += ` AND p.location_cell IS NOT NULL AND ST_DWithin(p.location_cell,(SELECT approximate_cell FROM viewer_location_projection WHERE user_id=$1),50000)`;
    if (cursor) { params.push(cursor.createdAt, cursor.id); where += ` AND (p.created_at,p.id) < ($${params.length - 1}::timestamptz,$${params.length}::uuid)`; }
    params.push(input.limit + 1);
    const result = await db.query<{ id: string; created_at: Date; body: string; location_label: string | null; author_name: string; likes: string; comments: string; is_liked: boolean; poll: unknown }>(`SELECT p.id,p.created_at,p.body,p.location_label,COALESCE(cp.display_name,'TurkSquare üyesi') author_name,(SELECT count(*) FROM post_reactions x WHERE x.post_id=p.id AND x.kind='like') likes,0 comments,EXISTS(SELECT 1 FROM post_reactions x WHERE x.post_id=p.id AND x.actor_id=$1 AND x.kind='like') is_liked,(SELECT json_build_object('id',pl.post_id,'selectionMode',pl.selection_mode,'closesAt',pl.closes_at,'options',COALESCE((SELECT json_agg(json_build_object('id',o.id,'label',o.label,'votes',(SELECT count(*) FROM post_poll_votes v WHERE v.option_id=o.id),'selected',EXISTS(SELECT 1 FROM post_poll_votes v WHERE v.option_id=o.id AND v.voter_id=$1)) ORDER BY o.ordinal) FROM post_poll_options o WHERE o.post_id=p.id),'[]'::json)) FROM post_polls pl WHERE pl.post_id=p.id) poll FROM community_posts p LEFT JOIN community_profile_projection cp ON cp.user_id=p.author_id WHERE ${where} ORDER BY p.created_at DESC,p.id DESC LIMIT $${params.length}`, params);
    const page = result.rows.slice(0, input.limit); const next = result.rows.length > input.limit ? encodeCursor(page[page.length - 1]!) : null;
    return { data: page.map((p) => ({ id:p.id, authorName:p.author_name, location:p.location_label ?? '', createdAtLabel:p.created_at.toISOString(), message:p.body, likes:Number(p.likes), comments:Number(p.comments), isLiked:p.is_liked, poll:p.poll ?? null })), meta: { nextCursor: next } };
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
    const kind = input.poll ? 'poll' : input.marketplaceListingId ? 'marketplace_listing' : 'standard'; const result = await client.query<{id:string}>('INSERT INTO community_posts(author_id,kind,visibility,body,location_label,marketplace_listing_id) VALUES($1,$2,$3,$4,$5,$6) RETURNING id',[userId,kind,input.visibility,input.body,input.locationLabel??null,input.marketplaceListingId??null]); const id=result.rows[0]!.id;
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
// FORUM
//
// Akıştan ayrı uçlar, çünkü ayrı tablolar: forum bir arşiv, akış bir gündem.
// Sıralama sunucuda: "son hareket" ile "en çok yanıt" arasındaki farkı istemci
// yeniden hesaplarsa, iki istemci sürümü iki farklı sıra gösterir.
const forumTopicsQuery=z.object({categoryId:z.string().uuid().optional(),cursor:z.string().max(200).optional(),limit:z.coerce.number().int().min(1).max(50).default(20),sort:z.enum(['latestActivity','newest','mostReplies']).default('latestActivity')});
const forumTopicBody=z.object({categoryId:z.string().uuid(),title:z.string().trim().min(8).max(160),body:z.string().trim().min(20).max(8000)});
const forumReplyBody=z.object({body:z.string().trim().min(1).max(4000)});
const forumLikeBody=z.object({value:z.boolean()});
const forumSort={latestActivity:{expr:'COALESCE(t.last_reply_at,t.created_at)',cast:'timestamptz'},newest:{expr:'t.created_at',cast:'timestamptz'},mostReplies:{expr:'t.reply_count',cast:'int'}} as const;
type ForumTopicRow={id:string;category_id:string;category_title:string;title:string;body:string;author_id:string;author_name:string;created_at:Date;reply_count:number;view_count:string;like_count:string;is_liked:boolean;is_pinned:boolean;is_locked:boolean;last_reply_at:Date|null;last_reply_author_name:string|null;sort_value:Date|number};
type ForumReplyRow={id:string;topic_id:string;author_id:string;author_name:string;body:string;created_at:Date;like_count:string;is_liked:boolean;is_accepted_answer:boolean};
// İmleç sabitlenmiş bayrağını da taşıyor: sıralama `is_pinned DESC` ile
// başladığı için, onu dışarıda bırakan bir imleç ikinci sayfada sabit konuyu
// yeniden gösterirdi.
const forumCursorEncode=(row:{is_pinned:boolean;sort_value:Date|number;id:string})=>Buffer.from(`${row.is_pinned?1:0}|${row.sort_value instanceof Date?row.sort_value.toISOString():row.sort_value}|${row.id}`).toString('base64url');
const forumCursorDecode=(cursor?:string)=>{if(!cursor)return null;try{const [pinned,value,id]=Buffer.from(cursor,'base64url').toString('utf8').split('|');if(pinned===undefined||!value||!id)throw Error();return{pinned:pinned==='1',value,id};}catch{throw Object.assign(new Error('Invalid cursor'),{statusCode:400});}};
const forumTopicSelect=(bodyExpr:string,sortExpr:string)=>`SELECT t.id,t.category_id,c.title category_title,t.title,${bodyExpr} body,t.author_id,COALESCE(p.display_name,'TurkSquare üyesi') author_name,t.created_at,t.reply_count,t.view_count,(SELECT count(*) FROM forum_reactions x WHERE x.target_type='topic' AND x.target_id=t.id) like_count,EXISTS(SELECT 1 FROM forum_reactions x WHERE x.target_type='topic' AND x.target_id=t.id AND x.actor_id=$1) is_liked,t.is_pinned,t.is_locked,t.last_reply_at,(SELECT display_name FROM community_profile_projection WHERE user_id=t.last_reply_author_id) last_reply_author_name,${sortExpr} sort_value FROM forum_topics t JOIN forum_categories c ON c.id=t.category_id LEFT JOIN community_profile_projection p ON p.user_id=t.author_id WHERE t.deleted_at IS NULL AND t.moderation_state='active'`;
const forumTopicJson=(r:ForumTopicRow)=>({id:r.id,categoryId:r.category_id,categoryTitle:r.category_title,title:r.title,body:r.body,authorId:r.author_id,authorName:r.author_name,createdAt:r.created_at.toISOString(),replyCount:Number(r.reply_count),viewCount:Number(r.view_count),likeCount:Number(r.like_count),isLiked:r.is_liked,isPinned:r.is_pinned,isLocked:r.is_locked,lastReplyAt:r.last_reply_at?r.last_reply_at.toISOString():null,lastReplyAuthorName:r.last_reply_author_name});
const forumReplyJson=(r:ForumReplyRow)=>({id:r.id,topicId:r.topic_id,authorId:r.author_id,authorName:r.author_name,body:r.body,createdAt:r.created_at.toISOString(),likeCount:Number(r.like_count),isLiked:r.is_liked,isAcceptedAnswer:r.is_accepted_answer});
const forumReplySelect=`SELECT r.id,r.topic_id,r.author_id,COALESCE(p.display_name,'TurkSquare üyesi') author_name,r.body,r.created_at,(SELECT count(*) FROM forum_reactions x WHERE x.target_type='reply' AND x.target_id=r.id) like_count,EXISTS(SELECT 1 FROM forum_reactions x WHERE x.target_type='reply' AND x.target_id=r.id AND x.actor_id=$1) is_liked,r.is_accepted_answer FROM forum_replies r LEFT JOIN community_profile_projection p ON p.user_id=r.author_id WHERE r.deleted_at IS NULL AND r.moderation_state='active'`;

app.get('/v1/community/forum/categories',async(request,reply)=>{try{const userId=await viewer(request.headers);void userId;const rows=await db.query<{id:string;slug:string;title:string;emoji:string;description:string;topic_count:string;reply_count:string;last_activity_at:Date|null}>(`SELECT c.id,c.slug,c.title,c.emoji,c.description,count(t.id) topic_count,COALESCE(sum(t.reply_count),0) reply_count,max(COALESCE(t.last_reply_at,t.created_at)) last_activity_at FROM forum_categories c LEFT JOIN forum_topics t ON t.category_id=c.id AND t.deleted_at IS NULL AND t.moderation_state='active' WHERE c.is_active GROUP BY c.id ORDER BY c.ordinal,c.title`);return{data:rows.rows.map((c)=>({id:c.id,slug:c.slug,title:c.title,emoji:c.emoji,description:c.description,topicCount:Number(c.topic_count),replyCount:Number(c.reply_count),lastActivityAt:c.last_activity_at?c.last_activity_at.toISOString():null}))};}catch{return reply.code(401).send({error:{code:'FORUM_CATEGORIES_FAILED',message:'Forum kategorileri yüklenemedi.'}});}});

app.get('/v1/community/forum/topics',async(request,reply)=>{try{const userId=await viewer(request.headers);const input=forumTopicsQuery.parse(request.query);const cursor=forumCursorDecode(input.cursor);const sort=forumSort[input.sort];const params:unknown[]=[userId];let where='';
  if(input.categoryId){params.push(input.categoryId);where+=` AND t.category_id=$${params.length}::uuid`;}
  if(cursor){params.push(cursor.pinned,cursor.value,cursor.id);where+=` AND (t.is_pinned,${sort.expr},t.id) < ($${params.length-2}::boolean,$${params.length-1}::${sort.cast},$${params.length}::uuid)`;}
  params.push(input.limit+1);
  const rows=await db.query<ForumTopicRow>(`${forumTopicSelect('left(t.body,240)',sort.expr)}${where} ORDER BY t.is_pinned DESC,${sort.expr} DESC,t.id DESC LIMIT $${params.length}`,params);
  const page=rows.rows.slice(0,input.limit);const next=rows.rows.length>input.limit?forumCursorEncode(page[page.length-1]!):null;
  return{data:page.map(forumTopicJson),meta:{nextCursor:next}};
}catch(error){return reply.code((error as {statusCode?:number}).statusCode??401).send({error:{code:'FORUM_TOPICS_FAILED',message:'Konular yüklenemedi.'}});}});

// Trend sırası son hareket değil, konuşulma yoğunluğu: son bir haftada yanıt
// almış konular arasından en çok konuşulanlar. Sabit konular buraya girmiyor,
// çünkü orada duruşları bir moderasyon kararı, bir ilgi göstergesi değil.
app.get('/v1/community/forum/topics/trending',async(request,reply)=>{try{const userId=await viewer(request.headers);const limit=z.coerce.number().int().min(1).max(20).default(5).parse((request.query as {limit?:string}).limit??5);const rows=await db.query<ForumTopicRow>(`${forumTopicSelect('left(t.body,240)','t.created_at')} AND NOT t.is_pinned AND COALESCE(t.last_reply_at,t.created_at)>now()-interval '7 days' ORDER BY t.reply_count DESC,COALESCE(t.last_reply_at,t.created_at) DESC LIMIT $2`,[userId,limit]);return{data:rows.rows.map(forumTopicJson)};}catch{return reply.code(401).send({error:{code:'FORUM_TRENDING_FAILED',message:'Trend tartışmalar yüklenemedi.'}});}});

app.get('/v1/community/forum/topics/:id',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);
  // Okunma sayacı üye başına bir kez artıyor: aynı konuyu ikinci kez açmak onu
  // daha çok okunmuş göstermemeli.
  const seen=await db.query('INSERT INTO forum_topic_views(topic_id,viewer_id) SELECT $1,$2 WHERE EXISTS(SELECT 1 FROM forum_topics WHERE id=$1 AND deleted_at IS NULL) ON CONFLICT DO NOTHING',[id,userId]);
  if(seen.rowCount)await db.query('UPDATE forum_topics SET view_count=view_count+1 WHERE id=$1',[id]);
  const rows=await db.query<ForumTopicRow>(`${forumTopicSelect('t.body','t.created_at')} AND t.id=$2`,[userId,id]);
  if(!rows.rows[0])return reply.code(404).send({error:{code:'FORUM_TOPIC_NOT_FOUND',message:'Konu bulunamadı.'}});
  return{data:forumTopicJson(rows.rows[0])};
}catch{return reply.code(401).send({error:{code:'FORUM_TOPIC_FAILED',message:'Konu yüklenemedi.'}});}});

app.post('/v1/community/forum/topics',async(request,reply)=>{try{const userId=await viewer(request.headers);const input=forumTopicBody.parse(request.body);
  const restricted=await db.query('SELECT 1 FROM content_author_restrictions WHERE user_id=$1 AND lifted_at IS NULL AND (expires_at IS NULL OR expires_at>now())',[userId]);
  if(restricted.rows[0])return reply.code(403).send({error:{code:'AUTHOR_RESTRICTED',message:'Hesabın şu anda kısıtlı.'}});
  const created=await db.query<{id:string}>('INSERT INTO forum_topics(category_id,author_id,title,body) SELECT $1,$2,$3,$4 WHERE EXISTS(SELECT 1 FROM forum_categories WHERE id=$1 AND is_active) RETURNING id',[input.categoryId,userId,input.title,input.body]);
  if(!created.rows[0])return reply.code(400).send({error:{code:'FORUM_CATEGORY_NOT_FOUND',message:'Kategori bulunamadı.'}});
  const rows=await db.query<ForumTopicRow>(`${forumTopicSelect('t.body','t.created_at')} AND t.id=$2`,[userId,created.rows[0].id]);
  return reply.code(201).send({data:forumTopicJson(rows.rows[0]!)});
}catch{return reply.code(400).send({error:{code:'FORUM_TOPIC_CREATE_FAILED',message:'Konu açılamadı.'}});}});

app.get('/v1/community/forum/topics/:id/replies',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);const input=z.object({cursor:z.string().max(200).optional(),limit:z.coerce.number().int().min(1).max(100).default(30)}).parse(request.query);const cursor=decodeCursor(input.cursor);const params:unknown[]=[userId,id];let where='';
  // Yanıtlar eskiden yeniye: bir tartışma yukarıdan aşağıya okunur.
  if(cursor){params.push(cursor.createdAt,cursor.id);where+=` AND (r.created_at,r.id) > ($${params.length-1}::timestamptz,$${params.length}::uuid)`;}
  params.push(input.limit+1);
  const rows=await db.query<ForumReplyRow&{created_at:Date}>(`${forumReplySelect} AND r.topic_id=$2${where} ORDER BY r.created_at,r.id LIMIT $${params.length}`,params);
  const page=rows.rows.slice(0,input.limit);const next=rows.rows.length>input.limit?encodeCursor(page[page.length-1]!):null;
  return{data:page.map(forumReplyJson),meta:{nextCursor:next}};
}catch(error){return reply.code((error as {statusCode?:number}).statusCode??401).send({error:{code:'FORUM_REPLIES_FAILED',message:'Yanıtlar yüklenemedi.'}});}});

app.post('/v1/community/forum/topics/:id/replies',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);const input=forumReplyBody.parse(request.body);const client=await db.connect();try{await client.query('BEGIN');
  // Kilit kontrolü ile sayaç güncellemesi tek işlemde: konu tam bu sırada
  // kapatılırsa yanıt da düşmeli.
  const topic=await client.query<{is_locked:boolean}>('SELECT is_locked FROM forum_topics WHERE id=$1 AND deleted_at IS NULL AND moderation_state=\'active\' FOR UPDATE',[id]);
  if(!topic.rows[0]){await client.query('ROLLBACK');return reply.code(404).send({error:{code:'FORUM_TOPIC_NOT_FOUND',message:'Konu bulunamadı.'}});}
  if(topic.rows[0].is_locked){await client.query('ROLLBACK');return reply.code(403).send({error:{code:'FORUM_TOPIC_LOCKED',message:'Bu konu kapatıldı, yeni yanıt yazılamıyor.'}});}
  const created=await client.query<{id:string}>('INSERT INTO forum_replies(topic_id,author_id,body) VALUES($1,$2,$3) RETURNING id',[id,userId,input.body]);
  await client.query('UPDATE forum_topics SET reply_count=reply_count+1,last_reply_at=now(),last_reply_author_id=$2 WHERE id=$1',[id,userId]);
  await client.query('COMMIT');
  const rows=await db.query<ForumReplyRow>(`${forumReplySelect} AND r.id=$2`,[userId,created.rows[0]!.id]);
  return reply.code(201).send({data:forumReplyJson(rows.rows[0]!)});
}catch(e){await client.query('ROLLBACK');throw e;}finally{client.release();}}catch{return reply.code(400).send({error:{code:'FORUM_REPLY_FAILED',message:'Yanıt gönderilemedi.'}});}});

// Beğeni PUT: aynı isteği iki kez göndermek sayacı iki kez artırmıyor.
app.put('/v1/community/forum/topics/:id/like',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);const input=forumLikeBody.parse(request.body);
  if(input.value)await db.query('INSERT INTO forum_reactions(target_type,target_id,actor_id) SELECT \'topic\',$1,$2 WHERE EXISTS(SELECT 1 FROM forum_topics WHERE id=$1 AND deleted_at IS NULL) ON CONFLICT DO NOTHING',[id,userId]);
  else await db.query('DELETE FROM forum_reactions WHERE target_type=\'topic\' AND target_id=$1 AND actor_id=$2',[id,userId]);
  const rows=await db.query<ForumTopicRow>(`${forumTopicSelect('t.body','t.created_at')} AND t.id=$2`,[userId,id]);
  if(!rows.rows[0])return reply.code(404).send({error:{code:'FORUM_TOPIC_NOT_FOUND',message:'Konu bulunamadı.'}});
  return{data:forumTopicJson(rows.rows[0])};
}catch{return reply.code(400).send({error:{code:'FORUM_LIKE_FAILED',message:'Beğeni kaydedilemedi.'}});}});

app.put('/v1/community/forum/replies/:id/like',async(request,reply)=>{try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);const input=forumLikeBody.parse(request.body);
  if(input.value)await db.query('INSERT INTO forum_reactions(target_type,target_id,actor_id) SELECT \'reply\',$1,$2 WHERE EXISTS(SELECT 1 FROM forum_replies WHERE id=$1 AND deleted_at IS NULL) ON CONFLICT DO NOTHING',[id,userId]);
  else await db.query('DELETE FROM forum_reactions WHERE target_type=\'reply\' AND target_id=$1 AND actor_id=$2',[id,userId]);
  const rows=await db.query<ForumReplyRow>(`${forumReplySelect} AND r.id=$2`,[userId,id]);
  if(!rows.rows[0])return reply.code(404).send({error:{code:'FORUM_REPLY_NOT_FOUND',message:'Yanıt bulunamadı.'}});
  return{data:forumReplyJson(rows.rows[0])};
}catch{return reply.code(400).send({error:{code:'FORUM_LIKE_FAILED',message:'Beğeni kaydedilemedi.'}});}});

// ŞİKÂYET KUYRUĞU
//
// Paylaşım, yorum, Story, forum konusu ve forum yanıtı tek kuyruğa düşüyor:
// moderasyon ekibine iki ayrı listeye bakma yükü bindirmemek için. İçeriğin
// kopyası kayıt anında alınıyor, çünkü yazan onu silebiliyor.
const reportBody=z.object({targetType:z.enum(['post','comment','story','forum_topic','forum_reply']),targetId:z.string().uuid(),category:z.enum(['child_safety','self_harm','violence_threat','hate_speech','harassment','sexual_content','scam_fraud','illegal_goods','spam','other']),note:z.string().trim().max(1000).optional()});
const reportSources={post:'SELECT author_id,body FROM community_posts WHERE id=$1',comment:'SELECT author_id,body FROM community_comments WHERE id=$1',story:'SELECT author_id,NULL body FROM stories WHERE id=$1',forum_topic:'SELECT author_id,title||E\'\\n\'||body body FROM forum_topics WHERE id=$1',forum_reply:'SELECT author_id,body FROM forum_replies WHERE id=$1'} as const;
app.post('/v1/community/reports',async(request,reply)=>{try{const userId=await viewer(request.headers);const input=reportBody.parse(request.body);
  const target=await db.query<{author_id:string;body:string|null}>(reportSources[input.targetType],[input.targetId]);
  if(!target.rows[0])return reply.code(404).send({error:{code:'REPORT_TARGET_NOT_FOUND',message:'Bildirilen içerik bulunamadı.'}});
  const created=await db.query<{id:string}>('INSERT INTO content_reports(reporter_id,target_type,target_id,target_author_id,category,note,content_snapshot) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (reporter_id,target_type,target_id) WHERE state IN(\'open\',\'reviewing\') DO NOTHING RETURNING id',[userId,input.targetType,input.targetId,target.rows[0].author_id,input.category,input.note??null,target.rows[0].body]);
  if(created.rows[0])return reply.code(201).send({data:{id:created.rows[0].id,duplicate:false}});
  // Aynı içeriği ikinci kez bildirmek bir hata değil: istenen şey zaten doğru.
  const existing=await db.query<{id:string}>('SELECT id FROM content_reports WHERE reporter_id=$1 AND target_type=$2 AND target_id=$3 AND state IN(\'open\',\'reviewing\')',[userId,input.targetType,input.targetId]);
  return{data:{id:existing.rows[0]?.id??'',duplicate:true}};
}catch{return reply.code(400).send({error:{code:'REPORT_FAILED',message:'Bildirim kaydedilemedi.'}});}});

app.get('/v1/community/restrictions/me',async(request,reply)=>{try{const userId=await viewer(request.headers);const rows=await db.query<{kind:string;reason:string;expires_at:Date|null}>('SELECT kind,reason,expires_at FROM content_author_restrictions WHERE user_id=$1 AND lifted_at IS NULL AND (expires_at IS NULL OR expires_at>now()) ORDER BY created_at DESC LIMIT 1',[userId]);const row=rows.rows[0];return{data:row?{kind:row.kind,reason:row.reason,expiresAt:row.expires_at?row.expires_at.toISOString():null}:null};}catch{return reply.code(401).send({error:{code:'RESTRICTION_FAILED',message:'Durum okunamadı.'}});}});
await app.listen({ port: Number(process.env.PORT ?? 8081), host: '0.0.0.0' });
