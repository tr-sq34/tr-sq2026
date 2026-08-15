import Fastify, { type FastifyError } from 'fastify'; import cors from '@fastify/cors'; import rawBody from 'fastify-raw-body'; import helmet from '@fastify/helmet'; import rateLimit from '@fastify/rate-limit'; import Stripe from 'stripe'; import { z } from 'zod'; import { importJWK, jwtVerify } from 'jose'; import { createDatabasePool } from './database.js'; import { getIdentityVerificationKey } from './infrastructure/azureKeyVault.js'; import { sendVerificationCapabilityEvent } from './infrastructure/azureServiceBus.js';
const required=(k:string)=>{const v=process.env[k];if(!v)throw Error(`Missing ${k}`);return v;}; const db=createDatabasePool(); const stripe=new Stripe(required('STRIPE_SECRET_KEY')); const identityKey=await getIdentityVerificationKey(); const verifyKey=await importJWK(identityKey,'RS256'); const app=Fastify({logger:{redact:['req.headers.authorization','req.body']}}); await app.register(helmet);await app.register(rateLimit,{global:true,max:60,timeWindow:'1 minute'});await app.register(cors,{origin:(origin,callback)=>callback(null,!origin||origin==='https://turksquare.com'||origin==='https://www.turksquare.com'||/^http:\/\/localhost:\d+$/.test(origin)),methods:['GET','POST','OPTIONS'],allowedHeaders:['Authorization','Content-Type'],maxAge:600});await app.register(rawBody,{field:'rawBody',global:false,encoding:false,runFirst:true});
/**
 * The last stop for anything a handler did not catch. Whatever slips past the
 * per-route try/catch went out as Fastify's default 500 with the exception's
 * own message in it - a ZodError's dump of the schema, or a driver error naming
 * columns. Neither belongs in a response, and neither is a sentence a screen
 * can show.
 */
app.setErrorHandler((error: FastifyError, request, reply) => {
  if (error instanceof z.ZodError) {
    request.log.warn({ url: request.url, issues: error.issues }, 'request body rejected by schema');
    return reply.code(400).send({ error: { code: 'INVALID_REQUEST', message: 'Gönderilen bilgiler geçersiz.' } });
  }
  const status = error.statusCode ?? 500;
  if (status === 429) {
    return reply.code(429).send({ error: { code: 'RATE_LIMITED', message: 'Çok fazla istek gönderildi. Lütfen biraz sonra tekrar deneyin.' } });
  }
  if (status >= 400 && status < 500) {
    request.log.warn({ url: request.url, err: error }, 'request rejected');
    return reply.code(status).send({ error: { code: 'BAD_REQUEST', message: 'İstek işlenemedi.' } });
  }
  request.log.error({ url: request.url, err: error }, 'unhandled error');
  return reply.code(500).send({ error: { code: 'INTERNAL_ERROR', message: 'Beklenmeyen bir hata oluştu.' } });
});

/**
 * A route that does not exist answered with Fastify's own body -
 * `{"message":"Route PUT:/v1/marketplace/<id>/reactions/save not found","error":"Not Found"}`.
 * That is a second envelope the app has to know about on top of
 * `{error:{code,message}}`, and it prints the requested path back to whoever
 * asked. One shape for every failure; the path stays in the log.
 */
app.setNotFoundHandler((request, reply) => {
  request.log.info({ url: request.url, method: request.method }, 'route not found');
  return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'İstenen adres bulunamadı.' } });
});

const capabilityQueueEnabled=Boolean(process.env.AZURE_SERVICE_BUS_CONNECTION_STRING&&process.env.AZURE_VERIFICATION_CAPABILITY_QUEUE_NAME);
async function publishCapabilities(){if(!capabilityQueueEnabled)return;const events=await db.query<{id:string;event_type:string;payload:unknown}>('SELECT id,event_type,payload FROM verification_outbox_events WHERE published_at IS NULL ORDER BY created_at LIMIT 20');for(const e of events.rows){try{await sendVerificationCapabilityEvent({eventId:e.id,eventType:e.event_type,payload:e.payload});await db.query('UPDATE verification_outbox_events SET published_at=now() WHERE id=$1 AND published_at IS NULL',[e.id]);}catch(error){app.log.warn({err:error,eventId:e.id},'Verification capability outbox deferred');}}}
async function user(headers:{authorization?:string}){const t=headers.authorization?.replace(/^Bearer\s+/i,'');if(!t)throw Error('UNAUTHORIZED');const p=await jwtVerify(t,verifyKey,{issuer:required('JWT_ISSUER'),audience:required('JWT_AUDIENCE'),algorithms:['RS256']});if(!p.payload.sub)throw Error('UNAUTHORIZED');return p.payload.sub;}
// Gatework operators arrive with the delegation token Identity mints for them,
// not with a member token: the audience differs, and the roles ride in `scope`.
// Same contract community-service and the messaging gateway already implement,
// so one delegation opens every operator-facing service and none of them holds
// a credential of its own.
const gateworkRoles=new Set(['owner','security_admin','operations_admin','content_editor','moderator','analyst','auditor']);
const VERIFICATION_READ_ROLES=['owner','security_admin','operations_admin','auditor'];
async function gateworkActor(headers:{authorization?:string}){const token=headers.authorization?.replace(/^Bearer\s+/i,'');if(!token)throw Error('UNAUTHORIZED');const verified=await jwtVerify(token,verifyKey,{issuer:required('JWT_ISSUER'),audience:required('GATEWORK_JWT_AUDIENCE'),algorithms:['RS256']});const actorId=verified.payload.sub;const roles=Array.isArray(verified.payload.scope)?verified.payload.scope.filter((v):v is string=>typeof v==='string'&&gateworkRoles.has(v)):[];if(!actorId||!roles.length)throw Error('UNAUTHORIZED');if(!roles.some((role)=>VERIFICATION_READ_ROLES.includes(role)))throw Error('FORBIDDEN');return{actorId,roles};}
app.get('/health',{config:{rateLimit:false}},async()=>{await db.query('SELECT 1');return{status:'ok'};});
app.get('/v1/verification/status',async(req,reply)=>{try{const id=await user(req.headers);const row=await db.query<{status:string;updated_at:Date}>('SELECT status,updated_at FROM verification_sessions WHERE user_id=$1 ORDER BY updated_at DESC LIMIT 1',[id]);const status=row.rows[0]?.status??'not_started';return{data:{status,identityVerified:status==='verified',auctionSellerEligible:status==='verified',updatedAt:row.rows[0]?.updated_at.toISOString()??null}};}catch{return reply.code(401).send({error:{code:'VERIFICATION_STATUS_UNAVAILABLE'}});}});
app.post('/v1/verification/sessions',async(req,reply)=>{try{const id=await user(req.headers);const session=await stripe.identity.verificationSessions.create({type:'document',options:{document:{require_matching_selfie:true}},metadata:{turksquare_user_id:id},return_url:required('VERIFICATION_RETURN_URL')});await db.query('INSERT INTO verification_sessions(user_id,stripe_session_id,status,policy_version) VALUES($1,$2,$3,$4)',[id,session.id,'created','2026-identity-v1']);return reply.code(201).send({data:{id:session.id,url:session.url}});}catch{return reply.code(400).send({error:{code:'VERIFICATION_SESSION_FAILED'}});}});
// What the console may see of a verification: that it happened, where it got to
// and when. Nothing else exists to show - this service stores no document, no
// image, no name off an ID and no Stripe result detail, only the status Stripe
// reported. An operator screen that could show a passport scan would make this
// database worth stealing, so the absence is the design, not an omission.
app.get('/v1/internal/gatework/verification/sessions',async(req,reply)=>{try{await gateworkActor(req.headers);const input=z.object({status:z.enum(['created','requires_input','verified','canceled','redacted']).optional(),userId:z.string().uuid().optional(),limit:z.coerce.number().int().min(1).max(200).default(100),offset:z.coerce.number().int().min(0).max(10_000).default(0)}).parse(req.query);const rows=await db.query<{id:string;user_id:string;status:string;policy_version:string;created_at:Date;updated_at:Date;expires_at:Date|null;redacted_at:Date|null}>(`SELECT id,user_id,status,policy_version,created_at,updated_at,expires_at,redacted_at FROM verification_sessions WHERE ($3::text IS NULL OR status=$3) AND ($4::uuid IS NULL OR user_id=$4) ORDER BY updated_at DESC,id DESC LIMIT $1 OFFSET $2`,[input.limit,input.offset,input.status??null,input.userId??null]);return{data:rows.rows.map((row)=>({id:row.id,userId:row.user_id,status:row.status,policyVersion:row.policy_version,createdAt:row.created_at.toISOString(),updatedAt:row.updated_at.toISOString(),expiresAt:row.expires_at?.toISOString()??null,redactedAt:row.redacted_at?.toISOString()??null})),meta:{nextOffset:rows.rows.length===input.limit?input.offset+input.limit:null}};}catch(error){return reply.code((error as Error).message==='FORBIDDEN'?403:401).send({error:{code:'VERIFICATION_SESSIONS_UNAVAILABLE',message:'Doğrulama kayıtları okunamadı.'}});}});

// The counts, plus the one number nobody could see before: how many capability
// events are still sitting in the outbox. A member can be verified at Stripe
// and recorded verified here while Community never hears about it - the badge
// simply does not appear and the member reports a bug nobody can reproduce.
// The backlog is that failure, visible before it is reported.
app.get('/v1/internal/gatework/verification/overview',async(req,reply)=>{try{await gateworkActor(req.headers);const[status,outbox]=await Promise.all([db.query<{status:string;count:string}>('SELECT status,count(*) count FROM verification_sessions GROUP BY status'),db.query<{pending:string;oldest:Date|null}>('SELECT count(*) pending,min(created_at) oldest FROM verification_outbox_events WHERE published_at IS NULL')]);const counts:Record<string,number>={created:0,requires_input:0,verified:0,canceled:0,redacted:0};for(const row of status.rows)counts[row.status]=Number(row.count);const oldest=outbox.rows[0]?.oldest??null;return{data:{counts,total:Object.values(counts).reduce((sum,value)=>sum+value,0),outbox:{pending:Number(outbox.rows[0]?.pending??0),oldestPendingAt:oldest?oldest.toISOString():null,queueConfigured:capabilityQueueEnabled}}};}catch(error){return reply.code((error as Error).message==='FORBIDDEN'?403:401).send({error:{code:'VERIFICATION_OVERVIEW_UNAVAILABLE',message:'Doğrulama özeti okunamadı.'}});}});

app.post('/v1/verification/webhooks/stripe',{config:{rawBody:true,rateLimit:false}},async(req,reply)=>{const signature=req.headers['stripe-signature'];const rawBody=(req as typeof req & {rawBody?:Buffer}).rawBody;if(typeof signature!=='string'||!rawBody)return reply.code(400).send();let event:Stripe.Event;try{event=stripe.webhooks.constructEvent(rawBody,signature,required('STRIPE_WEBHOOK_SECRET'));}catch{return reply.code(400).send();}if(!['identity.verification_session.verified','identity.verification_session.requires_input','identity.verification_session.canceled','identity.verification_session.redacted'].includes(event.type))return reply.code(204).send();const session=event.data.object as Stripe.Identity.VerificationSession;const status=event.type.endsWith('.verified')?'verified':event.type.endsWith('.requires_input')?'requires_input':event.type.endsWith('.redacted')?'redacted':'canceled';const c=await db.connect();try{await c.query('BEGIN');if(!(await c.query('INSERT INTO processed_stripe_webhooks(stripe_event_id) VALUES($1) ON CONFLICT DO NOTHING RETURNING stripe_event_id',[event.id])).rowCount){await c.query('COMMIT');return reply.code(204).send();}const row=await c.query<{user_id:string}>('UPDATE verification_sessions SET status=$1,updated_at=now(),redacted_at=CASE WHEN $1=$2 THEN now() ELSE redacted_at END WHERE stripe_session_id=$3 RETURNING user_id',[status,'redacted',session.id]);if(row.rows[0])await c.query('INSERT INTO verification_outbox_events(event_type,payload) VALUES($1,$2)', ['community.member_capabilities_upserted',JSON.stringify({userId:row.rows[0].user_id,identityVerified:status==='verified',auctionSellerEligible:status==='verified'})]);await c.query('COMMIT');return reply.code(204).send();}catch{await c.query('ROLLBACK');return reply.code(500).send();}finally{c.release();}});await app.listen({port:Number(process.env.PORT??8082),host:'0.0.0.0'});void publishCapabilities();const timer=setInterval(()=>void publishCapabilities(),5000);timer.unref();
