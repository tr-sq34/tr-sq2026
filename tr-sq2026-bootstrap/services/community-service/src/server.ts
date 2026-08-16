import Fastify, { type FastifyError, type FastifyReply, type FastifyRequest } from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import { randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { importJWK, jwtVerify } from 'jose';
import { z } from 'zod';
import type pg from 'pg';
import { createDatabasePool } from './database.js';
import { closeServiceBus, isMessagingProjectionConfigured, sendMessagingProjectionEvent } from './infrastructure/azureServiceBus.js';
import { generateMediaUploadSasUrl, generateMediaReadSasUrl, headMediaBlob } from './infrastructure/azureBlob.js';
import { getIdentityVerificationKey } from './infrastructure/azureKeyVault.js';
import { AUTOMATED_BADGE_CODES, advanceProgress, awardBadge, recomputeScore, reporterTrust, revokeBadge, touchStreak } from './journey.js';
import { LOCALITY_MIN_BUCKET, emptyLocalityBucket, suppressSmallBuckets, type LocalityBucket } from './locality.js';
import { MIN_SESSIONS_FOR_RATE, crashFingerprint, crashFreeRate, redactCrashText } from './stability.js';

const required = (key: string) => { const value = process.env[key]; if (!value) throw new Error(`Missing ${key}`); return value; };
const db = createDatabasePool();
const identityVerificationKey = await (async () => {
  const jwk = await getIdentityVerificationKey();
  return importJWK(jwk, 'RS256');
})();
const app = Fastify({ logger: { redact: ['req.headers.authorization'] } });

/**
 * The last stop for anything a handler did not catch.
 *
 * Most routes wrap themselves in try/catch, but "most" is the problem: whatever
 * slips past — a `schema.parse` outside a try, a driver error — went out as
 * Fastify's default 500 with the exception's own message in it. That message is
 * a ZodError's full dump of the schema, or a Postgres error naming columns.
 * Neither belongs in a response, and neither is a sentence the app can show.
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

const feedQuery = z.object({ mode: z.enum(['forYou', 'nearby', 'following']).default('forYou'), cursor: z.string().max(128).optional(), limit: z.coerce.number().int().min(1).max(50).default(20) });
const interactionBody = z.object({ enabled: z.boolean(), idempotencyKey: z.string().uuid() });
const shareBody = z.object({ idempotencyKey: z.string().uuid() });
const postBody = z.object({ body:z.string().trim().min(1).max(2200), visibility:z.enum(['public','friends_only']).default('public'), locationLabel:z.string().trim().max(120).optional(), locationRegionCode:z.string().trim().regex(/^[A-Za-z]{2}$/).optional(), marketplaceListingId:z.string().uuid().optional(), mediaIds:z.array(z.string().uuid()).max(10).optional(), poll:z.object({ question:z.string().trim().min(1).max(300), selectionMode:z.enum(['single','multiple']), options:z.array(z.string().trim().min(1).max(160)).min(2).max(4), closesAt:z.string().datetime().optional() }).optional(), purpose:z.enum(['standard','imece_help','traveler_match']).default('standard'), travelerMatch:z.object({ from:z.string().trim().min(2).max(120), to:z.string().trim().min(2).max(120), travelAt:z.string().datetime(), packageDetails:z.string().trim().min(1).max(500), note:z.string().trim().max(500).optional() }).optional(), idempotencyKey:z.string().uuid() })
  // A traveller post without a trip is the banner with nothing under it, and a
  // trip on a post that is not a traveller post is a detail nothing will ever
  // read. Rejected here rather than half-stored.
  .refine((v) => (v.purpose === 'traveler_match') === (v.travelerMatch !== undefined), { message: 'travelerMatch is required for traveler_match posts and not allowed otherwise' });
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
// The sections Çarşı actually has. Keys, not labels: the chip's Turkish wording
// belongs to the app and can change without touching a stored row. Anything the
// app does not know about would be a listing nobody can reach, so this is a
// closed list on both sides - see migration 030.
const LISTING_CATEGORIES=['vehicle','rental','home','electronics','collectible','art','other'] as const;
const listingBody=z.object({title:z.string().trim().min(3).max(140),description:z.string().trim().min(10).max(4000),price:z.coerce.number().nonnegative(),category:z.enum(LISTING_CATEGORIES).default('other'),city:z.string().trim().min(2).max(100).optional(),regionCode:z.string().regex(/^[A-Za-z]{2}$/).optional(),mediaIds:z.array(z.string().uuid()).max(10).optional()});
const listingQuery=z.object({cursor:z.string().max(128).optional(),limit:z.coerce.number().int().min(1).max(50).default(20),sellerId:z.string().uuid().optional(),category:z.enum(LISTING_CATEGORIES).optional()});
const auctionBody=z.object({startingPrice:z.coerce.number().nonnegative(),minimumIncrement:z.coerce.number().positive(),startsAt:z.string().datetime(),endsAt:z.string().datetime()}).refine((v)=>Date.parse(v.endsAt)>Date.parse(v.startsAt));
const bidBody=z.object({amount:z.coerce.number().positive()});
const gateworkSystemAccountBody=z.object({principalId:z.string().uuid(),displayName:z.string().trim().min(2).max(100),reason:z.string().trim().min(5).max(500),idempotencyKey:z.string().uuid()});
const gateworkPostBody=z.object({authorId:z.string().uuid(),body:z.string().trim().min(1).max(2200),visibility:z.enum(['public','friends_only']).default('public'),regionCode:z.string().trim().regex(/^[A-Za-z]{2}$/).optional(),reason:z.string().trim().min(5).max(500),idempotencyKey:z.string().uuid()});
// Panelden Story. Gorunurluk sorulmuyor: resmi hesabin Story'si herkese acik
// olmak icin var, `network` secilseydi hicbir uyenin arkadasi olmadigi icin
// kimseye gorunmezdi. Sure 24 saatle sinirli, cunku stories tablosunun kendi
// kisiti bu - "surekli duran Story" diye bir sey yok.
const gateworkStoryBody=z.object({authorId:z.string().uuid(),mediaId:z.string().uuid(),ttlHours:z.coerce.number().int().min(1).max(24).default(24),reason:z.string().trim().min(5).max(500),idempotencyKey:z.string().uuid()});
const decodeCursor = (cursor?: string) => { if (!cursor) return null; try { const [createdAt, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|'); if (!createdAt || !id) throw Error(); return { createdAt, id }; } catch { throw Object.assign(new Error('Invalid cursor'), { statusCode: 400 }); } };
const encodeCursor = (row: { created_at: Date; id: string }) => Buffer.from(`${row.created_at.toISOString()}|${row.id}`).toString('base64url');
/**
 * Acilis kartlarinin gorselleri.
 *
 * Bunlar bir uyenin yukledigi medya degil, depoya islenmis dort JPEG: Story
 * seridi hic kart olmadiginda cizilmedigi icin uygulama ilk gun bos aciliyordu.
 * Blob'a konulmadilar, cunku onlari yerlestiren `035` gecisi yalnizca SQL
 * calistirabiliyor - gecis isinde depolama kimlik bilgisi yok. Dosyalar
 * acilista bellege okunuyor; boylece istekte disk yok ve isim listesi kapali,
 * yani yol asimi diye bir sey kalmiyor.
 */
const LAUNCH_ASSET_DIR = new URL('../assets/launch/', import.meta.url);
const launchAssets = new Map<string, Buffer>();
try {
  for (const name of await readdir(LAUNCH_ASSET_DIR)) {
    if (!/^[a-z0-9-]+\.jpg$/.test(name)) continue;
    launchAssets.set(name, await readFile(new URL(name, LAUNCH_ASSET_DIR)));
  }
} catch (error) {
  // Sessizce gecmiyor: kartlar yerinde durur ama gorselleri 404 doner, ve bunun
  // sebebi imajda assets/ klasorunun olmamasidir.
  app.log.error({ err: error }, 'acilis kartlarinin gorselleri okunamadi');
}

const PUBLIC_BASE_URL = (process.env.PUBLIC_BASE_URL ?? 'https://community-api.turksquare.com').replace(/\/$/, '');
const mediaObjectUrl = async (safeUrlOrKey: string) => {
  if (/^https:\/\//.test(safeUrlOrKey)) return safeUrlOrKey;
  // `launch/...` bir blob anahtari degil, servisin kendi sunduğu dosya. Imzali
  // bir SAS uretilmeye calisilsaydi var olmayan bir blob icin gecerli gorunen
  // ama 404 donen bir baglanti cikardi.
  if (safeUrlOrKey.startsWith('launch/')) return `${PUBLIC_BASE_URL}/v1/public/${safeUrlOrKey}`;
  return generateMediaReadSasUrl(safeUrlOrKey, 300);
};


async function viewer(headers: { authorization?: string }) { const token = headers.authorization?.replace(/^Bearer\s+/i, ''); if (!token) throw Error('UNAUTHORIZED'); const verified = await jwtVerify(token, identityVerificationKey, { issuer: required('JWT_ISSUER'), audience: required('JWT_AUDIENCE'), algorithms: ['RS256'] }); if (!verified.payload.sub) throw Error('UNAUTHORIZED'); return verified.payload.sub; }
/// Six read routes used to answer `statusCode ?? 401`, which meant a SQL error,
/// a missing blob credential or any other internal fault left the service as a
/// 401. That is not a cosmetic mislabel: the app treats 401 on an authenticated
/// request as "this session is over", clears the token store and signs the
/// member out. One broken query on the story strip was enough to empty every
/// other screen in the app, and the log said "unauthorized" while the token was
/// perfectly valid.
///
/// 401 is now reserved for the one thing that means it - `viewer()` refusing
/// the token. Everything else is a 500 and gets logged, because a fault the
/// server cannot explain is not the member's session's fault.
const readFailureStatus = (error: unknown) =>
  (error as { statusCode?: number }).statusCode
  ?? ((error as Error)?.message === 'UNAUTHORIZED' ? 401 : 500);

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

/// Kimlik istemeyen tek okuma yolu. Icerigi depodan gelen sabit dort dosya;
/// uye verisi degil, bu yuzden imzali baglantiya gerek yok. Uygulama bu
/// baglantiyi zaten kimlikli bir yanitin icinde aliyor ve gorseli baslıksiz
/// cekiyor - blob SAS baglantilarinin calistigi bicimin aynisi.
app.get('/v1/public/launch/:name', async (request, reply) => {
  const body = launchAssets.get((request.params as { name: string }).name);
  if (!body) return reply.code(404).send({ error: { code: 'ASSET_NOT_FOUND', message: 'Gorsel bulunamadi.' } });
  return reply
    .header('content-type', 'image/jpeg')
    .header('cache-control', 'public, max-age=86400, immutable')
    .send(body);
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

/**
 * App stability: the two ingest routes and the one the console reads.
 *
 * A member's session is the only place that knows the app died - by the time
 * anyone notices in the console the process is gone, and the emulator walkthrough
 * that produced this feature is not a reporting system. `/health` above proves a
 * service is up; nothing proved the app on a member's phone was.
 *
 * Both ingest routes take an optional viewer. A crash on the login screen, or
 * one that happens after the session was cleared, is exactly the crash worth
 * counting - requiring a token would blind the endpoint to the failures that
 * happen earliest.
 */
const launchBody = z.object({
  sessionId: z.string().uuid(),
  platform: z.enum(['android', 'ios', 'web', 'other']),
  appVersion: z.string().trim().min(1).max(40),
  osVersion: z.string().trim().max(80).optional(),
  deviceModel: z.string().trim().max(120).optional(),
});
const crashReportBody = launchBody.extend({
  sessionId: z.string().uuid().optional(),
  fatal: z.boolean(),
  errorType: z.string().trim().min(1).max(160),
  message: z.string().trim().min(1).max(1000),
  screen: z.string().trim().max(120).optional(),
  stack: z.string().trim().max(8000).optional(),
});
const stabilityQuery = z.object({ hours: z.coerce.number().int().min(1).max(720).default(24) });

/// `viewer()` throws when there is no token, which is the right answer for a
/// feed and the wrong one for telemetry.
const optionalViewer = async (headers: { authorization?: string }) => {
  try { return await viewer(headers); } catch { return null; }
};

/// Thirty days, swept from the ingest path rather than a cron: this service has
/// no scheduler, and a table nobody prunes is a table that eventually decides
/// how much the database costs. Once an hour at most, and never in the way of
/// the response - a failed sweep must not turn into a failed crash report.
const STABILITY_RETENTION_DAYS = 30;
let lastStabilitySweep = 0;
function sweepStabilityRetention() {
  const now = Date.now();
  if (now - lastStabilitySweep < 3_600_000) return;
  lastStabilitySweep = now;
  void (async () => {
    try {
      await db.query(`DELETE FROM app_crash_reports WHERE occurred_at < now() - make_interval(days => $1::int)`, [STABILITY_RETENTION_DAYS]);
      await db.query(`DELETE FROM app_launch_sessions WHERE started_at < now() - make_interval(days => $1::int)`, [STABILITY_RETENTION_DAYS]);
    } catch (error) {
      app.log.warn({ err: error }, 'stability retention sweep failed');
    }
  })();
}

// The two ingest routes parse outside their try block on purpose. A malformed
// body is the caller's mistake, and the global error handler already turns a
// ZodError into a 400; catching it here would answer 500 and write an
// error-level line, which is exactly the noise this feature exists to remove
// from the log.
app.post('/v1/app/launches', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (request, reply) => {
  const input = launchBody.parse(request.body);
  try {
    const memberId = await optionalViewer(request.headers);
    // The app retries this on a flaky network and reuses one id for the life of
    // the process, so a repeat is the same launch, not a second one.
    await db.query(
      `INSERT INTO app_launch_sessions(id, member_id, platform, app_version, os_version, device_model)
       VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT (id) DO NOTHING`,
      [input.sessionId, memberId, input.platform, input.appVersion, input.osVersion ?? null, input.deviceModel ?? null],
    );
    return reply.code(202).send({ data: { recorded: true } });
  } catch (error) {
    request.log.error({ err: error }, 'app launch ingest failed');
    return reply.code(500).send({ error: { code: 'LAUNCH_NOT_RECORDED', message: 'Oturum kaydedilemedi.' } });
  }
});

app.post('/v1/app/crashes', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (request, reply) => {
  const input = crashReportBody.parse(request.body);
  try {
    const memberId = await optionalViewer(request.headers);
    const message = redactCrashText(input.message);
    const stack = input.stack ? redactCrashText(input.stack) : null;
    const fingerprint = crashFingerprint({ errorType: input.errorType, message, stack });
    await db.query(
      `INSERT INTO app_crash_reports(session_id, member_id, platform, app_version, os_version, device_model, fatal, error_type, message, screen, stack, fingerprint)
       VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
      [input.sessionId ?? null, memberId, input.platform, input.appVersion, input.osVersion ?? null, input.deviceModel ?? null,
        input.fatal, input.errorType, message, input.screen ?? null, stack, fingerprint],
    );
    // Only a fatal one ruins the session. A handled error the app recovered from
    // is worth reading and must not move the crash-free rate.
    if (input.fatal && input.sessionId) {
      await db.query('UPDATE app_launch_sessions SET crashed = TRUE WHERE id = $1', [input.sessionId]);
    }
    sweepStabilityRetention();
    return reply.code(202).send({ data: { recorded: true } });
  } catch (error) {
    request.log.error({ err: error }, 'app crash ingest failed');
    return reply.code(500).send({ error: { code: 'CRASH_NOT_RECORDED', message: 'Hata raporu kaydedilemedi.' } });
  }
});

app.get('/v1/internal/gatework/system/stability', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'security_admin', 'operations_admin', 'auditor', 'analyst']);
    const { hours } = stabilityQuery.parse(request.query);

    const [current, previous, crashes, groups, platforms] = await Promise.all([
      db.query<{ sessions: number; crashed_sessions: number }>(
        `SELECT count(*)::int AS sessions, count(*) FILTER (WHERE crashed)::int AS crashed_sessions
           FROM app_launch_sessions WHERE started_at > now() - make_interval(hours => $1::int)`, [hours]),
      // The same length of time immediately before it. "%99.1" says nothing on
      // its own; "%99.1, dün %99.8" is the sentence an operator acts on.
      db.query<{ sessions: number; crashed_sessions: number }>(
        `SELECT count(*)::int AS sessions, count(*) FILTER (WHERE crashed)::int AS crashed_sessions
           FROM app_launch_sessions
          WHERE started_at > now() - make_interval(hours => $1::int) * 2
            AND started_at <= now() - make_interval(hours => $1::int)`, [hours]),
      db.query<{ crashes: number; fatal_crashes: number }>(
        `SELECT count(*)::int AS crashes, count(*) FILTER (WHERE fatal)::int AS fatal_crashes
           FROM app_crash_reports WHERE occurred_at > now() - make_interval(hours => $1::int)`, [hours]),
      db.query(
        `SELECT fingerprint,
                (array_agg(error_type ORDER BY occurred_at DESC))[1] AS error_type,
                (array_agg(message ORDER BY occurred_at DESC))[1] AS message,
                (array_agg(screen ORDER BY occurred_at DESC))[1] AS screen,
                count(*)::int AS occurrences,
                count(DISTINCT session_id)::int AS sessions,
                bool_or(fatal) AS fatal,
                max(occurred_at) AS last_seen,
                array_agg(DISTINCT platform) AS platforms,
                array_agg(DISTINCT app_version) AS app_versions,
                array_remove(array_agg(DISTINCT device_model), NULL) AS device_models
           FROM app_crash_reports WHERE occurred_at > now() - make_interval(hours => $1::int)
          GROUP BY fingerprint ORDER BY count(*) DESC, max(occurred_at) DESC LIMIT 8`, [hours]),
      db.query<{ platform: string; sessions: number; crashed_sessions: number }>(
        `SELECT platform, count(*)::int AS sessions, count(*) FILTER (WHERE crashed)::int AS crashed_sessions
           FROM app_launch_sessions WHERE started_at > now() - make_interval(hours => $1::int)
          GROUP BY platform ORDER BY count(*) DESC`, [hours]),
    ]);

    const window = { sessions: current.rows[0].sessions, crashedSessions: current.rows[0].crashed_sessions };
    const before = { sessions: previous.rows[0].sessions, crashedSessions: previous.rows[0].crashed_sessions };

    return {
      data: {
        windowHours: hours,
        minSessionsForRate: MIN_SESSIONS_FOR_RATE,
        sessions: window.sessions,
        crashedSessions: window.crashedSessions,
        crashFreeRate: crashFreeRate(window),
        previous: { sessions: before.sessions, crashFreeRate: crashFreeRate(before) },
        crashes: crashes.rows[0].crashes,
        fatalCrashes: crashes.rows[0].fatal_crashes,
        platforms: platforms.rows.map((row) => ({
          platform: row.platform,
          sessions: row.sessions,
          crashFreeRate: crashFreeRate({ sessions: row.sessions, crashedSessions: row.crashed_sessions }),
        })),
        groups: groups.rows.map((row) => ({
          fingerprint: row.fingerprint,
          errorType: row.error_type,
          message: row.message,
          screen: row.screen,
          occurrences: row.occurrences,
          sessions: row.sessions,
          fatal: row.fatal,
          lastSeen: row.last_seen,
          platforms: row.platforms,
          appVersions: row.app_versions,
          deviceModels: row.device_models,
        })),
      },
    };
  } catch (error) {
    // Same rule as the read routes below: 401 means the token was refused and
    // nothing else. A broken query here must not read as an expired session.
    const message = (error as Error)?.message;
    const status = message === 'FORBIDDEN' ? 403 : message === 'UNAUTHORIZED' ? 401 : 500;
    if (status >= 500) request.log.error({ err: error }, 'stability read failed');
    return reply.code(status).send({ error: { code: 'STABILITY_UNAVAILABLE', message: 'Kararlılık verisi okunamadı.' } });
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

/// The official accounts, for the console to pick from.
///
/// Creating one returned an id and nothing ever listed them again, so an editor
/// had to keep a UUID somewhere outside the product and paste it into every
/// publish form. A wrong paste was not caught by the form - it was caught by
/// the publish endpoint, after the article had been written - and a UUID does
/// not tell you which account you got.
///
/// The counts travel with the row because "which account is this" is answered
/// by what it has published, not by its id.
app.get('/v1/internal/gatework/system-accounts', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const rows = await db.query<{ user_id: string; display_name: string | null; active: boolean; created_at: Date; news_count: string; post_count: string }>(
      `SELECT s.user_id,p.display_name,s.active,s.created_at,
              (SELECT count(*) FROM news_articles a WHERE a.author_id=s.user_id AND a.deleted_at IS NULL) news_count,
              (SELECT count(*) FROM community_posts c WHERE c.author_id=s.user_id AND c.deleted_at IS NULL) post_count
         FROM community_system_accounts s
         LEFT JOIN community_profile_projection p ON p.user_id=s.user_id
        WHERE s.role='official'
        ORDER BY s.active DESC, p.display_name ASC`,
    );
    return {
      data: rows.rows.map((row) => ({
        id: row.user_id,
        displayName: row.display_name,
        active: row.active,
        createdAt: row.created_at.toISOString(),
        newsCount: Number(row.news_count),
        postCount: Number(row.post_count),
      })),
    };
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'GATEWORK_SYSTEM_ACCOUNTS_UNAVAILABLE', message: 'Resmî hesaplar okunamadı.' } });
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

/* --- Panelden Story --------------------------------------------------------
 *
 * Story serisi ana sayfanin en ustunde duruyor ve yeni bir uyenin agi bos
 * oldugu icin ilk gun tamamen bos kaliyor. Sponsorlu yuvalar (`promotions`,
 * placement='story_slot') zaten panelden yerlestirilebiliyordu; platformun
 * kendi Story'si icin bir yol yoktu.
 *
 * Resmi hesabin Story'si herkese gorunur: `storyAccessWhere` aktif resmi
 * hesaplari bolgeye ve arkadaslik iliskisine bakmadan geciriyor. Bu yuzden
 * burada bolge secilmiyor - yazilsaydi sadece o eyalettekilere gorunurdu.
 */
app.post('/v1/internal/gatework/stories', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const input = gateworkStoryBody.parse(request.body);
    const client = await db.connect();
    try {
      await client.query('BEGIN');
      const prior = await client.query<{ result_id: string | null }>("SELECT result_id FROM gatework_command_dedup WHERE actor_id=$1 AND idempotency_key=$2 AND command_type='official_story.create' FOR UPDATE", [actor.actorId, input.idempotencyKey]);
      if (prior.rows[0]?.result_id) {
        await client.query('COMMIT');
        return reply.code(200).send({ data: { id: prior.rows[0].result_id } });
      }
      const official = await client.query("SELECT 1 FROM community_system_accounts WHERE user_id=$1 AND role='official' AND active", [input.authorId]);
      if (!official.rows[0]) throw Error('OFFICIAL_NOT_ACTIVE');
      // Medya, saklanmadan once dogrulaniyor: taranmamis bir kimlikle acilan
      // Story okuma tarafinda `m.status='ready'` suzgecine takilir ve panelde
      // "yayinlandi" yazarken uygulamada hic gorunmezdi.
      const media = await client.query("SELECT 1 FROM media_assets WHERE id=$1 AND owner_id=$2 AND status='ready'", [input.mediaId, input.authorId]);
      if (!media.rows[0]) throw Error('MEDIA_NOT_READY');
      const story = await client.query<{ id: string }>(
        "INSERT INTO stories(author_id,media_id,visibility,region_code,expires_at) VALUES($1,$2,'public',NULL,now()+($3::text||' hours')::interval) RETURNING id",
        [input.authorId, input.mediaId, input.ttlHours],
      );
      await client.query("INSERT INTO gatework_command_dedup(actor_id,idempotency_key,command_type,result_id) VALUES($1,$2,'official_story.create',$3)", [actor.actorId, input.idempotencyKey, story.rows[0]!.id]);
      await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'official_story.publish', targetType: 'story', targetId: story.rows[0]!.id, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
      await client.query('COMMIT');
      return reply.code(201).send({ data: story.rows[0] });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  } catch (error) {
    const known = error instanceof Error ? error.message : '';
    return reply.code(known === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'GATEWORK_STORY_REJECTED', message: known === 'MEDIA_NOT_READY' ? 'Gorsel taramasi bitmeden Story yayinlanamaz.' : known === 'OFFICIAL_NOT_ACTIVE' ? 'Secilen resmi hesap aktif degil.' : 'Story yayinlanamadi.' } });
  }
});

/// Panelden acilan Story'ler ve sureleri. Story 24 saatte kendiliginden
/// dusuyor, bu yuzden liste "yayinda olanlar" degil "hala yayinda olanlar":
/// bir editorun ekledigi Story'nin ne kadar omru kaldigini baska yerden
/// gorebilecegi bir ekran yok.
app.get('/v1/internal/gatework/stories', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor', 'moderator', 'auditor']);
    const rows = await db.query<{ id: string; author_id: string; author_name: string; created_at: Date; expires_at: Date; safe_url: string | null; thumbnail_url: string | null; view_count: string; like_count: string }>(
      `SELECT s.id,s.author_id,COALESCE(p.display_name,'TurkSquare') author_name,s.created_at,s.expires_at,m.safe_url,m.thumbnail_url,
              (SELECT count(*) FROM story_views v WHERE v.story_id=s.id) view_count,
              (SELECT count(*) FROM story_likes l WHERE l.story_id=s.id) like_count
         FROM stories s
         JOIN media_assets m ON m.id=s.media_id
         JOIN community_system_accounts o ON o.user_id=s.author_id AND o.role='official'
         LEFT JOIN community_profile_projection p ON p.user_id=s.author_id
        WHERE s.expires_at>now()
        ORDER BY s.created_at DESC LIMIT 50`,
    );
    return {
      data: await Promise.all(rows.rows.map(async (row) => ({
        id: row.id,
        authorId: row.author_id,
        authorName: row.author_name,
        createdAt: row.created_at.toISOString(),
        expiresAt: row.expires_at.toISOString(),
        imageUrl: row.thumbnail_url ? await mediaObjectUrl(row.thumbnail_url) : row.safe_url ? await mediaObjectUrl(row.safe_url) : null,
        viewCount: Number(row.view_count),
        likeCount: Number(row.like_count),
      }))),
    };
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'GATEWORK_STORIES_UNAVAILABLE', message: 'Panelden acilan Storyler okunamadi.' } });
  }
});

/// Geri cekme. Satir silinmiyor, suresi simdiye cekiliyor: goruntulenmeler ve
/// begeniler o Story'ye bagli duruyor ve bir sikayet acilmissa hedefi hala
/// cozulebilir olmali.
app.delete('/v1/internal/gatework/stories/:id', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = z.object({ reason: z.string().trim().min(5).max(500) }).parse(request.body);
    const removed = await db.query("UPDATE stories SET expires_at=now() WHERE id=$1 AND expires_at>now() AND EXISTS(SELECT 1 FROM community_system_accounts o WHERE o.user_id=stories.author_id AND o.role='official') RETURNING id", [id]);
    if (!removed.rows[0]) return reply.code(404).send({ error: { code: 'STORY_NOT_FOUND', message: 'Yayinda olan bir panel Storysi bulunamadi.' } });
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'official_story.retract', targetType: 'story', targetId: id, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    return reply.code(204).send();
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'GATEWORK_STORY_RETRACT_FAILED', message: 'Story geri cekilemedi.' } });
  }
});

/* --- Medya yükleme akışı ---------------------------------------------------
 *
 * İstemci yalnızca beyan ettiği görseli, özel bir karantina ön ekine
 * yükleyebilir. Okunabilir nesneyi bu bağlantı değil, taramadan ve EXIF
 * temizliğinden sonra medya işleyici üretir.
 *
 * Üç adım da iki ayrı yerden kullanılıyor: üyenin kendi yüklemesi ve panelin
 * resmî hesap adına yüklediği haber görseli. Aradaki tek fark dosyanın kimin
 * adına yazıldığı - onu söyleyen taraf rotalar, ne yapıldığını söyleyen taraf
 * bu üç işlev. İkinci bir kopya çıkarmak, güvenlik kontrolü olan bir akışı iki
 * yerde ayrı ayrı doğru tutmayı gerektirirdi.
 */
async function openMediaUpload(ownerId: string, input: z.infer<typeof mediaPresignBody>) {
  const mediaId = randomUUID();
  const uploadId = randomUUID();
  const quarantineKey = `uploads/quarantine/${ownerId}/${mediaId}`;
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      "INSERT INTO media_assets(id,owner_id,status,kind) VALUES($1,$2,'quarantined',$3)",
      [mediaId, ownerId, input.kind],
    );
    await client.query(
      "INSERT INTO media_upload_sessions(id,media_id,owner_id,quarantine_key,expected_sha256,expected_size_bytes,content_type,expires_at) VALUES($1,$2,$3,$4,$5,$6,$7,now()+interval '5 minutes')",
      [uploadId, mediaId, ownerId, quarantineKey, Buffer.from(input.sha256, 'hex'), input.sizeBytes, input.contentType],
    );
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
  return {
    uploadId,
    mediaId,
    uploadUrl: await generateMediaUploadSasUrl(quarantineKey, 300),
    expiresInSeconds: 300,
    // İstemci bu başlıkları olduğu gibi gönderiyor, içeriklerini yorumlamıyor.
    // Burada eskiden `x-amz-checksum-sha256` yazıyordu: S3 döneminden kalan,
    // Azure'un tanımadığı bir başlık. Asıl sorun eksik olandı - Azure'a
    // doğrudan PUT ile blob yazarken `x-ms-blob-type` zorunlu, yoksa depolama
    // isteği daha gövdeye bakmadan MissingRequiredHeader ile reddediyor.
    // Yükleme adımı bu yüzden hiç tutmadı ve hiçbir medya taramaya bile
    // ulaşamadı.
    //
    // İçerik türü hem istek başlığı hem de `x-ms-blob-content-type` olarak
    // gidiyor: ikincisi blobun kalıcı türünü açıkça yazar, tamamlama adımı o
    // türü beyan edilenle karşılaştırır.
    requiredHeaders: {
      'x-ms-blob-type': 'BlockBlob',
      'content-type': input.contentType,
      'x-ms-blob-content-type': input.contentType,
    },
  };
}

type MediaCompletion =
  | { ok: true; mediaId: string }
  | { ok: false; httpStatus: number; code: string; message: string };

async function completeMediaUpload(ownerId: string, uploadId: string): Promise<MediaCompletion> {
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const session = await client.query<{
      media_id: string; quarantine_key: string; expected_size_bytes: string; content_type: string; expires_at: Date; completed_at: Date | null;
    }>(
      'SELECT media_id,quarantine_key,expected_size_bytes,content_type,expires_at,completed_at FROM media_upload_sessions WHERE id=$1 AND owner_id=$2 FOR UPDATE',
      [uploadId, ownerId],
    );
    const row = session.rows[0];
    if (!row || row.expires_at <= new Date()) {
      await client.query('ROLLBACK');
      return { ok: false, httpStatus: 410, code: 'UPLOAD_EXPIRED', message: 'Yükleme süresi doldu.' };
    }
    if (row.completed_at) {
      await client.query('COMMIT');
      return { ok: true, mediaId: row.media_id };
    }
    // Blobun kendi özellikleri, beyan edilen boyut ve türle karşılaştırılıyor.
    // Buraya üçüncü bir koşul olarak SHA-256 karşılaştırması da yazılmıştı ama
    // karşıya konan değer Azure'un MD5'iydi; hiçbir koşulda tutmayan bir koşul
    // olduğu için sağlam gelen dosyalar da reddediliyordu. Özet doğrulaması
    // artık medya işleyicide, indirilen baytların üzerinde yapılıyor - taramayı
    // yapan taraf, güvenli nesneyi üretmeden önce baytların beyan edilenle aynı
    // olduğunu görmüş oluyor.
    const head = await headMediaBlob(row.quarantine_key);
    if (head.contentLength !== Number(row.expected_size_bytes) || head.contentType !== row.content_type) {
      await client.query('ROLLBACK');
      return { ok: false, httpStatus: 400, code: 'UPLOAD_VALIDATION_FAILED', message: 'Yüklenen dosya doğrulanamadı.' };
    }
    await client.query('UPDATE media_upload_sessions SET completed_at=now() WHERE id=$1 AND completed_at IS NULL', [uploadId]);
    await client.query("UPDATE media_assets SET status='scanning' WHERE id=$1 AND owner_id=$2 AND status='quarantined'", [row.media_id, ownerId]);
    await client.query("INSERT INTO media_processing_jobs(media_id,job_type,status) VALUES($1,'scan','queued') ON CONFLICT DO NOTHING", [row.media_id]);
    await client.query('COMMIT');
    return { ok: true, mediaId: row.media_id };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

// Medya kimliği bir paylaşım aracı değil. Sahibi tarama sürerken durumu
// sorabilir; başka herkes medyayı, zaten yetkisi olan bir Topluluk nesnesi
// üzerinden alır - görünür bir Story gibi.
async function readMediaAsset(ownerId: string, mediaId: string) {
  const media = await db.query<{
    id: string;
    status: 'quarantined' | 'scanning' | 'ready' | 'rejected';
    kind: 'image' | 'video';
    safe_url: string | null;
    thumbnail_url: string | null;
  }>(
    'SELECT id,status,kind,safe_url,thumbnail_url FROM media_assets WHERE id=$1 AND owner_id=$2',
    [mediaId, ownerId],
  );
  const row = media.rows[0];
  if (!row) return null;
  return {
    id: row.id,
    status: row.status,
    kind: row.kind,
    url: row.status === 'ready' && row.safe_url ? await mediaObjectUrl(row.safe_url) : null,
    thumbnailUrl: row.status === 'ready' && row.thumbnail_url ? await mediaObjectUrl(row.thumbnail_url) : null,
  };
}

app.post('/v1/media/uploads/presign', { config: { rateLimit: { max: 12, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const input = mediaPresignBody.parse(request.body);
    return reply.code(201).send({ data: await openMediaUpload(userId, input) });
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
    const result = await completeMediaUpload(userId, uploadId);
    if (!result.ok) return reply.code(result.httpStatus).send({ error: { code: result.code, message: result.message } });
    return reply.code(202).send({ data: { mediaId: result.mediaId, status: 'scanning' } });
  } catch (error) {
    return reply.code((error as { statusCode?: number }).statusCode ?? 400).send({
      error: { code: 'MEDIA_COMPLETE_FAILED', message: 'Medya doğrulama kuyruğa alınamadı.' },
    });
  }
});

app.get('/v1/media/:id', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const mediaId = z.string().uuid().parse((request.params as { id: string }).id);
    const data = await readMediaAsset(userId, mediaId);
    if (!data) return reply.code(404).send({ error: { code: 'MEDIA_NOT_FOUND', message: 'Medya bulunamadı.' } });
    return { data };
  } catch (error) {
    return reply.code((error as { statusCode?: number }).statusCode ?? 400).send({
      error: { code: 'MEDIA_STATUS_FAILED', message: 'Medya durumu okunamadı.' },
    });
  }
});

/* --- Panelin resmî hesap adına yüklediği görsel -----------------------------
 *
 * Haber görseli için panelde yükleme yoktu; alanın adı "görsel medya kimliği"
 * idi ve ipucu "medya kimliği medya hattından gelir" diyordu. Böyle bir hat
 * yoktu: kimliği elle üretebilecek tek yol uygulamadan bir görsel yükleyip
 * kimliğini kopyalamaktı, o da resmî hesabın değil o üyenin medyası olurdu -
 * haber yayınlarken `MEDIA_NOT_READY` ile geri dönerdi.
 *
 * Aynı üç adım, aynı tarama, aynı işleyici; değişen tek şey dosyanın kimin
 * adına yazıldığı. Sahip, haberi yayınlayacak resmî hesabın kendisi: haber
 * yayınlanırken medyanın hazır olup olmadığına bakan sorgu da, medyayı
 * sonradan okuyan sorgu da o hesabı görüyor.
 */
const gateworkMediaPresignBody = mediaPresignBody.extend({ ownerId: z.string().uuid() });
const gateworkMediaCompleteBody = mediaCompleteBody.extend({ ownerId: z.string().uuid() });

async function requireOfficialOwner(ownerId: string) {
  const account = await db.query(
    "SELECT 1 FROM community_system_accounts WHERE user_id=$1 AND role='official' AND active",
    [ownerId],
  );
  if (!account.rows[0]) throw Error('OFFICIAL_NOT_ACTIVE');
}

app.post('/v1/internal/gatework/media/uploads/presign', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const { ownerId, ...input } = gateworkMediaPresignBody.parse(request.body);
    await requireOfficialOwner(ownerId);
    return reply.code(201).send({ data: await openMediaUpload(ownerId, input) });
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 400).send({
      error: { code: 'GATEWORK_MEDIA_NOT_ACCEPTED', message: 'Görsel yükleme isteği kabul edilemedi.' },
    });
  }
});

app.post('/v1/internal/gatework/media/uploads/complete', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const { ownerId, uploadId } = gateworkMediaCompleteBody.parse(request.body);
    const result = await completeMediaUpload(ownerId, uploadId);
    if (!result.ok) return reply.code(result.httpStatus).send({ error: { code: result.code, message: result.message } });
    return reply.code(202).send({ data: { mediaId: result.mediaId, status: 'scanning' } });
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 400).send({
      error: { code: 'GATEWORK_MEDIA_COMPLETE_FAILED', message: 'Görsel doğrulama kuyruğa alınamadı.' },
    });
  }
});

app.get('/v1/internal/gatework/media/:id', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const mediaId = z.string().uuid().parse((request.params as { id: string }).id);
    const ownerId = z.string().uuid().parse((request.query as { ownerId?: string }).ownerId);
    const data = await readMediaAsset(ownerId, mediaId);
    if (!data) return reply.code(404).send({ error: { code: 'MEDIA_NOT_FOUND', message: 'Görsel bulunamadı.' } });
    return { data };
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 400).send({
      error: { code: 'GATEWORK_MEDIA_STATUS_FAILED', message: 'Görselin durumu okunamadı.' },
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
      // Haber kartları bu sayının dışında: "çevrendeki 12 paylaşım" cümlesi
      // insanları sayıyor, bültenin kendi haberlerini değil.
      db.query<{ count: string }>(`SELECT count(*) FROM community_posts p JOIN community_profile_projection v ON v.user_id=$1 WHERE p.deleted_at IS NULL AND p.archived_at IS NULL AND p.moderation_state='active' AND p.news_article_id IS NULL AND p.region_code=v.region_code`, [userId]),
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

/**
 * What the composer sends and the feed never sent back.
 *
 * A post could carry photos and a poll since 001, and both were being written:
 * `post_media_refs` had no INSERT anywhere in this file, and `post_polls` was
 * inserted on create and read by nothing. So a member attached two photos and a
 * four-option poll, published, and got a paragraph of text - the photos landed
 * in the media service and were never referenced, the poll existed but had no
 * options on screen to tap, which also made the vote route unreachable.
 *
 * Media travels as an id resolved to a signed URL on the way out, never as a
 * stored URL, and only `ready` assets are joined: an image still being scanned
 * is not part of the post yet.
 */
const FEED_MEDIA = `(SELECT json_agg(json_build_object('id',m.id,'kind',m.kind,'safeUrl',m.safe_url,'thumbnailUrl',m.thumbnail_url) ORDER BY r.ordinal) FROM post_media_refs r JOIN media_assets m ON m.id=r.media_id WHERE r.post_id=p.id AND m.status='ready') media`;

const feedPoll = (viewerParam: string) => `(SELECT json_build_object(
  'id',pp.post_id,'selectionMode',pp.selection_mode,'closesAt',pp.closes_at,
  'options',(SELECT json_agg(json_build_object(
      'id',o.id,'label',o.label,
      'votes',(SELECT count(*) FROM post_poll_votes v WHERE v.option_id=o.id),
      'selected',EXISTS(SELECT 1 FROM post_poll_votes v WHERE v.option_id=o.id AND v.voter_id=${viewerParam})
    ) ORDER BY o.ordinal) FROM post_poll_options o WHERE o.post_id=pp.post_id)
 ) FROM post_polls pp WHERE pp.post_id=p.id) poll`;

type FeedMediaRow = { id: string; kind: 'image' | 'video'; safeUrl: string | null; thumbnailUrl: string | null };
type FeedPollRow = { id: string; selectionMode: string; closesAt: string | null; options: Array<{ id: string; label: string; votes: string | number; selected: boolean }> | null };
type FeedTravelerRow = { from: string; to: string; travelAt: string; packageDetails: string; note: string | null };
type FeedNewsRow = { id: string; title: string; category: string };
type FeedRow = { id: string; created_at: Date; body: string; location_label: string | null; author_id: string; author_name: string; likes: string; comments: string; is_liked: boolean; media: FeedMediaRow[] | null; poll: FeedPollRow | null; purpose: string; is_author: boolean; traveler: FeedTravelerRow | null; news: FeedNewsRow | null };

// The trip travels as one object rather than five columns so that "no trip" is
// a single null instead of five of them.
const FEED_TRAVELER = `(SELECT json_build_object('from',t.from_place,'to',t.to_place,'travelAt',t.travel_at,'packageDetails',t.package_details,'note',t.note) FROM post_traveler_details t WHERE t.post_id=p.id) traveler`;

const FEED_PURPOSE: Record<string, string> = { imece_help: 'imeceHelp', traveler_match: 'travelerMatch' };

/* --- Haber Bülteni ---------------------------------------------------------
 *
 * Yayınlanan bir haber, editör isterse akışta da bir kart oluyor (036). O kartın
 * kendi beğeni ve yorum sayacı yok: ikisini de haberin kendi tablolarından
 * okuyor, çünkü "akıştaki paylaşımla haber aynı şey" demek ancak tek bir sayı
 * varsa doğru olur. Aynı sebeple kart, haberin görünürlüğüne bağlı - geri
 * çekilen haber akıştan da düşer, ileri tarihli olan akışta erken çıkmaz.
 */
const NEWS_POST_LIVE = `EXISTS(SELECT 1 FROM news_articles na WHERE na.id=p.news_article_id AND na.deleted_at IS NULL AND na.published_at IS NOT NULL AND na.published_at<=now())`;
const FEED_NEWS_VISIBLE = `(p.news_article_id IS NULL OR ${NEWS_POST_LIVE})`;

/// Yazarin hesabi acik mi.
///
/// Hesabini donduran ya da silmek isteyen uyenin paylasimlari akista durmaya
/// devam ediyordu: Identity oturumu kesiyor, Community ise bunu hic duymuyordu.
/// Paylasimlar silinmiyor - dondurma geri alinabilir bir karar ve geri donen
/// uye kendi gecmisini bulmali - yalnizca baskalarina gorunmuyor.
/// Uyenin kendi paylasimi bu kuralin disinda: silmeden once ne yazdigini
/// gormesi gerekebilir.
const AUTHOR_ACCOUNT_OPEN = (viewerParam: string) =>
  `(p.author_id=${viewerParam} OR NOT EXISTS(SELECT 1 FROM community_profile_projection ap WHERE ap.user_id=p.author_id AND ap.closed_at IS NOT NULL))`;

const FEED_NEWS = `(SELECT json_build_object('id',na.id,'title',na.title,'category',na.category) FROM news_articles na WHERE na.id=p.news_article_id) news`;

/// The feed's columns and the feed's JSON, named so that a single post can be
/// read with exactly the shape the feed hands back. A card fetched from a
/// notification that differed from the same card in the list - one with a poll,
/// one without - would be a second definition of what a post is.
const feedColumns = (viewerParam: string) => `p.id,p.created_at,p.body,p.location_label,p.author_id,COALESCE(cp.display_name,'TurkSquare üyesi') author_name,CASE WHEN p.news_article_id IS NULL THEN (SELECT count(*) FROM post_reactions x WHERE x.post_id=p.id AND x.kind='like') ELSE (SELECT count(*) FROM news_reactions r WHERE r.article_id=p.news_article_id AND r.value='like') END likes,CASE WHEN p.news_article_id IS NULL THEN (SELECT count(*) FROM community_comments c WHERE c.post_id=p.id AND c.deleted_at IS NULL AND c.moderation_state='active') ELSE (SELECT count(*) FROM news_comments c WHERE c.article_id=p.news_article_id AND c.deleted_at IS NULL AND c.moderation_state='active') END comments,CASE WHEN p.news_article_id IS NULL THEN EXISTS(SELECT 1 FROM post_reactions x WHERE x.post_id=p.id AND x.actor_id=${viewerParam} AND x.kind='like') ELSE EXISTS(SELECT 1 FROM news_reactions r WHERE r.article_id=p.news_article_id AND r.user_id=${viewerParam} AND r.value='like') END is_liked,p.purpose,(p.author_id=${viewerParam} AND p.news_article_id IS NULL) is_author,${FEED_TRAVELER},${FEED_MEDIA},${feedPoll(viewerParam)},${FEED_NEWS}`;

/// Haberin akıştaki imzası. Yayınlayan resmî hesabın adı değil, tek bir isim:
/// haberi yazan kişi değil bülten paylaşıyor. Profil de açılmıyor - kart bir
/// üyeye değil habere götürüyor, uygulama bunu `news` alanının doluluğundan
/// anlıyor.
const NEWS_BYLINE = 'Haber Bülteni';

const feedPostJson = async (p: FeedRow) => ({
  id: p.id,
  authorId: p.author_id,
  authorName: p.news ? NEWS_BYLINE : p.author_name,
  location: p.location_label ?? '',
  createdAtLabel: p.created_at.toISOString(),
  message: p.body,
  likes: Number(p.likes),
  comments: Number(p.comments),
  isLiked: p.is_liked,
  isAuthor: p.is_author,
  purpose: FEED_PURPOSE[p.purpose] ?? 'standard',
  travelerMatch: p.traveler ? { ...p.traveler, travelAt: new Date(p.traveler.travelAt).toISOString() } : null,
  media: await feedMediaJson(p.media),
  poll: feedPollJson(p.poll),
  news: p.news,
});

const feedMediaJson = async (media: FeedMediaRow[] | null) => Promise.all(
  (media ?? []).filter((item) => item.safeUrl).map(async (item) => ({
    id: item.id,
    type: item.kind,
    url: await mediaObjectUrl(item.safeUrl!),
    thumbnailUrl: item.thumbnailUrl ? await mediaObjectUrl(item.thumbnailUrl) : null,
  })),
);

const feedPollJson = (poll: FeedPollRow | null) => poll && poll.options?.length
  ? {
      id: poll.id,
      selectionMode: poll.selectionMode,
      closesAt: poll.closesAt,
      options: poll.options.map((option) => ({ id: option.id, label: option.label, votes: Number(option.votes), selected: option.selected })),
    }
  : null;

app.get('/v1/community/feed', async (request, reply) => {
  try {
    const userId = await viewer(request.headers); const input = feedQuery.parse(request.query); const cursor = decodeCursor(input.cursor);
    const params: unknown[] = [userId]; let where = `p.deleted_at IS NULL AND p.archived_at IS NULL AND p.moderation_state='active' AND ${FEED_NEWS_VISIBLE} AND ${AUTHOR_ACCOUNT_OPEN('$1')} AND (p.visibility='public' OR EXISTS (SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=p.author_id AND r.relationship='friend' AND r.active))`;
    if (input.mode === 'following') where += ` AND EXISTS (SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=p.author_id AND r.active)`;
    // "Nearby" is the chosen state, not a radius. The original predicate asked
    // for posts within 50km of viewer_location_projection.approximate_cell, and
    // nothing has ever written either that projection or community_posts
    // .location_cell - so the tab was empty for everybody, always. Rewriting it
    // in terms of coordinates would have meant tracking members to fill the
    // gap; locality here is what a member chose to publish (migration 008), so
    // that is what the tab means. A post carries its own region when the
    // composer sent one, and otherwise inherits the author's chosen state.
    if (input.mode === 'nearby') where += ` AND viewer_profile.region_code IS NOT NULL AND COALESCE(p.region_code,cp.region_code)=viewer_profile.region_code`;
    if (cursor) { params.push(cursor.createdAt, cursor.id); where += ` AND (p.created_at,p.id) < ($${params.length - 1}::timestamptz,$${params.length}::uuid)`; }
    params.push(input.limit + 1);
    // Sıra tam olarak yeniden eskiye. Burada bir zamanlar puan vardı: üyenin
    // eyaletinden gelen paylaşım 1800, ortak ilgi alanı olan yazarınki 600
    // saniye ileri alınıyordu. İki sonucu oldu. Akış kronolojik olmaktan
    // çıkıyordu - üstteki kart alttakinden eski olabiliyordu ve okuyan kişi
    // bunu sıralamanın bozukluğu olarak görüyordu. İkincisi daha kötüsü:
    // imleç `(created_at,id)` karşılaştırmasıyla ilerliyor, sıralama ise
    // puana bakıyordu. Sayfanın son kartı 30 dakika ileri taşınmış bir
    // paylaşımsa, sonraki sayfa onun gerçek saatinden geriye soruyor ve
    // aradaki paylaşımlar hiç görünmüyordu. Kime yakın olduğu artık sekmenin
    // işi: "Yakınındakiler" eyalete, "Takip ettiklerin" ilişkiye bakıyor.
    const result = await db.query<FeedRow>(`SELECT ${feedColumns('$1')} FROM community_posts p LEFT JOIN community_profile_projection cp ON cp.user_id=p.author_id LEFT JOIN community_profile_projection viewer_profile ON viewer_profile.user_id=$1 WHERE ${where} ORDER BY p.created_at DESC,p.id DESC LIMIT $${params.length}`, params);
    const page = result.rows.slice(0, input.limit); const next = result.rows.length > input.limit ? encodeCursor(page[page.length - 1]!) : null;
    // authorId travels with the card. Without it the app had nothing to compare
    // the viewer against, so it fell back to a hardcoded 'local-user' and every
    // post in production looked like it belonged to somebody else - which is
    // why the delete button on your own post never appeared, and why a post
    // owner could not moderate the comments under it.
    return { data: await Promise.all(page.map(feedPostJson)), meta: { nextCursor: next } };
  } catch (error) { const status = readFailureStatus(error); if (status >= 500) request.log.error({ err: error }, 'feed read failed'); return reply.code(status).send({ error: { code: 'FEED_UNAVAILABLE', message: 'Akış yüklenemedi.' } }); }
});

app.put('/v1/community/posts/:id/reactions/:kind', async (request, reply) => {
  try { const userId = await viewer(request.headers); const postId = z.string().uuid().parse((request.params as { id: string }).id); const kind = z.enum(['like','save']).parse((request.params as { kind: string }).kind); const input = interactionBody.parse(request.body);
    // Akıştaki haber kartının kalbi haberin kendi tablosuna yazılıyor (036).
    // İki tabloya birden yazmak, iki farklı doğru üretirdi: haber ekranında 12,
    // akışta 3. "Kaydet" bunun dışında - o kişisel bir yer imi, haberin sayacı
    // değil, dolayısıyla eskisi gibi `post_reactions` içinde kalıyor.
    const linked = await db.query<{ news_article_id: string | null }>('SELECT news_article_id FROM community_posts WHERE id=$1 AND deleted_at IS NULL', [postId]);
    const articleId = linked.rows[0]?.news_article_id ?? null;
    if (articleId && kind === 'like') {
      if (input.enabled) {
        await db.query(
          `INSERT INTO news_reactions(article_id,user_id,value) SELECT a.id,$2,'like' FROM news_articles a WHERE a.id=$1 AND a.deleted_at IS NULL
           ON CONFLICT(article_id,user_id) DO UPDATE SET value='like',created_at=now()`,
          [articleId, userId],
        );
      } else {
        // Yalnızca beğeni siliniyor: aynı satır haber ekranında "beğenmedim"
        // olarak işaretlenmiş olabilir ve akıştaki kalbin sönmesi onu silmemeli.
        await db.query("DELETE FROM news_reactions WHERE article_id=$1 AND user_id=$2 AND value='like'", [articleId, userId]);
      }
      return reply.code(204).send();
    }
    if (input.enabled) await db.query('INSERT INTO post_reactions(post_id,actor_id,kind) SELECT $1,$2,$3 WHERE EXISTS(SELECT 1 FROM community_posts WHERE id=$1 AND deleted_at IS NULL) ON CONFLICT DO NOTHING', [postId,userId,kind]);
    else await db.query('DELETE FROM post_reactions WHERE post_id=$1 AND actor_id=$2 AND kind=$3', [postId,userId,kind]);
    // A save is private - the member is filing the post away for themselves, not
    // telling the author anything - so only a like reaches the bell. Nothing is
    // deleted on un-liking either: the notification counts its people live, so
    // the number drops on its own and the line disappears when it hits zero.
    if (input.enabled && kind === 'like') notifyOwner('post_like', postId, userId);
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
    if (input.marketplaceListingId) { const listing = await client.query('SELECT 1 FROM marketplace_listing_projection WHERE listing_id=$1 AND owner_id=$2 AND status=\'active\'', [input.marketplaceListingId,userId]); if (!listing.rows[0]) { await client.query('ROLLBACK'); return reply.code(403).send({error:{code:'LISTING_NOT_AVAILABLE',message:'Aktif ilan bulunamadı.'}}); } }
    const kind = input.poll ? 'poll' : input.marketplaceListingId ? 'marketplace_listing' : 'standard'; const result = await client.query<{id:string}>('INSERT INTO community_posts(author_id,kind,visibility,body,location_label,region_code,marketplace_listing_id,purpose) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id',[userId,kind,input.visibility,input.body,input.locationLabel??null,input.locationRegionCode?.toUpperCase()??null,input.marketplaceListingId??null,input.purpose]); const id=result.rows[0]!.id;
    // The trip. Written inside the same transaction as the post it belongs to:
    // a "Bavulda Yer Var" post that appears without its route and date is a
    // post the member has to delete and write again.
    if (input.travelerMatch) await client.query('INSERT INTO post_traveler_details(post_id,from_place,to_place,travel_at,package_details,note) VALUES($1,$2,$3,$4,$5,$6)',[id,input.travelerMatch.from,input.travelerMatch.to,input.travelerMatch.travelAt,input.travelerMatch.packageDetails,input.travelerMatch.note??null]);
    if(input.poll){const poll=await client.query<{post_id:string}>('INSERT INTO post_polls(post_id,selection_mode,closes_at) VALUES($1,$2,$3) RETURNING post_id',[id,input.poll.selectionMode,input.poll.closesAt??null]); for(const [ordinal,label] of input.poll.options.entries()) await client.query('INSERT INTO post_poll_options(post_id,ordinal,label) VALUES($1,$2,$3)',[poll.rows[0]!.post_id,ordinal,label]);}
    // The photos. `post_media_refs` has existed since 001 and nothing had ever
    // written a row into it: the app uploaded the files, the media service
    // scanned and stored them, and then the post was created without a single
    // reference to any of them. Ownership and scan state are checked here rather
    // than trusted from the request - an id is not a permission.
    if (input.mediaIds?.length) {
      const distinct = new Set(input.mediaIds);
      const ready = await client.query<{ id: string }>("SELECT id FROM media_assets WHERE id=ANY($1::uuid[]) AND owner_id=$2 AND status='ready' FOR KEY SHARE", [input.mediaIds, userId]);
      // Every id has to be the member's own, scanned, and listed once: a repeat
      // would put the same photo on the post twice under two ordinals.
      if (ready.rows.length !== distinct.size || distinct.size !== input.mediaIds.length) {
        await client.query('ROLLBACK');
        return reply.code(400).send({ error: { code: 'MEDIA_NOT_READY', message: 'Medya hazır değil.' } });
      }
      for (const [ordinal, mediaId] of input.mediaIds.entries()) {
        await client.query('INSERT INTO post_media_refs(post_id,media_id,ordinal) VALUES($1,$2,$3)', [id, mediaId, ordinal]);
      }
    }
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
// Bir kapanmamis parantez yuzunden bu kosulu kullanan her sorgu
// `syntax error at or near "ORDER"` ile duserdi: Story listesi, Story
// goruntulenme kaydi ve Story begenisi. Uygulamada karsiligi "Story'ler su
// anda yuklenemedi" satiriydi ve bos bir Story serididi.
const storyAccessWhere = (storyAlias: string, viewerParam: string) => `(${storyAlias}.author_id=${viewerParam} OR (NOT EXISTS(SELECT 1 FROM story_audience_exclusions x WHERE x.story_id=${storyAlias}.id AND x.excluded_user_id=${viewerParam}) AND (EXISTS(SELECT 1 FROM relationship_projection r WHERE r.viewer_id=${viewerParam} AND r.subject_id=${storyAlias}.author_id AND r.active) OR EXISTS(SELECT 1 FROM community_system_accounts o WHERE o.user_id=${storyAlias}.author_id AND o.role='official' AND o.active) OR (${storyAlias}.visibility='public' AND ${storyAlias}.region_code=(SELECT region_code FROM community_profile_projection WHERE user_id=${viewerParam})))))`;
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
    const status = readFailureStatus(error);
    if (status >= 500) request.log.error({ err: error }, 'story read failed');
    return reply.code(status).send({
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
// Feed comments.
//
// The routes below have existed since 005 and nothing has ever called them: the
// app was wired to a mock repository, so every comment a member wrote lived in
// that phone's memory until the screen closed. Connecting it exposed two things
// this list never did - who wrote the comment, and whether the reader is even
// allowed to be reading it.
//
// The display name is joined here rather than left to the caller, exactly as the
// news list does it, because a comment is drawn under a name and an author id is
// not one.
const postCommentSelect = (viewerParam: string) => `
  SELECT c.id,c.author_id,c.parent_id,c.body,c.created_at,
         COALESCE(p.display_name,'TurkSquare üyesi') author_name,
         (SELECT count(*) FROM comment_reactions x WHERE x.comment_id=c.id) like_count,
         EXISTS(SELECT 1 FROM comment_reactions x WHERE x.comment_id=c.id AND x.actor_id=${viewerParam}) is_liked
    FROM community_comments c
    LEFT JOIN community_profile_projection p ON p.user_id=c.author_id`;

type PostCommentRow = { id: string; author_id: string; parent_id: string | null; body: string; created_at: Date; author_name: string; like_count: string; is_liked: boolean };
const postCommentJson = (row: PostCommentRow) => ({
  id: row.id,
  authorId: row.author_id,
  authorName: row.author_name,
  parentId: row.parent_id,
  body: row.body,
  createdAt: row.created_at.toISOString(),
  likes: Number(row.like_count),
  isLiked: row.is_liked,
});

/**
 * A comment thread is exactly as visible as the post it hangs under. Asking for
 * it by id used to be the way around that - a friends-only post answered anybody
 * who knew the uuid - so both routes now ask the question the feed asks, plus
 * the author, who can always read under their own post.
 */
const postReadableWhere = (postParam: string, viewerParam: string) =>
  `p.id=${postParam} AND p.deleted_at IS NULL AND p.moderation_state='active' AND ${FEED_NEWS_VISIBLE} AND ${AUTHOR_ACCOUNT_OPEN(viewerParam)} AND (p.visibility='public' OR p.author_id=${viewerParam} OR EXISTS(SELECT 1 FROM relationship_projection r WHERE r.viewer_id=${viewerParam} AND r.subject_id=p.author_id AND r.relationship='friend' AND r.active))`;

/**
 * One post, by id.
 *
 * Written for the bell: "Elif paylaşımına yorum yaptı" pointed at a post the
 * app had no way to fetch, so the notification opened nothing. The comment
 * thread under it has been readable by id since the beginning; the post itself
 * was not.
 *
 * Visibility is the feed's question, asked with the same predicate the comment
 * route uses - knowing the uuid is not permission to read a friends-only post.
 */
app.get('/v1/community/posts/:id', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const postId = z.string().uuid().parse((request.params as { id: string }).id);
    const rows = await db.query<FeedRow>(
      `SELECT ${feedColumns('$2')} FROM community_posts p LEFT JOIN community_profile_projection cp ON cp.user_id=p.author_id WHERE ${postReadableWhere('$1', '$2')}`,
      [postId, userId],
    );
    const post = rows.rows[0];
    if (!post) return reply.code(404).send({ error: { code: 'POST_NOT_FOUND', message: 'Paylaşım bulunamadı.' } });
    return { data: await feedPostJson(post) };
  } catch (error) {
    const status = readFailureStatus(error);
    if (status >= 500) request.log.error({ err: error }, 'post read failed');
    return reply.code(status).send({ error: { code: 'POST_UNAVAILABLE', message: 'Paylaşım yüklenemedi.' } });
  }
});

app.get('/v1/community/posts/:id/comments', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const postId = z.string().uuid().parse((request.params as { id: string }).id);
    const post = await db.query<{ news_article_id: string | null }>(`SELECT p.news_article_id FROM community_posts p WHERE ${postReadableWhere('$1', '$2')}`, [postId, userId]);
    if (!post.rows[0]) return reply.code(404).send({ error: { code: 'POST_NOT_FOUND', message: 'Paylaşım bulunamadı.' } });
    // Haber kartının altındaki başlık, haberin kendi yorum listesi (036). Aynı
    // iş parçacığı iki ekranda da okunuyor; ayrı bir liste tutulsaydı akışta
    // yazılan yorum haber ekranında görünmezdi.
    if (post.rows[0].news_article_id) {
      const newsRows = await db.query<NewsCommentRow>(
        `${newsCommentSelect('$2')} WHERE c.article_id=$1 AND c.deleted_at IS NULL AND c.moderation_state='active' ORDER BY c.created_at ASC LIMIT 100`,
        [post.rows[0].news_article_id, userId],
      );
      return { data: newsRows.rows.map(newsCommentJson) };
    }
    // Oldest first: a thread reads top to bottom, and the app appends a comment
    // it has just written to the end of the list it is already holding.
    const rows = await db.query<PostCommentRow>(
      `${postCommentSelect('$2')} WHERE c.post_id=$1 AND c.deleted_at IS NULL AND c.moderation_state='active' ORDER BY c.created_at ASC LIMIT 100`,
      [postId, userId],
    );
    return { data: rows.rows.map(postCommentJson) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'COMMENTS_FAILED', message: 'Yorumlar yüklenemedi.' } });
  }
});

app.post('/v1/community/posts/:id/comments', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const restricted = await activeRestriction(userId);
    if (restricted) return reply.code(403).send(restrictionError(restricted));
    const postId = z.string().uuid().parse((request.params as { id: string }).id);
    const input = commentBody.parse(request.body);
    const post = await db.query<{ comments_enabled: boolean; news_article_id: string | null }>(`SELECT p.comments_enabled,p.news_article_id FROM community_posts p WHERE ${postReadableWhere('$1', '$2')}`, [postId, userId]);
    if (!post.rows[0]) return reply.code(404).send({ error: { code: 'POST_NOT_FOUND', message: 'Paylaşım bulunamadı.' } });
    // Haber kartına yazılan yorum haberin altına yazılıyor. Yorumlara kapalı
    // olup olmadığına da haber karar veriyor: editör haberi kapattığında akıştan
    // yazılabilmesi, kapatma düğmesini işlevsiz bırakırdı.
    if (post.rows[0].news_article_id) {
      const articleId = post.rows[0].news_article_id;
      const article = await db.query(`SELECT 1 FROM news_articles a WHERE a.id=$1 AND ${NEWS_VISIBLE} AND a.comments_enabled`, [articleId]);
      if (!article.rows[0]) return reply.code(403).send({ error: { code: 'COMMENTS_DISABLED', message: 'Bu haber yorumlara kapalı.' } });
      const written = await db.query<{ id: string }>(
        'INSERT INTO news_comments(article_id,author_id,parent_id,body) VALUES($1,$2,$3,$4) RETURNING id',
        [articleId, userId, input.parentId ?? null, input.body],
      );
      const newsRow = await db.query<NewsCommentRow>(`${newsCommentSelect('$2')} WHERE c.id=$1`, [written.rows[0]!.id, userId]);
      // Haber ekranındaki yorumla aynı ödül: seri devam eder, `vocalist` akışta
      // yazılan yorumları sayar ve haber yorumu onu ilerletmez.
      void grantInBackground('news_comment', async (journey) => { await touchStreak(journey, userId); });
      return reply.code(201).send({ data: newsCommentJson(newsRow.rows[0]!) });
    }
    if (!post.rows[0].comments_enabled) {
      return reply.code(403).send({ error: { code: 'COMMENTS_DISABLED', message: 'Yorumlar kapalı.' } });
    }
    const inserted = await db.query<{ id: string }>(
      'INSERT INTO community_comments(post_id,author_id,parent_id,body) VALUES($1,$2,$3,$4) RETURNING id',
      [postId, userId, input.parentId ?? null, input.body],
    );
    const row = await db.query<PostCommentRow>(`${postCommentSelect('$2')} WHERE c.id=$1`, [inserted.rows[0]!.id, userId]);
    notifyOwner('post_comment', postId, userId);
    // Ses Ver: the first comment. Everything else about commenting is counted
    // elsewhere; this is the one badge the act itself earns.
    void grantInBackground('comment', async (journey) => { await touchStreak(journey, userId); await awardBadge(journey, userId, 'vocalist'); });
    return reply.code(201).send({ data: postCommentJson(row.rows[0]!) });
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'COMMENT_CREATE_FAILED', message: 'Yorum gönderilemedi.' } });
  }
});
app.delete('/v1/community/comments/:id', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    // Two people can take a comment down: whoever wrote it, and whoever owns the
    // post it is sitting under. The app has always offered the post owner that
    // button; the server used to accept the request, change nothing and answer
    // 204, so the comment came back on the next open.
    const removed = await db.query(
      `UPDATE community_comments c SET deleted_at=now(),moderation_state='removed'
        WHERE c.id=$1 AND c.deleted_at IS NULL
          AND (c.author_id=$2 OR EXISTS(SELECT 1 FROM community_posts p WHERE p.id=c.post_id AND p.author_id=$2))
        RETURNING c.id`,
      [id, userId],
    );
    if (!removed.rows[0]) {
      // Akıştaki haber kartının yorumları başka bir tabloda duruyor (036), ama
      // uygulamaya aynı listeden geliyor. Kimliği burada bulunamayan bir yorumu
      // "yok" saymak, üyenin akıştan yazdığı yorumu silememesi demekti.
      const newsRemoved = await db.query(
        "UPDATE news_comments SET deleted_at=now(),moderation_state='removed' WHERE id=$1 AND author_id=$2 AND deleted_at IS NULL RETURNING id",
        [id, userId],
      );
      if (!newsRemoved.rows[0]) return reply.code(404).send({ error: { code: 'COMMENT_NOT_FOUND', message: 'Yorum bulunamadı.' } });
    }
    return reply.code(204).send();
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'COMMENT_DELETE_FAILED', message: 'Yorum silinemedi.' } });
  }
});

/**
 * The heart under a comment.
 *
 * No idempotency key, unlike the post and story equivalents: this endpoint
 * states the desired end state rather than applying a delta, so the same request
 * twice leaves the same single row. `enabled` is what the reader's finger is
 * saying, not "add one".
 */
const commentLikeBody = z.object({ enabled: z.boolean() });

app.put('/v1/community/comments/:id/likes', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const restricted = await activeRestriction(userId);
    if (restricted) return reply.code(403).send(restrictionError(restricted));
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = commentLikeBody.parse(request.body);
    // Liking something is a claim to have read it, so it asks the same
    // visibility question the list does - about the post the comment hangs under.
    const readable = await db.query(
      `SELECT 1 FROM community_comments c JOIN community_posts p ON ${postReadableWhere('c.post_id', '$2')}
        WHERE c.id=$1 AND c.deleted_at IS NULL AND c.moderation_state='active'`,
      [id, userId],
    );
    if (!readable.rows[0]) {
      // Aynı liste, başka tablo: haber kartının altındaki yorumlar (036). Kalp
      // haberin tarafına yazılmazsa akıştan beğenilen yorum haber ekranında
      // beğenilmemiş görünür.
      const newsComment = await db.query(
        `SELECT 1 FROM news_comments c JOIN news_articles a ON a.id=c.article_id
          WHERE c.id=$1 AND c.deleted_at IS NULL AND c.moderation_state='active' AND ${NEWS_VISIBLE}`,
        [id],
      );
      if (!newsComment.rows[0]) return reply.code(404).send({ error: { code: 'COMMENT_NOT_FOUND', message: 'Yorum bulunamadı.' } });
      if (input.enabled) await db.query('INSERT INTO news_comment_reactions(comment_id,actor_id) VALUES($1,$2) ON CONFLICT DO NOTHING', [id, userId]);
      else await db.query('DELETE FROM news_comment_reactions WHERE comment_id=$1 AND actor_id=$2', [id, userId]);
      const newsTally = await db.query<{ like_count: string }>('SELECT count(*) like_count FROM news_comment_reactions WHERE comment_id=$1', [id]);
      return { data: { likes: Number(newsTally.rows[0]!.like_count), isLiked: input.enabled } };
    }
    if (input.enabled) await db.query('INSERT INTO comment_reactions(comment_id,actor_id) VALUES($1,$2) ON CONFLICT DO NOTHING', [id, userId]);
    else await db.query('DELETE FROM comment_reactions WHERE comment_id=$1 AND actor_id=$2', [id, userId]);
    const tally = await db.query<{ like_count: string }>('SELECT count(*) like_count FROM comment_reactions WHERE comment_id=$1', [id]);
    return { data: { likes: Number(tally.rows[0]!.like_count), isLiked: input.enabled } };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'COMMENT_LIKE_FAILED', message: 'Beğenin kaydedilemedi.' } });
  }
});

/**
 * "Eşleşme isteği gönder" / "Destek teklif et".
 *
 * The sheet has always closed with "İsteğin gönderildi." and the request has
 * always gone into a list in the sender's own process: the mock repository was
 * wired on both sides of the mock flag, so the owner was never told and had
 * nowhere to look. These three routes are the other end of that sheet.
 *
 * The kind is derived from the post's own purpose and never read from the
 * request body. A member cannot decide that somebody else's help post is a
 * suitcase; the post already said what it is.
 */
const specialRequestBody = z.object({ message: z.string().trim().min(1).max(500) });
const specialRequestStatusBody = z.object({ status: z.enum(['accepted', 'declined', 'cancelled']) });
const SPECIAL_REQUEST_KINDS: Record<string, string> = { imece_help: 'imece_offer', traveler_match: 'traveler_match' };

type SpecialRequestRow = { id: string; post_id: string; sender_id: string; sender_name: string; kind: string; message: string; status: string; created_at: Date };
const specialRequestColumns = `r.id,r.post_id,r.sender_id,r.kind,r.message,r.status,r.created_at,
  COALESCE(cp.display_name,'TurkSquare üyesi') sender_name`;
const specialRequestSender = 'LEFT JOIN community_profile_projection cp ON cp.user_id=r.sender_id';
const specialRequestSelect = `SELECT ${specialRequestColumns} FROM post_special_requests r ${specialRequestSender}`;
const specialRequestJson = (row: SpecialRequestRow) => ({
  id: row.id,
  postId: row.post_id,
  senderId: row.sender_id,
  senderName: row.sender_name,
  type: row.kind === 'imece_offer' ? 'imeceOffer' : 'travelerMatch',
  message: row.message,
  status: row.status,
  createdAt: row.created_at.toISOString(),
});

app.post('/v1/community/posts/:id/requests', { config: { rateLimit: { max: 10, timeWindow: '1 hour' } } }, async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const restricted = await activeRestriction(userId);
    if (restricted) return reply.code(403).send(restrictionError(restricted));
    const postId = z.string().uuid().parse((request.params as { id: string }).id);
    const input = specialRequestBody.parse(request.body);
    const post = await db.query<{ purpose: string; author_id: string }>(
      `SELECT p.purpose,p.author_id FROM community_posts p WHERE ${postReadableWhere('$1', '$2')}`,
      [postId, userId],
    );
    const found = post.rows[0];
    if (!found) return reply.code(404).send({ error: { code: 'POST_NOT_FOUND', message: 'Paylaşım bulunamadı.' } });
    // Nothing to ask for on a plain post, and nothing to ask yourself.
    const kind = SPECIAL_REQUEST_KINDS[found.purpose];
    if (!kind) return reply.code(409).send({ error: { code: 'POST_NOT_REQUESTABLE', message: 'Bu paylaşıma istek gönderilemez.' } });
    if (found.author_id === userId) return reply.code(409).send({ error: { code: 'OWN_POST', message: 'Kendi paylaşımına istek gönderemezsin.' } });
    // A pending request can be rewritten; an answered one cannot. Re-asking
    // after a no is the thing the owner should never have to decline twice, so
    // the UPDATE simply matches no row and the request is refused.
    const saved = await db.query<SpecialRequestRow>(
      // The row comes back out of the CTE itself rather than being read again
      // from the table: a statement sees the snapshot it started with, so a
      // second SELECT here would not find the row this INSERT just wrote.
      `WITH upserted AS (
         INSERT INTO post_special_requests(post_id,sender_id,kind,message) VALUES($1,$2,$3,$4)
         ON CONFLICT (post_id,sender_id) DO UPDATE SET message=EXCLUDED.message,updated_at=now()
           WHERE post_special_requests.status='pending'
         RETURNING id,post_id,sender_id,kind,message,status,created_at
       )
       SELECT ${specialRequestColumns} FROM upserted r ${specialRequestSender}`,
      [postId, userId, kind, input.message],
    );
    const row = saved.rows[0];
    if (!row) return reply.code(409).send({ error: { code: 'REQUEST_ALREADY_ANSWERED', message: 'Bu paylaşıma zaten istek gönderdin.' } });
    notifyOwner('special_request', postId, userId);
    return reply.code(201).send({ data: specialRequestJson(row) });
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'REQUEST_CREATE_FAILED', message: 'İstek gönderilemedi.' } });
  }
});

/// The owner reads every request on their post. Anybody else reads only the one
/// they sent themselves: how many people offered to carry a parcel is the
/// owner's business, not the queue's.
app.get('/v1/community/posts/:id/requests', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const postId = z.string().uuid().parse((request.params as { id: string }).id);
    const post = await db.query(`SELECT 1 FROM community_posts p WHERE ${postReadableWhere('$1', '$2')}`, [postId, userId]);
    if (!post.rows[0]) return reply.code(404).send({ error: { code: 'POST_NOT_FOUND', message: 'Paylaşım bulunamadı.' } });
    const rows = await db.query<SpecialRequestRow>(
      `${specialRequestSelect}
        WHERE r.post_id=$1
          AND (r.sender_id=$2 OR EXISTS(SELECT 1 FROM community_posts p WHERE p.id=r.post_id AND p.author_id=$2))
        ORDER BY r.created_at DESC LIMIT 100`,
      [postId, userId],
    );
    return { data: rows.rows.map(specialRequestJson) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'REQUESTS_FAILED', message: 'İstekler yüklenemedi.' } });
  }
});

/// Who may say what: the owner accepts or declines, the sender withdraws.
/// Neither can do the other's half, and only a pending request can move - an
/// accepted request is a promise somebody is already acting on.
app.put('/v1/community/requests/:id/status', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = specialRequestStatusBody.parse(request.body);
    const actorClause = input.status === 'cancelled'
      ? 'r.sender_id=$3'
      : 'EXISTS(SELECT 1 FROM community_posts p WHERE p.id=r.post_id AND p.author_id=$3)';
    const updated = await db.query<{ id: string }>(
      `UPDATE post_special_requests r SET status=$2,updated_at=now()
        WHERE r.id=$1 AND r.status='pending' AND ${actorClause} RETURNING r.id`,
      [id, input.status, userId],
    );
    if (!updated.rows[0]) return reply.code(404).send({ error: { code: 'REQUEST_NOT_FOUND', message: 'İstek bulunamadı.' } });
    const row = await db.query<SpecialRequestRow>(`${specialRequestSelect} WHERE r.id=$1`, [id]);
    return { data: specialRequestJson(row.rows[0]!) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'REQUEST_STATUS_FAILED', message: 'İstek güncellenemedi.' } });
  }
});

/**
 * Saving, liking and sharing a listing.
 *
 * The three buttons on the listing card had no table behind them: the card sent
 * `isSaved:false` to every member on every request, and the app's repository
 * threw for all three writes. The icon filled in, the catch emptied it again,
 * and a saved listing was gone by the next refresh.
 *
 * The card also carried nobody's identity - `sellerId` was left at its default,
 * so every listing in production appeared to belong to the same fictional
 * member and no screen could tell the seller's own listing from a stranger's.
 *
 * Counts are counts. The seller learns that eleven people saved the listing,
 * never which eleven: wanting a used sofa is not an introduction the buyer
 * agreed to make.
 */
const listingColumns = (viewerParam: string) => `l.id,l.owner_id,l.title,l.description,l.price,l.category,l.city,l.region_code,l.created_at,
  COALESCE(cp.display_name,'TurkSquare üyesi') seller_name,
  (SELECT count(*) FROM marketplace_listing_reactions x WHERE x.listing_id=l.id AND x.kind='like') like_count,
  (SELECT count(*) FROM marketplace_listing_reactions x WHERE x.listing_id=l.id AND x.kind='share') share_count,
  EXISTS(SELECT 1 FROM marketplace_listing_reactions x WHERE x.listing_id=l.id AND x.actor_id=${viewerParam} AND x.kind='save') is_saved,
  EXISTS(SELECT 1 FROM marketplace_listing_reactions x WHERE x.listing_id=l.id AND x.actor_id=${viewerParam} AND x.kind='like') is_liked,
  (SELECT json_agg(json_build_object('id',m.id,'safeUrl',m.safe_url,'thumbnailUrl',m.thumbnail_url) ORDER BY r.ordinal) FROM marketplace_listing_media r JOIN media_assets m ON m.id=r.media_id WHERE r.listing_id=l.id AND m.status='ready') media`;

type ListingMediaRow = { id: string; safeUrl: string | null; thumbnailUrl: string | null };
type ListingRow = { id: string; owner_id: string; title: string; description: string; price: string; category: string; city: string | null; region_code: string | null; created_at: Date; seller_name: string; like_count: string; share_count: string; is_saved: boolean; is_liked: boolean; media: ListingMediaRow[] | null };

// A photo travels as an id and leaves as a URL that expires. The object store
// is never addressed directly by the app, so a link copied out of one response
// stops working instead of becoming a permanent public address for a member's
// living room.
const listingMediaJson = async (rows: ListingMediaRow[] | null) => Promise.all(
  (rows ?? []).filter((row) => row.safeUrl).map(async (row) => ({
    id: row.id,
    url: await mediaObjectUrl(row.safeUrl!),
    thumbnailUrl: row.thumbnailUrl ? await mediaObjectUrl(row.thumbnailUrl) : null,
  })),
);

// Condition is still the app's own vocabulary and the table has no column for
// it, so the card gets an empty string rather than a guess. Category is a real
// column since migration 030 and is passed through as the seller chose it.
const listingJson = async (l: ListingRow) => {
  const media = await listingMediaJson(l.media);
  // The first photo is the cover. imageUrl stays in the payload because the
  // card only ever draws one, and an empty string there is what the app already
  // reads as "this listing has no photo".
  return { id:l.id, sellerId:l.owner_id, title:l.title, description:l.description, price:Number(l.price), category:l.category, condition:'', location:[l.city,l.region_code].filter(Boolean).join(', '), sellerName:l.seller_name, imageUrl:media[0]?.url ?? '', media, isSaved:l.is_saved, isLiked:l.is_liked, likeCount:Number(l.like_count), shareCount:Number(l.share_count), createdAt:l.created_at.toISOString() };
};

const readListing = async (listingId: string, userId: string) => {
  const row = await db.query<ListingRow>(`SELECT ${listingColumns('$2')} FROM marketplace_listings l LEFT JOIN community_profile_projection cp ON cp.user_id=l.owner_id WHERE l.id=$1 AND l.status='active'`, [listingId, userId]);
  return row.rows[0] ?? null;
};

app.get('/v1/marketplace/listings',async(request,reply)=>{try{const userId=await viewer(request.headers);const input=listingQuery.parse(request.query);const cursor=decodeCursor(input.cursor);const params:unknown[]=[userId];let where="l.status='active'";if(input.sellerId){params.push(input.sellerId);where+=` AND l.owner_id=$${params.length}`;}if(input.category){params.push(input.category);where+=` AND l.category=$${params.length}`;}if(cursor){params.push(cursor.createdAt,cursor.id);where+=` AND (l.created_at,l.id) < ($${params.length-1}::timestamptz,$${params.length}::uuid)`;}params.push(input.limit+1);const rows=await db.query<ListingRow>(`SELECT ${listingColumns('$1')} FROM marketplace_listings l LEFT JOIN community_profile_projection cp ON cp.user_id=l.owner_id LEFT JOIN community_profile_projection v ON v.user_id=$1 WHERE ${where} ORDER BY (l.region_code=v.region_code) DESC,l.created_at DESC,l.id DESC LIMIT $${params.length}`,params);const page=rows.rows.slice(0,input.limit);const next=rows.rows.length>input.limit?encodeCursor(page[page.length-1]!):null;const data=await Promise.all(page.map(listingJson));return{data,meta:{nextCursor:next}};}catch(error){return reply.code((error as {statusCode?:number}).statusCode??401).send({error:{code:'LISTINGS_UNAVAILABLE'}});}});

/**
 * The seller behind a listing.
 *
 * Tapping the seller's name opened a profile the app filled in from nothing:
 * `getSellerProfile` returned a hardcoded record of zeros and
 * `getSellerListings` returned the entire marketplace, so a stranger's page
 * showed every listing on TurkSquare as theirs.
 *
 * What comes back here is only what is known: the name, the chosen city, how
 * many listings are up, and whether identity has been verified. There is no
 * rating, no response time and no sales count in this system yet, so none is
 * invented - a fabricated "0 out of 5" is a worse answer than no answer.
 */
/**
 * One listing, by id. Same reason as the post route above: a "kaydetti" or
 * "beğendi" notification names a listing the app could only find by paging
 * through the whole board.
 *
 * Only active listings answer. A sold or withdrawn listing is gone for the
 * reader as well as the board - the alternative is a notification opening a
 * page that can no longer be acted on.
 */
app.get('/v1/marketplace/listings/:id', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const listingId = z.string().uuid().parse((request.params as { id: string }).id);
    const rows = await db.query<ListingRow>(
      `SELECT ${listingColumns('$1')} FROM marketplace_listings l LEFT JOIN community_profile_projection cp ON cp.user_id=l.owner_id WHERE l.id=$2 AND l.status='active'`,
      [userId, listingId],
    );
    const listing = rows.rows[0];
    if (!listing) return reply.code(404).send({ error: { code: 'LISTING_NOT_FOUND', message: 'İlan bulunamadı.' } });
    return { data: await listingJson(listing) };
  } catch (error) {
    const status = readFailureStatus(error);
    if (status >= 500) request.log.error({ err: error }, 'listing read failed');
    return reply.code(status).send({ error: { code: 'LISTING_UNAVAILABLE', message: 'İlan yüklenemedi.' } });
  }
});

app.get('/v1/marketplace/sellers/:id', async (request, reply) => {
  try {
    // Read for authentication only: a seller's page is for members, and the
    // answer is the same for every one of them.
    await viewer(request.headers);
    const sellerId = z.string().uuid().parse((request.params as { id: string }).id);
    const row = await db.query<{ display_name: string | null; city: string | null; region_code: string | null; active_listings: string; identity_verified: boolean }>(
      `SELECT cp.display_name,cp.city,cp.region_code,
              (SELECT count(*) FROM marketplace_listings l WHERE l.owner_id=$1 AND l.status='active') active_listings,
              EXISTS(SELECT 1 FROM member_capabilities mc WHERE mc.user_id=$1 AND mc.identity_verified) identity_verified
         FROM (SELECT $1::uuid user_id) s
         LEFT JOIN community_profile_projection cp ON cp.user_id=s.user_id`, [sellerId]);
    const seller = row.rows[0]!;
    return { data: { id: sellerId, displayName: seller.display_name ?? 'TurkSquare üyesi', city: [seller.city, seller.region_code].filter(Boolean).join(', '), activeListingCount: Number(seller.active_listings), identityVerified: seller.identity_verified } };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'SELLER_UNAVAILABLE', message: 'Satıcı bilgisi alınamadı.' } });
  }
});

/**
 * The seller's own panel.
 *
 * "Satış merkezim" drew four boxes and a performance card entirely from local
 * placeholders that returned zero: a member with eleven saves on three listings
 * was told they had none, which is worse than an empty panel because it reads
 * as an answer.
 *
 * What is counted here is what the marketplace actually records: listings by
 * status, and saves, likes and shares on those listings. Views, messages and
 * offers are absent on purpose - nothing in this system tracks a listing view,
 * messages live in another service, and there is no offers table at all. They
 * are left out of the payload rather than sent as zero, so the app can tell
 * "none yet" apart from "not counted".
 */
app.get('/v1/marketplace/me/overview', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const totals = await db.query<{ active: string; reserved: string; sold: string; draft: string; saves: string; likes: string; shares: string; saves_7d: string; likes_7d: string; shares_7d: string }>(
      `WITH mine AS (SELECT id,status FROM marketplace_listings WHERE owner_id=$1),
            reactions AS (SELECT x.kind,x.created_at FROM marketplace_listing_reactions x JOIN mine ON mine.id=x.listing_id)
       SELECT (SELECT count(*) FROM mine WHERE status='active') active,
              (SELECT count(*) FROM mine WHERE status='reserved') reserved,
              (SELECT count(*) FROM mine WHERE status='sold') sold,
              (SELECT count(*) FROM mine WHERE status='draft') draft,
              (SELECT count(*) FROM reactions WHERE kind='save') saves,
              (SELECT count(*) FROM reactions WHERE kind='like') likes,
              (SELECT count(*) FROM reactions WHERE kind='share') shares,
              (SELECT count(*) FROM reactions WHERE kind='save' AND created_at > now() - interval '7 days') saves_7d,
              (SELECT count(*) FROM reactions WHERE kind='like' AND created_at > now() - interval '7 days') likes_7d,
              (SELECT count(*) FROM reactions WHERE kind='share' AND created_at > now() - interval '7 days') shares_7d`,
      [userId]);
    // The listing most people saved, not the one posted last. A seller reading
    // this wants to know which one is working.
    const top = await db.query<{ id: string; title: string; saves: string }>(
      `SELECT l.id,l.title,count(x.*) saves
         FROM marketplace_listings l
         LEFT JOIN marketplace_listing_reactions x ON x.listing_id=l.id AND x.kind='save'
        WHERE l.owner_id=$1 AND l.status='active'
        GROUP BY l.id,l.title
        ORDER BY saves DESC,l.created_at DESC
        LIMIT 1`, [userId]);
    const t = totals.rows[0]!;
    const best = top.rows[0];
    return { data: {
      sellerId: userId,
      activeListings: Number(t.active), reservedListings: Number(t.reserved), soldListings: Number(t.sold), draftListings: Number(t.draft),
      saves: Number(t.saves), likes: Number(t.likes), shares: Number(t.shares),
      saves7d: Number(t.saves_7d), likes7d: Number(t.likes_7d), shares7d: Number(t.shares_7d),
      topListing: best ? { id: best.id, title: best.title, saves: Number(best.saves) } : null,
    } };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'SELLER_OVERVIEW_UNAVAILABLE', message: 'Satış merkezi bilgileri alınamadı.' } });
  }
});

app.put('/v1/marketplace/listings/:id/reactions/:kind', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const listingId = z.string().uuid().parse((request.params as { id: string }).id);
    const kind = z.enum(['save','like']).parse((request.params as { kind: string }).kind);
    const input = z.object({ enabled: z.boolean() }).parse(request.body);
    // State, not delta: a retried tap on a flaky connection lands on the same
    // answer as the first one.
    if (input.enabled) await db.query("INSERT INTO marketplace_listing_reactions(listing_id,actor_id,kind) SELECT $1,$2,$3 WHERE EXISTS(SELECT 1 FROM marketplace_listings WHERE id=$1 AND status='active') ON CONFLICT DO NOTHING", [listingId, userId, kind]);
    else await db.query('DELETE FROM marketplace_listing_reactions WHERE listing_id=$1 AND actor_id=$2 AND kind=$3', [listingId, userId, kind]);
    // The seller learns that somebody saved it, never who. That is the same
    // line the counts on the card already draw, and the bell does not cross it.
    if (input.enabled) notifyOwner(kind === 'save' ? 'listing_save' : 'listing_like', listingId, userId);
    const listing = await readListing(listingId, userId);
    if (!listing) return reply.code(404).send({ error: { code: 'LISTING_NOT_AVAILABLE', message: 'İlan bulunamadı.' } });
    return { data: await listingJson(listing) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'LISTING_REACTION_FAILED', message: 'İşlem kaydedilemedi.' } });
  }
});

app.post('/v1/marketplace/listings/:id/shares', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const listingId = z.string().uuid().parse((request.params as { id: string }).id);
    // Sharing the same listing twice is still one member telling their circle
    // about it, so the count follows people rather than taps.
    await db.query("INSERT INTO marketplace_listing_reactions(listing_id,actor_id,kind) SELECT $1,$2,'share' WHERE EXISTS(SELECT 1 FROM marketplace_listings WHERE id=$1 AND status='active') ON CONFLICT DO NOTHING", [listingId, userId]);
    const listing = await readListing(listingId, userId);
    if (!listing) return reply.code(404).send({ error: { code: 'LISTING_NOT_AVAILABLE', message: 'İlan bulunamadı.' } });
    return { data: await listingJson(listing) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'LISTING_SHARE_FAILED', message: 'Paylaşım kaydedilemedi.' } });
  }
});
/**
 * Publish a listing.
 *
 * The photos the seller picked used to stop at the phone: there was no column
 * to put them in, so every card in the marketplace drew the same stock kitchen.
 * They now arrive as ids of already-scanned uploads and the listing keeps them
 * in the order they were chosen, because the first one is the cover.
 *
 * Listing and photos are written together. A listing that appears without its
 * photos is a listing the seller has to delete and write again.
 */
app.post('/v1/marketplace/listings',async(request,reply)=>{
  const client=await db.connect();
  try{
    const userId=await viewer(request.headers);
    const input=listingBody.parse(request.body);
    await client.query('BEGIN');
    const row=await client.query<{id:string}>('INSERT INTO marketplace_listings(owner_id,title,description,price,category,city,region_code) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id',[userId,input.title,input.description,input.price,input.category,input.city??null,input.regionCode?.toUpperCase()??null]);
    const id=row.rows[0]!.id;
    if(input.mediaIds?.length){
      const distinct=new Set(input.mediaIds);
      const ready=await client.query<{id:string}>("SELECT id FROM media_assets WHERE id=ANY($1::uuid[]) AND owner_id=$2 AND status='ready' FOR KEY SHARE",[input.mediaIds,userId]);
      // Every id has to be the seller's own, scanned, and listed once: a repeat
      // would put the same photo on the listing twice under two ordinals.
      if(ready.rows.length!==distinct.size||distinct.size!==input.mediaIds.length){
        await client.query('ROLLBACK');
        return reply.code(400).send({error:{code:'MEDIA_NOT_READY',message:'Fotoğraflar hazır değil.'}});
      }
      for(const [ordinal,mediaId] of input.mediaIds.entries()) await client.query('INSERT INTO marketplace_listing_media(listing_id,media_id,ordinal) VALUES($1,$2,$3)',[id,mediaId,ordinal]);
    }
    await client.query('COMMIT');
    return reply.code(201).send({data:{id}});
  }catch{
    await client.query('ROLLBACK').catch(()=>{});
    return reply.code(400).send({error:{code:'LISTING_CREATE_FAILED'}});
  }finally{client.release();}
});
app.post('/v1/marketplace/listings/:id/auction',async(request,reply)=>{try{const userId=await viewer(request.headers);const listingId=z.string().uuid().parse((request.params as {id:string}).id);const input=auctionBody.parse(request.body);const eligible=await db.query('SELECT 1 FROM member_capabilities WHERE user_id=$1 AND auction_seller_eligible',[userId]);if(!eligible.rows[0])return reply.code(403).send({error:{code:'VERIFICATION_REQUIRED',message:'İhale açmak için Onaylı Hesap rozeti gerekir.'}});const row=await db.query<{id:string}>('INSERT INTO marketplace_auctions(listing_id,seller_id,starting_price,minimum_increment,starts_at,ends_at) SELECT $1,$2,$3,$4,$5,$6 WHERE EXISTS(SELECT 1 FROM marketplace_listings WHERE id=$1 AND owner_id=$2 AND status=\'active\') RETURNING id',[listingId,userId,input.startingPrice,input.minimumIncrement,input.startsAt,input.endsAt]);if(!row.rows[0])return reply.code(404).send({error:{code:'LISTING_NOT_AVAILABLE'}});return reply.code(201).send({data:row.rows[0]});}catch{return reply.code(400).send({error:{code:'AUCTION_CREATE_FAILED'}});}});
app.post('/v1/marketplace/auctions/:id/bids',async(request,reply)=>{const client=await db.connect();try{const userId=await viewer(request.headers);const id=z.string().uuid().parse((request.params as {id:string}).id);const input=bidBody.parse(request.body);await client.query('BEGIN');const auction=await client.query<{seller_id:string;starting_price:string;minimum_increment:string;starts_at:Date;ends_at:Date;status:string}>('SELECT seller_id,starting_price,minimum_increment,starts_at,ends_at,status FROM marketplace_auctions WHERE id=$1 FOR UPDATE',[id]);const a=auction.rows[0];
  // status is read for one reason: an operator cancelling an auction has to stop
  // the bidding. Nothing else writes it - it is inserted 'scheduled' and stays
  // there - so the open/closed window is still the clock, not the column.
  if(!a||a.status==='cancelled'||a.seller_id===userId||a.starts_at>new Date()||a.ends_at<=new Date())throw Error();const top=await client.query<{amount:string}>('SELECT amount FROM marketplace_auction_bids WHERE auction_id=$1 ORDER BY amount DESC,created_at ASC LIMIT 1',[id]);const minimum=Number(top.rows[0]?.amount??a.starting_price)+(top.rows[0]?Number(a.minimum_increment):0);if(input.amount<minimum)throw Error();const bid=await client.query<{id:string}>('INSERT INTO marketplace_auction_bids(auction_id,bidder_id,amount) VALUES($1,$2,$3) RETURNING id',[id,userId,input.amount]);await client.query('COMMIT');return reply.code(201).send({data:bid.rows[0]});}catch{await client.query('ROLLBACK');return reply.code(400).send({error:{code:'BID_REJECTED',message:'Teklif kabul edilemedi.'}});}finally{client.release();}});
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
    // And an unanswered request goes with it. Leaving it pending would put the
    // blocked account back in the blocker's inbox with an Accept button.
    await client.query(
      "DELETE FROM friend_requests WHERE status='pending' AND ((requester_id=$1 AND addressee_id=$2) OR (requester_id=$2 AND addressee_id=$1))",
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

/**
 * Arkadaşlık.
 *
 * `relationship_projection` has been read by nearly every access decision in
 * this service since migration 002 and never written by anything. These routes
 * are what finally writes it: accepting a request inserts both directions in
 * the same transaction, so the friendship exists in full or not at all.
 *
 * The friendship is symmetric on purpose. A one-way follow is a different
 * feature with different consent, and half of one is not a starting point.
 */
const friendRequestBody = z.object({ userId: z.string().uuid() });
const friendAnswerBody = z.object({ status: z.enum(['accepted', 'declined']) });

/// The viewer's standing with somebody else, in one word. The app draws a
/// different button for each, so a wrong answer here is a button that does
/// nothing.
async function relationshipWith(viewerId: string, otherId: string) {
  if (viewerId === otherId) return { relationship: 'self' as const, requestId: null };
  const row = await db.query<{ blocked: boolean; friend: boolean; request_id: string | null; incoming: boolean }>(
    `SELECT
       EXISTS(SELECT 1 FROM user_blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=$2) OR (b.blocker_id=$2 AND b.blocked_id=$1)) blocked,
       EXISTS(SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=$2 AND r.relationship='friend' AND r.active) friend,
       (SELECT f.id FROM friend_requests f WHERE f.status='pending' AND ((f.requester_id=$1 AND f.addressee_id=$2) OR (f.requester_id=$2 AND f.addressee_id=$1)) LIMIT 1) request_id,
       EXISTS(SELECT 1 FROM friend_requests f WHERE f.status='pending' AND f.requester_id=$2 AND f.addressee_id=$1) incoming`,
    [viewerId, otherId],
  );
  const state = row.rows[0]!;
  // Blocked outranks everything: whatever else is true, there is nothing to do
  // with this person until the block goes.
  if (state.blocked) return { relationship: 'blocked' as const, requestId: null };
  if (state.friend) return { relationship: 'friends' as const, requestId: null };
  if (state.request_id) return { relationship: state.incoming ? ('pendingIncoming' as const) : ('pendingOutgoing' as const), requestId: state.request_id };
  return { relationship: 'none' as const, requestId: null };
}

/// Writes the friendship itself. Both directions, one transaction: a projection
/// with only one row would mean A sees B's friends-only posts and B does not
/// see A's, which is not what either of them agreed to.
async function acceptFriendRequest(client: pg.PoolClient, requestId: string, addresseeId: string) {
  const answered = await client.query<{ requester_id: string }>(
    "UPDATE friend_requests SET status='accepted',updated_at=now() WHERE id=$1 AND addressee_id=$2 AND status='pending' RETURNING requester_id",
    [requestId, addresseeId],
  );
  const accepted = answered.rows[0];
  if (!accepted) return null;
  await client.query(
    `INSERT INTO relationship_projection(viewer_id,subject_id,relationship,active)
     VALUES($1,$2,'friend',true),($2,$1,'friend',true)
     ON CONFLICT (viewer_id,subject_id,relationship) DO UPDATE SET active=true,updated_at=now()`,
    [addresseeId, accepted.requester_id],
  );
  // The other side may have asked too. Two people who both sent a request are
  // not left with one of them still pending in an inbox.
  await client.query(
    "UPDATE friend_requests SET status='accepted',updated_at=now() WHERE status='pending' AND requester_id=$1 AND addressee_id=$2",
    [addresseeId, accepted.requester_id],
  );
  return accepted.requester_id;
}

app.post('/v1/community/friends/requests', { config: { rateLimit: { max: 30, timeWindow: '1 hour' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const viewerId = await viewer(request.headers);
    const restricted = await activeRestriction(viewerId);
    if (restricted) return reply.code(403).send(restrictionError(restricted));
    const { userId: targetId } = friendRequestBody.parse(request.body);
    if (viewerId === targetId) return reply.code(400).send({ error: { code: 'FRIEND_SELF_NOT_ALLOWED', message: 'Kendinize arkadaşlık isteği gönderemezsiniz.' } });
    const exists = await db.query('SELECT 1 FROM community_profile_projection WHERE user_id=$1', [targetId]);
    if (!exists.rows[0]) return reply.code(404).send({ error: { code: 'MEMBER_NOT_FOUND', message: 'Üye bulunamadı.' } });
    const standing = await relationshipWith(viewerId, targetId);
    if (standing.relationship === 'blocked') return reply.code(403).send({ error: { code: 'BLOCKED', message: 'Bu üyeye istek gönderemezsiniz.' } });
    if (standing.relationship === 'friends') return reply.code(409).send({ error: { code: 'ALREADY_FRIENDS', message: 'Zaten arkadaşsınız.' } });
    await client.query('BEGIN');
    // Both of you asked: that is a yes, not a second queue. The incoming
    // request is accepted here rather than sitting in an inbox waiting for a
    // tap that would say exactly what this request already said.
    if (standing.relationship === 'pendingIncoming' && standing.requestId) {
      await acceptFriendRequest(client, standing.requestId, viewerId);
      await client.query('COMMIT');
      return reply.code(200).send({ data: { relationship: 'friends', requestId: null } });
    }
    if (standing.relationship === 'pendingOutgoing') {
      await client.query('ROLLBACK');
      return reply.code(409).send({ error: { code: 'REQUEST_PENDING', message: 'İsteğin zaten gönderildi.' } });
    }
    const inserted = await client.query<{ id: string }>(
      'INSERT INTO friend_requests(requester_id,addressee_id) VALUES($1,$2) ON CONFLICT (requester_id,addressee_id) DO NOTHING RETURNING id',
      [viewerId, targetId],
    );
    const created = inserted.rows[0];
    if (!created) {
      // The only row that can be here now is one this member already sent and
      // that was declined. Asking again after a no is what the constraint is for.
      await client.query('ROLLBACK');
      return reply.code(409).send({ error: { code: 'REQUEST_ALREADY_ANSWERED', message: 'Bu üyeye daha önce istek gönderdin.' } });
    }
    await client.query('COMMIT');
    notifyOwner('friend_request', created.id, viewerId);
    return reply.code(201).send({ data: { relationship: 'pendingOutgoing', requestId: created.id } });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FRIEND_REQUEST_FAILED', message: 'Arkadaşlık isteği gönderilemedi.' } });
  } finally {
    client.release();
  }
});

type FriendRequestRow = { id: string; user_id: string; display_name: string; avatar_url: string | null; created_at: Date; direction: 'incoming' | 'outgoing' };

/// Both directions in one answer. A member who is waiting on somebody else and
/// a member somebody else is waiting on are the same screen.
app.get('/v1/community/friends/requests', async (request, reply) => {
  try {
    const viewerId = await viewer(request.headers);
    const rows = await db.query<FriendRequestRow>(
      `SELECT f.id,f.created_at,
              CASE WHEN f.addressee_id=$1 THEN 'incoming' ELSE 'outgoing' END direction,
              CASE WHEN f.addressee_id=$1 THEN f.requester_id ELSE f.addressee_id END user_id,
              COALESCE(p.display_name,'TurkSquare üyesi') display_name,
              (SELECT m.safe_url FROM media_assets m JOIN member_profiles mp ON mp.avatar_media_id=m.id WHERE mp.user_id=p.user_id AND m.status='ready') avatar_url
         FROM friend_requests f
         LEFT JOIN community_profile_projection p
           ON p.user_id = CASE WHEN f.addressee_id=$1 THEN f.requester_id ELSE f.addressee_id END
        WHERE f.status='pending' AND (f.addressee_id=$1 OR f.requester_id=$1)
        ORDER BY f.created_at DESC
        LIMIT 100`,
      [viewerId],
    );
    const data = await Promise.all(rows.rows.map(async (row) => ({
      id: row.id,
      direction: row.direction,
      userId: row.user_id,
      displayName: row.display_name,
      avatarUrl: row.avatar_url ? await mediaObjectUrl(row.avatar_url) : null,
      createdAt: row.created_at.toISOString(),
    })));
    return { data };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FRIEND_REQUESTS_UNAVAILABLE', message: 'Arkadaşlık istekleri yüklenemedi.' } });
  }
});

app.put('/v1/community/friends/requests/:id', async (request, reply) => {
  const client = await db.connect();
  try {
    const viewerId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = friendAnswerBody.parse(request.body);
    await client.query('BEGIN');
    if (input.status === 'declined') {
      // The decline is kept, unlike a cancellation: it is the record that says
      // this particular ask has been answered and cannot be repeated.
      const declined = await client.query(
        "UPDATE friend_requests SET status='declined',updated_at=now() WHERE id=$1 AND addressee_id=$2 AND status='pending' RETURNING id",
        [id, viewerId],
      );
      if (!declined.rows[0]) { await client.query('ROLLBACK'); return reply.code(404).send({ error: { code: 'REQUEST_NOT_FOUND', message: 'İstek bulunamadı.' } }); }
      await client.query('COMMIT');
      return { data: { relationship: 'none', requestId: null } };
    }
    const requesterId = await acceptFriendRequest(client, id, viewerId);
    if (!requesterId) { await client.query('ROLLBACK'); return reply.code(404).send({ error: { code: 'REQUEST_NOT_FOUND', message: 'İstek bulunamadı.' } }); }
    await client.query('COMMIT');
    return { data: { relationship: 'friends', requestId: null } };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FRIEND_ANSWER_FAILED', message: 'İstek güncellenemedi.' } });
  } finally {
    client.release();
  }
});

/// Withdrawing your own request. The row goes rather than being marked, so this
/// is not held against the member later: changing your mind about asking is not
/// the same as being told no.
app.delete('/v1/community/friends/requests/:id', async (request, reply) => {
  try {
    const viewerId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const removed = await db.query("DELETE FROM friend_requests WHERE id=$1 AND requester_id=$2 AND status='pending' RETURNING id", [id, viewerId]);
    if (!removed.rows[0]) return reply.code(404).send({ error: { code: 'REQUEST_NOT_FOUND', message: 'İstek bulunamadı.' } });
    return reply.code(204).send();
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FRIEND_CANCEL_FAILED', message: 'İstek geri çekilemedi.' } });
  }
});

app.get('/v1/community/friends', async (request, reply) => {
  try {
    const viewerId = await viewer(request.headers);
    const ownerId = z.string().uuid().optional().parse((request.query as { userId?: string }).userId) ?? viewerId;
    // Somebody else's friend list obeys the same lock as their profile.
    const access = await profileAccess(viewerId, ownerId);
    if (access.blocked) return reply.code(404).send({ error: { code: 'PROFILE_NOT_FOUND', message: 'Profil bulunamadı.' } });
    if (!access.full) return { data: [], meta: { locked: true } };
    const rows = await db.query<{ user_id: string; display_name: string; city: string | null; region_code: string | null; avatar_url: string | null }>(
      `SELECT p.user_id,COALESCE(p.display_name,'TurkSquare üyesi') display_name,p.city,p.region_code,
              (SELECT m.safe_url FROM media_assets m JOIN member_profiles mp ON mp.avatar_media_id=m.id WHERE mp.user_id=p.user_id AND m.status='ready') avatar_url
         FROM relationship_projection r
         JOIN community_profile_projection p ON p.user_id=r.subject_id
        WHERE r.viewer_id=$1 AND r.relationship='friend' AND r.active
        ORDER BY p.display_name
        LIMIT 200`,
      [ownerId],
    );
    const data = await Promise.all(rows.rows.map(async (row) => ({
      userId: row.user_id,
      displayName: row.display_name,
      city: row.city,
      regionCode: row.region_code,
      avatarUrl: row.avatar_url ? await mediaObjectUrl(row.avatar_url) : null,
    })));
    return { data, meta: { locked: false } };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FRIENDS_UNAVAILABLE', message: 'Arkadaş listesi yüklenemedi.' } });
  }
});

/// Unfriending. Both projection rows go inactive and the request record is
/// removed entirely, so either of them may ask again one day.
app.delete('/v1/community/friends/:userId', async (request, reply) => {
  const client = await db.connect();
  try {
    const viewerId = await viewer(request.headers);
    const otherId = z.string().uuid().parse((request.params as { userId: string }).userId);
    await client.query('BEGIN');
    await client.query(
      'UPDATE relationship_projection SET active=false,updated_at=now() WHERE active AND relationship=$3 AND ((viewer_id=$1 AND subject_id=$2) OR (viewer_id=$2 AND subject_id=$1))',
      [viewerId, otherId, 'friend'],
    );
    await client.query(
      'DELETE FROM friend_requests WHERE (requester_id=$1 AND addressee_id=$2) OR (requester_id=$2 AND addressee_id=$1)',
      [viewerId, otherId],
    );
    await client.query('COMMIT');
    return reply.code(204).send();
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'UNFRIEND_FAILED', message: 'Arkadaşlıktan çıkarılamadı.' } });
  } finally {
    client.release();
  }
});

app.get('/v1/community/friends/status/:userId', async (request, reply) => {
  try {
    const viewerId = await viewer(request.headers);
    const otherId = z.string().uuid().parse((request.params as { userId: string }).userId);
    return { data: await relationshipWith(viewerId, otherId) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FRIEND_STATUS_UNAVAILABLE', message: 'Arkadaşlık durumu okunamadı.' } });
  }
});

/**
 * Takip.
 *
 * Arkadaşlıktan farkı rızanın yönü: takip etmek için karşı tarafa sormuyorsun,
 * arkadaş olmak için soruyorsun. Bu yüzden istek kuyruğu yok, tek bir INSERT
 * var. Takip, arkadaşa özel paylaşımları açmıyor - onu yalnızca 'friend'
 * satırları açıyor; takip yalnızca akıştaki "Takip ettiklerin" sekmesini ve
 * Story şeridini besliyor.
 *
 * Satırlar 002'den beri şemada duran relationship_projection'a yazılıyor.
 */
// DISTINCT şart: bir kişi hem 'following' hem 'friend' satırı taşıyabiliyor
// (önce takip etmiş, sonra arkadaş olmuşlar) ve o kişi listede iki kez çıkardı.
const FOLLOW_LIST_SELECT = `
  SELECT DISTINCT p.user_id,COALESCE(p.display_name,'TurkSquare üyesi') display_name,mp.username,p.city,p.region_code,
         (SELECT m.safe_url FROM media_assets m WHERE m.id=mp.avatar_media_id AND m.status='ready') avatar_url,
         EXISTS(SELECT 1 FROM relationship_projection vr WHERE vr.viewer_id=$2 AND vr.subject_id=p.user_id AND vr.active) viewer_follows
    FROM relationship_projection r
    JOIN community_profile_projection p ON p.user_id=`;

type FollowRow = {
  user_id: string; display_name: string; username: string | null; city: string | null;
  region_code: string | null; avatar_url: string | null; viewer_follows: boolean;
};

async function toFollowDto(row: FollowRow) {
  return {
    userId: row.user_id,
    displayName: row.display_name,
    username: row.username,
    city: row.city,
    regionCode: row.region_code,
    avatarUrl: row.avatar_url ? await mediaObjectUrl(row.avatar_url) : null,
    viewerFollows: row.viewer_follows,
  };
}

/// Kilitli bir profilin takipçi listesi de kilitli. Boş dizi ile kilit ayrı ayrı
/// dönüyor: uygulama "kimse takip etmiyor" ile "göremiyorsun" arasındaki farkı
/// ekranda söylemek zorunda.
async function followList(
  request: FastifyRequest,
  reply: FastifyReply,
  direction: 'followers' | 'following',
) {
  const viewerId = await viewer(request.headers);
  const ownerId = z.string().uuid().parse((request.params as { userId: string }).userId);
  const access = await profileAccess(viewerId, ownerId);
  if (access.blocked) return reply.code(404).send({ error: { code: 'PROFILE_NOT_FOUND', message: 'Profil bulunamadı.' } });
  if (!access.full) return { data: [], meta: { locked: true } };
  const joinColumn = direction === 'followers' ? 'r.viewer_id' : 'r.subject_id';
  const matchColumn = direction === 'followers' ? 'r.subject_id' : 'r.viewer_id';
  const rows = await db.query<FollowRow>(
    `${FOLLOW_LIST_SELECT}${joinColumn}
     LEFT JOIN member_profiles mp ON mp.user_id=p.user_id
     WHERE ${matchColumn}=$1 AND r.active
     ORDER BY p.display_name
     LIMIT 500`,
    [ownerId, viewerId],
  );
  return { data: await Promise.all(rows.rows.map(toFollowDto)), meta: { locked: false } };
}

app.get('/v1/community/profiles/:userId/followers', async (request, reply) => {
  try {
    return await followList(request, reply, 'followers');
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FOLLOWERS_UNAVAILABLE', message: 'Takipçi listesi yüklenemedi.' } });
  }
});

app.get('/v1/community/profiles/:userId/following', async (request, reply) => {
  try {
    return await followList(request, reply, 'following');
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FOLLOWING_UNAVAILABLE', message: 'Takip listesi yüklenemedi.' } });
  }
});

app.post('/v1/community/members/:userId/follow', { config: { rateLimit: { max: 120, timeWindow: '1 hour' } } }, async (request, reply) => {
  try {
    const viewerId = await viewer(request.headers);
    const restricted = await activeRestriction(viewerId);
    if (restricted) return reply.code(403).send(restrictionError(restricted));
    const targetId = z.string().uuid().parse((request.params as { userId: string }).userId);
    if (targetId === viewerId) return reply.code(400).send({ error: { code: 'CANNOT_FOLLOW_SELF', message: 'Kendini takip edemezsin.' } });
    const blocked = await db.query(
      'SELECT 1 FROM user_blocks WHERE (blocker_id=$1 AND blocked_id=$2) OR (blocker_id=$2 AND blocked_id=$1)',
      [viewerId, targetId],
    );
    // Engellenen profil 404 veriyor; takip de aynısını vermeli, yoksa engel bir
    // "bu hesap var mı" sorgusuna dönüşür.
    if (blocked.rowCount) return reply.code(404).send({ error: { code: 'PROFILE_NOT_FOUND', message: 'Profil bulunamadı.' } });
    const exists = await db.query('SELECT 1 FROM community_profile_projection WHERE user_id=$1', [targetId]);
    if (!exists.rowCount) return reply.code(404).send({ error: { code: 'PROFILE_NOT_FOUND', message: 'Profil bulunamadı.' } });
    await db.query(
      `INSERT INTO relationship_projection(viewer_id,subject_id,relationship,active)
       VALUES($1,$2,'following',true)
       ON CONFLICT (viewer_id,subject_id,relationship) DO UPDATE SET active=true,updated_at=now()`,
      [viewerId, targetId],
    );
    return { data: { following: true } };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FOLLOW_FAILED', message: 'Takip edilemedi.' } });
  }
});

app.delete('/v1/community/members/:userId/follow', async (request, reply) => {
  try {
    const viewerId = await viewer(request.headers);
    const targetId = z.string().uuid().parse((request.params as { userId: string }).userId);
    // Yalnızca 'following' satırı kalkıyor. Arkadaşlık simetrik ve karşılıklı
    // onaylı: onu tek taraflı bir "takipten çık" dokunuşuyla bozmak, üyenin
    // istemediği bir şeyi yapmak olurdu. Arkadaşlıktan çıkmanın kendi yolu var.
    await db.query(
      "UPDATE relationship_projection SET active=false,updated_at=now() WHERE viewer_id=$1 AND subject_id=$2 AND relationship='following' AND active",
      [viewerId, targetId],
    );
    const stillFriends = await db.query(
      "SELECT 1 FROM relationship_projection WHERE viewer_id=$1 AND subject_id=$2 AND relationship='friend' AND active",
      [viewerId, targetId],
    );
    // Arkadaşlık devam ediyorsa kişi hâlâ takip edilenler arasında. Uygulamaya
    // "takipten çıktın" dedirtip listede bırakmak, ekranın kendi kendisiyle
    // çelişmesi olurdu; `keptByFriendship` bunun nedenini söylüyor.
    const keptByFriendship = (stillFriends.rowCount ?? 0) > 0;
    return { data: { following: keptByFriendship, keptByFriendship } };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'UNFOLLOW_FAILED', message: 'Takipten çıkılamadı.' } });
  }
});

/// Kendi takipçini listeden çıkarmak. Takipten çıkmanın aynası: bu sefer silinen
/// satır karşı tarafın satırı, o yüzden yalnızca kendi profilinde çalışıyor.
app.delete('/v1/community/members/:userId/follower', async (request, reply) => {
  try {
    const viewerId = await viewer(request.headers);
    const targetId = z.string().uuid().parse((request.params as { userId: string }).userId);
    const friends = await db.query(
      "SELECT 1 FROM relationship_projection WHERE viewer_id=$1 AND subject_id=$2 AND relationship='friend' AND active",
      [targetId, viewerId],
    );
    if (friends.rowCount) {
      return reply.code(409).send({ error: { code: 'FOLLOWER_IS_FRIEND', message: 'Bu kişi arkadaşın. Listeden çıkarmak için önce arkadaşlıktan çıkarman gerekiyor.' } });
    }
    await db.query(
      "UPDATE relationship_projection SET active=false,updated_at=now() WHERE viewer_id=$1 AND subject_id=$2 AND relationship='following' AND active",
      [targetId, viewerId],
    );
    return reply.code(204).send();
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'FOLLOWER_REMOVE_FAILED', message: 'Takipçi çıkarılamadı.' } });
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
// Reading the operation trail. Identity keeps the same shape for its own log, so
// the console can put the two side by side without a translation layer.
const AUDIT_READ_ROLES: GateworkRole[] = ['owner', 'security_admin', 'auditor'];
const gateworkAuditQuery = z.object({
  limit: z.coerce.number().int().min(1).max(200).default(100),
  offset: z.coerce.number().int().min(0).max(10_000).default(0),
  action: z.string().trim().min(2).max(80).optional(),
  actorId: z.string().uuid().optional(),
  outcome: z.enum(['succeeded', 'denied', 'failed']).optional(),
});

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

// Two trails, not one. gatework_operation_audit_events records what an operator
// asked this service to do - a category opened, a capability set, a topic pinned
// - while content_moderation_actions records decisions taken about a member's
// content. Merging them here would lose which is which; the console shows both
// under one screen and keeps the distinction in the row.
app.get('/v1/internal/gatework/audit', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, AUDIT_READ_ROLES);
    const input = gateworkAuditQuery.parse(request.query);
    const rows = await db.query<{ id: string; actor_id: string; actor_name: string | null; actor_roles: string[]; action: string; target_type: string; target_id: string; reason: string | null; outcome: string; created_at: Date; source: string }>(
      `SELECT e.id,e.actor_id,p.display_name actor_name,e.actor_roles,e.action,e.target_type,e.target_id,e.reason,e.outcome,e.created_at,'operation' source
         FROM gatework_operation_audit_events e LEFT JOIN community_profile_projection p ON p.user_id=e.actor_id
        WHERE ($3::text IS NULL OR e.action LIKE $3||'%') AND ($4::uuid IS NULL OR e.actor_id=$4) AND ($5::text IS NULL OR e.outcome=$5)
       UNION ALL
       -- A moderation decision has no outcome column: it is written only after
       -- the decision has been applied, so it is a succeeded row by construction.
       SELECT m.id,m.actor_id,p.display_name,m.actor_roles,m.action,m.target_type,m.target_id,m.reason,'succeeded',m.created_at,'moderation'
         FROM content_moderation_actions m LEFT JOIN community_profile_projection p ON p.user_id=m.actor_id
        WHERE ($3::text IS NULL OR m.action LIKE $3||'%') AND ($4::uuid IS NULL OR m.actor_id=$4) AND ($5::text IS NULL OR $5='succeeded')
       ORDER BY created_at DESC, id DESC LIMIT $1 OFFSET $2`,
      [input.limit, input.offset, input.action ?? null, input.actorId ?? null, input.outcome ?? null],
    );
    return {
      data: rows.rows.map((row) => ({ id: row.id, actorId: row.actor_id, actorName: row.actor_name, actorRoles: row.actor_roles, action: row.action, targetType: row.target_type, targetId: row.target_id, reason: row.reason, outcome: row.outcome, source: row.source, createdAt: row.created_at.toISOString() })),
      meta: { nextOffset: rows.rows.length === input.limit ? input.offset + input.limit : null },
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'AUDIT_UNAVAILABLE', message: 'Denetim kaydı okunamadı.' } });
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

/// Aynı kural üç yerde geçerli: burada, müsaitlik ucunda ve göç 037'deki CHECK
/// içinde. Üçü ayrışırsa uygulama "müsait" deyip sunucu reddeder.
const USERNAME_PATTERN = /^[a-z0-9][a-z0-9_.]{1,22}[a-z0-9]$/;

/// Kimsenin alamayacağı adlar. Bunlar bir kişiyi değil kurumu ya da bir ekranı
/// işaret ediyor; "@destek" adlı bir üye, uygulamanın kendisi sanılabilir.
const RESERVED_USERNAMES = new Set([
  'admin', 'admins', 'administrator', 'destek', 'support', 'yardim', 'help',
  'turksquare', 'turk_square', 'official', 'resmi', 'moderator', 'mod',
  'guvenlik', 'security', 'sistem', 'system', 'root', 'me', 'ben', 'profil',
  'profile', 'ayarlar', 'settings', 'null', 'undefined',
]);

const usernameField = z
  .string()
  .trim()
  .toLowerCase()
  .regex(USERNAME_PATTERN)
  .refine((value) => !value.includes('..'))
  .refine((value) => !RESERVED_USERNAMES.has(value));

const profilePatchBody = z.object({
  bio: z.string().trim().max(280).nullable().optional(),
  avatarMediaId: z.string().uuid().nullable().optional(),
  visibility: z.enum(['public', 'friends_only']).optional(),
  showcasedBadges: z.array(z.string().regex(/^[a-z0-9_]{3,60}$/)).max(3).optional(),
  // Bir kez boşaltılabiliyor ama boş dize ile değil: null "kullanıcı adım
  // olmasın" demek, '' ise doğrulamadan geçmiş bir kaza olurdu.
  username: usernameField.nullable().optional(),
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

/**
 * Where each kind of notification finds its recipient.
 *
 * The owner is looked up inside the insert rather than fetched first, so there
 * is no window where the post is deleted between the two statements and a
 * notification lands for something that no longer exists.
 */
const NOTIFICATION_SUBJECTS = {
  post_comment: 'SELECT p.author_id,p.id FROM community_posts p WHERE p.id=$1 AND p.deleted_at IS NULL',
  post_like: 'SELECT p.author_id,p.id FROM community_posts p WHERE p.id=$1 AND p.deleted_at IS NULL',
  listing_save: "SELECT l.owner_id,l.id FROM marketplace_listings l WHERE l.id=$1 AND l.status='active'",
  listing_like: "SELECT l.owner_id,l.id FROM marketplace_listings l WHERE l.id=$1 AND l.status='active'",
  special_request: 'SELECT p.author_id,p.id FROM community_posts p WHERE p.id=$1 AND p.deleted_at IS NULL',
  // The only kind whose $1 is not the subject: a friend request is looked up by
  // its own id, and the subject it files itself under is the person who asked.
  // One line per requester, so ten separate people are ten separate answers to
  // give rather than one line saying "10".
  friend_request: "SELECT r.addressee_id,r.requester_id FROM friend_requests r WHERE r.id=$1 AND r.status='pending'",
} as const;
type NotificationKind = keyof typeof NOTIFICATION_SUBJECTS;

/// Like a badge, a notification is a side effect: it must never be the reason a
/// comment fails to post. Fire and forget, logged on failure. The `owner<>$2`
/// clause is what keeps the bell from telling members about their own taps.
function notifyOwner(kind: NotificationKind, subjectId: string, actorId: string) {
  void db.query(
    `INSERT INTO member_notifications(user_id,kind,subject_id,last_actor_id)
     SELECT owner,$3,subject,$2 FROM (${NOTIFICATION_SUBJECTS[kind]}) s(owner,subject) WHERE owner<>$2
     ON CONFLICT(user_id,kind,subject_id) DO UPDATE SET last_actor_id=EXCLUDED.last_actor_id,updated_at=now(),read_at=NULL`,
    [subjectId, actorId, kind],
  ).catch((error) => app.log.warn({ err: error, kind }, 'Notification skipped'));
}

type NotificationRow = {
  id: string;
  // 'announcement' is not in NOTIFICATION_SUBJECTS: it has no owner to look up
  // and nothing a member did to trigger it, so it is written by the operator
  // route rather than by notifyOwner.
  kind: NotificationKind | 'announcement';
  subject_id: string;
  actor_name: string;
  actor_count: string;
  subject_title: string | null;
  // Only announcements carry one. Every other kind's sentence is composed in
  // the app out of the subject and the count; an announcement's sentence was
  // typed by a person and has to travel as it was written.
  subject_body: string | null;
  updated_at: Date;
  read_at: Date | null;
};

/**
 * The bell.
 *
 * Two things are computed here rather than stored. The number of people is
 * counted live in the table the act lives in, so unliking takes it back down
 * instead of leaving a permanent "3 kişi beğendi" behind. And the subject's
 * own title is read live too, so a notification whose post has since been
 * deleted - or whose listing was taken down - simply is not in the answer,
 * rather than being a line that opens onto nothing.
 *
 * The actor's name is sent only for comments and special requests. A comment is
 * public writing and carries its author's name anyway; a special request is a
 * message somebody wrote asking to be put in touch, so withholding their name
 * would make the notification useless. A like and a save are neither: the rest
 * of this service refuses to answer "who saved this listing" and this route is
 * not a back door into that question.
 */
app.get('/v1/notifications', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const rows = await db.query<NotificationRow>(
      `SELECT n.id,n.kind,n.subject_id,n.updated_at,n.read_at,
         COALESCE(cp.display_name,'TurkSquare üyesi') actor_name,
         CASE n.kind
           WHEN 'post_comment' THEN (SELECT count(DISTINCT c.author_id) FROM community_comments c WHERE c.post_id=n.subject_id AND c.deleted_at IS NULL AND c.moderation_state='active' AND c.author_id<>n.user_id)
           WHEN 'post_like' THEN (SELECT count(*) FROM post_reactions x WHERE x.post_id=n.subject_id AND x.kind='like' AND x.actor_id<>n.user_id)
           WHEN 'listing_save' THEN (SELECT count(*) FROM marketplace_listing_reactions x WHERE x.listing_id=n.subject_id AND x.kind='save' AND x.actor_id<>n.user_id)
           WHEN 'listing_like' THEN (SELECT count(*) FROM marketplace_listing_reactions x WHERE x.listing_id=n.subject_id AND x.kind='like' AND x.actor_id<>n.user_id)
           -- Only the ones still waiting. Once the owner has answered them all
           -- the line goes, because there is nothing left to act on.
           WHEN 'special_request' THEN (SELECT count(*) FROM post_special_requests r WHERE r.post_id=n.subject_id AND r.status='pending')
           -- Nobody "did" an announcement, so there is nothing to count. It is
           -- one because the filter below drops rows that count zero, and an
           -- announcement is always worth showing.
           WHEN 'announcement' THEN 1
           -- Ayni sebeple bir: destek yaniti sayilacak bir kalabalik degil,
           -- tek bir cevap. Talep silinmisse basligi da gelmez ve satir duser.
           WHEN 'support_answer' THEN 1
           -- Bir rozet bir kere kazanilir; sayilacak bir kalabaligi yok.
           WHEN 'badge_earned' THEN 1
           ELSE (SELECT count(*) FROM friend_requests f WHERE f.requester_id=n.subject_id AND f.addressee_id=n.user_id AND f.status='pending')
         END actor_count,
         CASE WHEN n.kind='announcement'
           THEN (SELECT a.body FROM member_announcements a WHERE a.id=n.subject_id)
           -- Yanitin kendisi zilde gorunuyor: uyeyi destek ekranina gonderip
           -- "bir cevap var" demek, cevabi bir tik arkasina saklamak olurdu.
           WHEN n.kind='support_answer'
           THEN (SELECT left(m.body,200) FROM support_messages m WHERE m.request_id=n.subject_id AND m.author_kind='staff' ORDER BY m.created_at DESC LIMIT 1)
           -- Rozetin kriteri zilde yaziyor: uyeye "bir rozet kazandin" deyip
           -- nedenini Yolculuk ekranina saklamak, haberi yarim vermek olurdu.
           WHEN n.kind='badge_earned'
           THEN (SELECT d.description FROM member_badges b JOIN badge_definitions d ON d.code=b.badge_code WHERE b.id=n.subject_id)
         END subject_body,
         CASE WHEN n.kind='announcement'
           THEN (SELECT a.title FROM member_announcements a WHERE a.id=n.subject_id)
           WHEN n.kind='support_answer'
           THEN (SELECT r.subject FROM support_requests r WHERE r.id=n.subject_id)
           WHEN n.kind='badge_earned'
           THEN (SELECT d.title FROM member_badges b JOIN badge_definitions d ON d.code=b.badge_code WHERE b.id=n.subject_id)
           WHEN n.kind IN ('post_comment','post_like','special_request')
           THEN (SELECT left(p.body,80) FROM community_posts p WHERE p.id=n.subject_id AND p.deleted_at IS NULL)
           -- A friend request has no title of its own; who is asking is the
           -- whole of it.
           WHEN n.kind='friend_request'
           THEN (SELECT f.display_name FROM community_profile_projection f WHERE f.user_id=n.subject_id)
           ELSE (SELECT l.title FROM marketplace_listings l WHERE l.id=n.subject_id AND l.status<>'draft')
         END subject_title
       FROM member_notifications n
       LEFT JOIN community_profile_projection cp ON cp.user_id=n.last_actor_id
       WHERE n.user_id=$1
         -- Kapatilmis turler burada eleniyor, yazilirken degil: kapali gecen
         -- surede olan biteni silmek yerine gizliyoruz, tekrar acan uye onlari
         -- goruyor. Satiri olmayan tur acik.
         AND NOT EXISTS (
           SELECT 1 FROM member_notification_preferences p
            WHERE p.user_id=n.user_id AND p.kind=n.kind AND p.enabled=false
         )
       ORDER BY n.updated_at DESC
       LIMIT 60`,
      [userId],
    );
    const data = rows.rows
      .filter((row) => row.subject_title !== null && Number(row.actor_count) > 0)
      .map((row) => ({
        id: row.id,
        kind: row.kind,
        subjectId: row.subject_id,
        subjectTitle: row.subject_title,
        body: row.subject_body,
        actorCount: Number(row.actor_count),
        actorName: row.kind === 'post_comment' || row.kind === 'special_request' || row.kind === 'friend_request' ? row.actor_name : null,
        createdAt: row.updated_at.toISOString(),
        isRead: row.read_at !== null,
      }));
    return { data };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'NOTIFICATIONS_UNAVAILABLE', message: 'Bildirimler yüklenemedi.' } });
  }
});

app.put('/v1/notifications/read-all', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    await db.query('UPDATE member_notifications SET read_at=now() WHERE user_id=$1 AND read_at IS NULL', [userId]);
    return reply.code(204).send();
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'NOTIFICATION_READ_FAILED', message: 'Bildirim güncellenemedi.' } });
  }
});

app.put('/v1/notifications/:id/read', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    // Scoped to the viewer, so an id guessed from somebody else's inbox marks
    // nothing. Already-read rows keep their first timestamp.
    await db.query('UPDATE member_notifications SET read_at=now() WHERE id=$1 AND user_id=$2 AND read_at IS NULL', [id, userId]);
    return reply.code(204).send();
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'NOTIFICATION_READ_FAILED', message: 'Bildirim güncellenemedi.' } });
  }
});

/// Zilde kapatilabilen turler.
///
/// `support_answer` ve `announcement` bilerek disarida: biri uyenin kendi
/// sordugu sorunun cevabi, digeri hesabini ilgilendiren duyuru. Ikisini de
/// kapatilabilir yapmak, sonra "haberim yoktu" demesine yol acardi.
const MUTABLE_NOTIFICATION_KINDS = [
  'post_comment',
  'post_like',
  'listing_save',
  'listing_like',
  'special_request',
  'friend_request',
] as const;

/// Govde yalnizca degisen turleri tasiyabilir, hepsini degil; ama tanimadigimiz
/// bir tur sessizce yutulmuyor. Yanlis yazilmis bir anahtari gormezden gelmek,
/// uyeye "kaydedildi" deyip hicbir sey kaydetmemek olurdu.
const notificationPreferencesSchema = z.object({
  preferences: z
    .object({
      post_comment: z.boolean(),
      post_like: z.boolean(),
      listing_save: z.boolean(),
      listing_like: z.boolean(),
      special_request: z.boolean(),
      friend_request: z.boolean(),
    })
    .partial()
    .strict(),
});

/// Uyenin bildirim tercihleri.
///
/// Satiri olmayan tur acik sayiliyor, o yuzden cevap once hepsini acik kurup
/// veritabanindan geleni uzerine yaziyor: ekran, kaydedilmis bir tercihle
/// varsayilan arasindaki farki bilmek zorunda kalmiyor.
app.get('/v1/notifications/preferences', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const rows = await db.query<{ kind: string; enabled: boolean }>(
      'SELECT kind,enabled FROM member_notification_preferences WHERE user_id=$1',
      [userId],
    );
    const preferences: Record<string, boolean> = {};
    for (const kind of MUTABLE_NOTIFICATION_KINDS) preferences[kind] = true;
    for (const row of rows.rows) {
      if (row.kind in preferences) preferences[row.kind] = row.enabled;
    }
    return { data: { preferences } };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'NOTIFICATION_PREFERENCES_UNAVAILABLE', message: 'Bildirim tercihleri yüklenemedi.' } });
  }
});

/// Tercihleri kaydet.
///
/// Govde yalnizca degisen turleri tasiyabilir; gonderilmeyen tur oldugu gibi
/// kaliyor. Tek tek UPSERT, cunku iki cihazdan ayni anda yapilan iki degisiklik
/// birbirini silmemeli - "hepsini sil, yenisini yaz" bicimi bunu yapardi.
app.put('/v1/notifications/preferences', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const body = notificationPreferencesSchema.parse(request.body ?? {});
    const entries = Object.entries(body.preferences);
    for (const [kind, enabled] of entries) {
      await db.query(
        `INSERT INTO member_notification_preferences (user_id,kind,enabled)
         VALUES ($1,$2,$3)
         ON CONFLICT (user_id,kind) DO UPDATE SET enabled=EXCLUDED.enabled, updated_at=now()`,
        [userId, kind, enabled],
      );
    }
    const rows = await db.query<{ kind: string; enabled: boolean }>(
      'SELECT kind,enabled FROM member_notification_preferences WHERE user_id=$1',
      [userId],
    );
    const preferences: Record<string, boolean> = {};
    for (const kind of MUTABLE_NOTIFICATION_KINDS) preferences[kind] = true;
    for (const row of rows.rows) {
      if (row.kind in preferences) preferences[row.kind] = row.enabled;
    }
    return { data: { preferences } };
  } catch (error) {
    if ((error as Error).message === 'UNAUTHORIZED') {
      return reply.code(401).send({ error: { code: 'UNAUTHORIZED', message: 'Oturum gerekli.' } });
    }
    return reply.code(400).send({ error: { code: 'NOTIFICATION_PREFERENCES_INVALID', message: 'Bildirim tercihleri kaydedilemedi.' } });
  }
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
  if (viewerId === ownerId) {
    return { self: true, blocked: false, full: true, viewerFollows: false, followsViewer: false };
  }
  const row = await db.query<{ blocked: boolean; friend: boolean; visibility: string; viewer_follows: boolean; follows_viewer: boolean }>(
    `SELECT
       EXISTS(SELECT 1 FROM user_blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=$2) OR (b.blocker_id=$2 AND b.blocked_id=$1)) blocked,
       EXISTS(SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=$2 AND r.relationship='friend' AND r.active) friend,
       COALESCE((SELECT visibility FROM member_profiles WHERE user_id=$2),'friends_only') visibility,
       EXISTS(SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$1 AND r.subject_id=$2 AND r.active) viewer_follows,
       EXISTS(SELECT 1 FROM relationship_projection r WHERE r.viewer_id=$2 AND r.subject_id=$1 AND r.active) follows_viewer`,
    [viewerId, ownerId],
  );
  const access = row.rows[0]!;
  return {
    self: false,
    blocked: access.blocked,
    full: !access.blocked && (access.visibility === 'public' || access.friend),
    viewerFollows: access.viewer_follows,
    followsViewer: access.follows_viewer,
  };
}

type ProfileRow = {
  user_id: string; display_name: string; username: string | null; city: string | null; region_code: string | null; interests: string[];
  born_in_us: boolean; arrived_month: number | null; arrived_year: number | null; origin_country: string | null;
  origin_city: string | null; primary_intent: string | null; bio: string | null; visibility: string | null;
  showcased_badges: string[] | null; avatar_url: string | null; identity_verified: boolean;
  post_count: string; friend_count: string; follower_count: string; following_count: string;
  points: number | null; level: number | null; badge_count: number | null;
  streak_days: number | null; level_title: string | null; next_level_points: number | null;
};

const PROFILE_SELECT = `
  SELECT p.user_id,p.display_name,p.city,p.region_code,p.interests,
         p.born_in_us,p.arrived_month,p.arrived_year,p.origin_country,p.origin_city,p.primary_intent,
         mp.bio,mp.visibility,mp.showcased_badges,mp.username,
         (SELECT m.safe_url FROM media_assets m WHERE m.id=mp.avatar_media_id AND m.status='ready') avatar_url,
         COALESCE(mc.identity_verified,false) identity_verified,
         (SELECT count(*) FROM community_posts cp WHERE cp.author_id=p.user_id AND cp.deleted_at IS NULL AND cp.archived_at IS NULL AND cp.moderation_state='active') post_count,
         (SELECT count(*) FROM relationship_projection r WHERE r.viewer_id=p.user_id AND r.relationship='friend' AND r.active) friend_count,
         -- Arkadaşlık iki yönlü yazılıyor, yani her arkadaş aynı zamanda hem
         -- takipçi hem takip edilen. Sayaçlar bu yüzden ilişki tipine göre
         -- ayrılmıyor: "beni takip edenler" listesinde arkadaşının çıkmaması
         -- üyeye yanlış bir sayı gösterirdi.
         -- count(DISTINCT ...): aynı kişinin hem 'following' hem 'friend'
         -- satırı olabiliyor ve düz bir count onu iki kişi sayardı.
         (SELECT count(DISTINCT r.viewer_id) FROM relationship_projection r WHERE r.subject_id=p.user_id AND r.active) follower_count,
         (SELECT count(DISTINCT r.subject_id) FROM relationship_projection r WHERE r.viewer_id=p.user_id AND r.active) following_count,
         ms.points,ms.level,ms.badge_count,ms.streak_days,
         (SELECT l.title FROM journey_levels l WHERE l.level=COALESCE(ms.level,1)) level_title,
         (SELECT min(l.min_points) FROM journey_levels l WHERE l.min_points>COALESCE(ms.points,0)) next_level_points
    FROM community_profile_projection p
    LEFT JOIN member_profiles mp ON mp.user_id=p.user_id
    LEFT JOIN member_capabilities mc ON mc.user_id=p.user_id
    LEFT JOIN member_scores ms ON ms.user_id=p.user_id`;

async function toProfileDto(
  row: ProfileRow,
  access: { self: boolean; full: boolean; viewerFollows?: boolean; followsViewer?: boolean },
) {
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
    // Handle, kilitli profilde de duruyor. Zaten bir adres: gizlemek profilin
    // paylaşılabilir olmasını engeller, kimseyi korumaz.
    username: row.username,
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
    // Kilitli profil bir duvar değil bir kapı: üyenin kendini anlattığı iki
    // satır ve vitrine koyduğu rozetler herkese açık kalıyor, çünkü karşıdaki
    // kişi arkadaşlık isteği göndermeden önce kime istek gönderdiğini
    // bilebilmeli. Nereden geldiği, ne zaman geldiği ve neyle ilgilendiği
    // kapalı kalmaya devam ediyor.
    bio: row.bio ?? '',
    avatarUrl: row.avatar_url ? await mediaObjectUrl(row.avatar_url) : null,
    visibility: row.visibility ?? 'friends_only',
    identityVerified: row.identity_verified,
    showcasedBadges: badges.rows.map((badge) => ({ code: badge.code, title: badge.title, icon: badge.icon, tier: badge.tier })),
    counts: {
      posts: Number(row.post_count),
      friends: Number(row.friend_count),
      followers: Number(row.follower_count),
      following: Number(row.following_count),
      badges: row.badge_count ?? 0,
    },
    viewerFollows: access.viewerFollows ?? false,
    followsViewer: access.followsViewer ?? false,
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
    // Kapali hesap da 404: "bu hesap donduruldu" demek, kimin ara verdigini
    // herkese duyurmak olurdu. Uyenin kendisi kendi profilini gormeye devam
    // ediyor - silmeden once ne biraktigina bakabilmeli.
    const row = await db.query<ProfileRow>(
      `${PROFILE_SELECT} WHERE p.user_id=$1 AND (p.user_id=$2 OR p.closed_at IS NULL)`,
      [ownerId, viewerId],
    );
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
      `INSERT INTO member_profiles(user_id,bio,avatar_media_id,visibility,showcased_badges,username)
       VALUES($1,$2,$3,COALESCE($4,'friends_only'),COALESCE($5::text[],'{}'),$8)
       ON CONFLICT(user_id) DO UPDATE SET
         bio=CASE WHEN $6::boolean THEN $2 ELSE member_profiles.bio END,
         avatar_media_id=CASE WHEN $7::boolean THEN $3 ELSE member_profiles.avatar_media_id END,
         visibility=COALESCE($4,member_profiles.visibility),
         showcased_badges=COALESCE($5::text[],member_profiles.showcased_badges),
         username=CASE WHEN $9::boolean THEN $8 ELSE member_profiles.username END,
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
        input.username ?? null,
        Object.prototype.hasOwnProperty.call(request.body ?? {}, 'username'),
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
    // Müsaitlik denetimi ile bu INSERT arasında saniyeler var; o aralıkta aynı
    // adı başkası alabilir. Son sözü indeks söylüyor ve üye "bu ad az önce
    // alındı" cevabını alıyor, "profil güncellenemedi" değil.
    if ((error as { code?: string }).code === '23505') {
      return reply.code(409).send({ error: { code: 'USERNAME_TAKEN', message: 'Bu kullanıcı adı alınmış. Başka bir tane dene.' } });
    }
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'PROFILE_UPDATE_FAILED', message: 'Profil güncellenemedi.' } });
  } finally {
    client.release();
  }
});

/// "Bu kullanıcı adı boşta mı?" - üye yazarken cevap veren uç.
///
/// Nihai karar değil, nezaket. Kaydetme anında indeks yeniden karar veriyor;
/// burada verilen "müsait" cevabı yalnızca o andaki durumu anlatıyor. Kural
/// ihlali ile doluluk ayrı ayrı dönüyor: "kısa" ile "alınmış" aynı ekranda aynı
/// kırmızıyı gösterirse üye neyi düzelteceğini bilemez.
app.get('/v1/community/profiles/username-available', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const raw = z.string().trim().max(40).parse((request.query as { username?: string }).username ?? '').toLowerCase();
    if (raw.length < 3 || raw.length > 24) {
      return { data: { available: false, reason: 'length', message: 'Kullanıcı adı 3-24 karakter olmalı.' } };
    }
    if (!USERNAME_PATTERN.test(raw) || raw.includes('..')) {
      return { data: { available: false, reason: 'format', message: 'Yalnızca küçük harf, rakam, alt çizgi ve nokta kullanabilirsin.' } };
    }
    if (RESERVED_USERNAMES.has(raw)) {
      return { data: { available: false, reason: 'reserved', message: 'Bu ad kullanıma kapalı.' } };
    }
    const taken = await db.query('SELECT 1 FROM member_profiles WHERE username=$1 AND user_id<>$2', [raw, userId]);
    return taken.rowCount
      ? { data: { available: false, reason: 'taken', message: 'Bu kullanıcı adı alınmış.' } }
      : { data: { available: true, reason: null, message: 'Bu kullanıcı adı senin olabilir.' } };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'USERNAME_CHECK_FAILED', message: 'Kullanıcı adı denetlenemedi.' } });
  }
});

// The grid behind the "Paylasimlar" tab. Archived posts are visible to their
// author and to nobody else, which is the difference between archiving and
// deleting: the member keeps them, the app stops showing them.
/// Profil ızgarasının imleci. Akışınkinden ayrı, çünkü bu liste önce
/// sabitlenmişleri sıralıyor ve devam edilecek yer bunu da bilmek zorunda.
const profileCursorEncode = (row: { pinned_at: Date | null; created_at: Date; id: string }) =>
  Buffer.from(`${row.pinned_at ? 1 : 0}|${row.created_at.toISOString()}|${row.id}`).toString('base64url');

const profileCursorDecode = (cursor?: string) => {
  if (!cursor) return null;
  try {
    const [pinned, createdAt, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|');
    if (pinned === undefined || !createdAt || !id) throw Error();
    return { pinned: pinned === '1', createdAt, id };
  } catch {
    throw Object.assign(new Error('Invalid cursor'), { statusCode: 400 });
  }
};

/// Aynı anda kaç paylaşım sabitlenebilir. Instagram'da üç; buradaki sebep de
/// aynı: ızgaranın ilk satırı bir seçki, ikinci bir akış değil.
const MAX_PINNED_POSTS = 3;

const postSettingsBody = z.object({
  pinned: z.boolean().optional(),
  commentsEnabled: z.boolean().optional(),
}).refine((value) => value.pinned !== undefined || value.commentsEnabled !== undefined, {
  message: 'Değiştirilecek bir ayar yok.',
});

/// Sabitleme ve yorumlara kapatma tek uçta: ikisi de paylaşımın sahibine ait
/// ayarlar ve ikisi de aynı sahiplik denetiminden geçiyor.
app.patch('/v1/community/posts/:id/settings', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = postSettingsBody.parse(request.body);

    const owned = await db.query<{ pinned_at: Date | null; comments_enabled: boolean }>(
      'SELECT pinned_at,comments_enabled FROM community_posts WHERE id=$1 AND author_id=$2 AND deleted_at IS NULL',
      [id, userId],
    );
    if (!owned.rows[0]) return reply.code(404).send({ error: { code: 'POST_NOT_FOUND', message: 'Paylaşım bulunamadı.' } });

    if (input.pinned === true && owned.rows[0].pinned_at === null) {
      const pinned = await db.query<{ count: string }>(
        'SELECT count(*) FROM community_posts WHERE author_id=$1 AND pinned_at IS NOT NULL AND deleted_at IS NULL',
        [userId],
      );
      // Sessizce en eskisini düşürmek yerine hayır deniyor: üye hangisinden
      // vazgeçtiğini kendi seçmeli.
      if (Number(pinned.rows[0]?.count ?? 0) >= MAX_PINNED_POSTS) {
        return reply.code(409).send({
          error: {
            code: 'PIN_LIMIT_REACHED',
            message: `En fazla ${MAX_PINNED_POSTS} paylaşım sabitlenebilir. Önce birinin sabitini kaldır.`,
          },
        });
      }
    }

    const updated = await db.query<{ pinned_at: Date | null; comments_enabled: boolean }>(
      `UPDATE community_posts
          SET pinned_at=CASE WHEN $3::boolean IS NULL THEN pinned_at WHEN $3::boolean THEN COALESCE(pinned_at,now()) ELSE NULL END,
              comments_enabled=COALESCE($4::boolean,comments_enabled)
        WHERE id=$1 AND author_id=$2 AND deleted_at IS NULL
        RETURNING pinned_at,comments_enabled`,
      [id, userId, input.pinned ?? null, input.commentsEnabled ?? null],
    );
    const row = updated.rows[0];
    if (!row) return reply.code(404).send({ error: { code: 'POST_NOT_FOUND', message: 'Paylaşım bulunamadı.' } });
    // Arşivlenmiş bir paylaşım sabitlenmiş kalabilir; ızgarada görünmediği için
    // bir zararı yok, arşivden çıktığında yine başa gelir.
    return { data: { pinned: row.pinned_at !== null, commentsEnabled: row.comments_enabled } };
  } catch (error) {
    return reply.code((error as { statusCode?: number }).statusCode ?? ((error as Error).message === 'UNAUTHORIZED' ? 401 : 400)).send({
      error: { code: 'POST_SETTINGS_FAILED', message: 'Paylaşım ayarı değiştirilemedi.' },
    });
  }
});

app.get('/v1/community/profiles/:userId/posts', async (request, reply) => {
  try {
    const viewerId = await viewer(request.headers);
    const ownerId = z.string().uuid().parse((request.params as { userId: string }).userId);
    const input = profilePostsQuery.parse(request.query);
    const access = await profileAccess(viewerId, ownerId);
    if (access.blocked) return reply.code(404).send({ error: { code: 'PROFILE_NOT_FOUND', message: 'Profil bulunamadı.' } });
    if (input.state === 'archived' && !access.self) return reply.code(403).send({ error: { code: 'ARCHIVE_IS_PRIVATE', message: 'Arşiv yalnızca sahibine açıktır.' } });
    if (!access.full) return { data: [], meta: { nextCursor: null, locked: true } };

    const cursor = profileCursorDecode(input.cursor);
    const params: unknown[] = [ownerId, viewerId];
    let where = `p.author_id=$1 AND p.deleted_at IS NULL AND p.moderation_state='active' AND p.archived_at IS ${input.state === 'archived' ? 'NOT NULL' : 'NULL'}`;
    if (!access.self) where += " AND p.visibility='public'";
    // İmleç sabitlik bayrağını da taşıyor: sıralama ondan başladığı için,
    // taşımasaydı sabitlenmiş paylaşım ikinci sayfanın da başında çıkardı.
    if (cursor) { params.push(cursor.pinned, cursor.createdAt, cursor.id); where += ` AND (p.pinned_at IS NOT NULL,p.created_at,p.id) < ($${params.length - 2}::boolean,$${params.length - 1}::timestamptz,$${params.length}::uuid)`; }
    params.push(input.limit + 1);
    const rows = await db.query<{ id: string; created_at: Date; body: string; location_label: string | null; visibility: string; likes: string; comments: string; is_liked: boolean; thumbnail_url: string | null; safe_url: string | null; pinned_at: Date | null; comments_enabled: boolean }>(
      `SELECT p.id,p.created_at,p.body,p.location_label,p.visibility,p.pinned_at,p.comments_enabled,
              (SELECT count(*) FROM post_reactions x WHERE x.post_id=p.id AND x.kind='like') likes,
              (SELECT count(*) FROM community_comments c WHERE c.post_id=p.id AND c.deleted_at IS NULL AND c.moderation_state='active') comments,
              EXISTS(SELECT 1 FROM post_reactions x WHERE x.post_id=p.id AND x.actor_id=$2 AND x.kind='like') is_liked,
              (SELECT m.thumbnail_url FROM post_media_refs r JOIN media_assets m ON m.id=r.media_id WHERE r.post_id=p.id AND m.status='ready' ORDER BY r.ordinal LIMIT 1) thumbnail_url,
              (SELECT m.safe_url FROM post_media_refs r JOIN media_assets m ON m.id=r.media_id WHERE r.post_id=p.id AND m.status='ready' ORDER BY r.ordinal LIMIT 1) safe_url
         FROM community_posts p
        WHERE ${where}
        ORDER BY (p.pinned_at IS NOT NULL) DESC,p.created_at DESC,p.id DESC
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
      pinned: post.pinned_at !== null,
      commentsEnabled: post.comments_enabled,
      thumbnailUrl: post.thumbnail_url ? await mediaObjectUrl(post.thumbnail_url) : post.safe_url ? await mediaObjectUrl(post.safe_url) : null,
    })));
    return { data, meta: { nextCursor: rows.rows.length > input.limit ? profileCursorEncode(page[page.length - 1]!) : null, locked: false } };
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
  // Haber akışta da paylaşılsın mı. Kararı editör veriyor: her haberin akışa
  // düşmesi akışı bültene çevirirdi, hiçbirinin düşmemesi ise haberi yalnızca
  // Haber Merkezi'ni açanın gördüğü bir yere hapsediyordu.
  shareToFeed: z.boolean().default(false),
  reason: z.string().trim().min(5).max(500),
  idempotencyKey: z.string().uuid(),
});

/* --- Haber akışta -----------------------------------------------------------
 *
 * Akıştaki kart haberin bir izdüşümü (036): metni özet, görseli kapak, beğenisi
 * ve yorumu haberin kendisi. Buradaki iki işlev de o izdüşümü kuruyor ya da
 * kaldırıyor; hiçbiri haberin kendisine dokunmuyor.
 */
async function shareArticleToFeed(client: pg.PoolClient, articleId: string) {
  // Tarih: geçmişte yayınlanmış bir haber bugün akışa çıkarıldığında akışın
  // dibine değil başına düşmeli. İleri tarihli bir haber ise kendi tarihini
  // koruyor - o güne kadar akışta zaten görünmüyor.
  const inserted = await client.query<{ id: string }>(
    `INSERT INTO community_posts(author_id,body,visibility,comments_enabled,region_code,news_article_id,created_at)
     SELECT a.author_id,a.summary,'public',a.comments_enabled,a.region_code,a.id,GREATEST(a.published_at,now())
       FROM news_articles a WHERE a.id=$1 AND a.deleted_at IS NULL
     ON CONFLICT (news_article_id) WHERE news_article_id IS NOT NULL DO NOTHING
     RETURNING id`,
    [articleId],
  );
  const postId = inserted.rows[0]?.id;
  if (!postId) return false;
  await client.query(
    `INSERT INTO post_media_refs(post_id,media_id,ordinal)
     SELECT $1,a.hero_media_id,0 FROM news_articles a WHERE a.id=$2 AND a.hero_media_id IS NOT NULL
     ON CONFLICT DO NOTHING`,
    [postId, articleId],
  );
  return true;
}

/// Yumuşak silme değil, satırın kaldırılması. Kaldırılan şey bir üyenin yazdığı
/// içerik değil, bir gösterim kararı; beğeniler ve yorumlar haberin kendi
/// tablolarında duruyor ve haber ekranında olduğu gibi kalıyor.
async function removeArticleFromFeed(client: pg.PoolClient, articleId: string) {
  const removed = await client.query('DELETE FROM community_posts WHERE news_article_id=$1', [articleId]);
  return (removed.rowCount ?? 0) > 0;
}

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

/// Ana sayfadaki manşet şeridi: aynı haberler, çıktıkları saate göre değil
/// editörün verdiği sıraya göre.
///
/// Sorgu eskiden `headline_rank IS NOT NULL` ile filtreliyordu. Sıra vermek
/// isteğe bağlı olduğu için pratikte şu oluyordu: panelden haber yayınlanıyor,
/// Haber Merkezi listesine düşüyor, ana sayfada hiçbir şey çıkmıyor ve aradaki
/// farkın tek açıklaması formdaki küçük bir ipucu oluyordu. Filtre yerine
/// sıralama: sıra verilmiş haberler önde, arkalarında en yeniler. Editörün
/// seçimi hâlâ üstte duruyor ama yayında haber varken şerit boş kalmıyor.
app.get('/v1/community/news/headlines', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const input = newsHeadlineQuery.parse(request.query);
    const rows = await db.query<NewsRow>(
      `${newsSelect()} WHERE ${NEWS_VISIBLE} ORDER BY (a.headline_rank IS NULL),a.headline_rank ASC,a.published_at DESC LIMIT $2`,
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
const newsCommentSelect = (viewerParam: string) => `
  SELECT c.id,c.author_id,c.parent_id,c.body,c.created_at,
         COALESCE(p.display_name,'TurkSquare üyesi') author_name,
         (SELECT count(*) FROM news_comment_reactions x WHERE x.comment_id=c.id) like_count,
         EXISTS(SELECT 1 FROM news_comment_reactions x WHERE x.comment_id=c.id AND x.actor_id=${viewerParam}) is_liked
    FROM news_comments c
    LEFT JOIN community_profile_projection p ON p.user_id=c.author_id`;

type NewsCommentRow = { id: string; author_id: string; parent_id: string | null; body: string; created_at: Date; author_name: string; like_count: string; is_liked: boolean };
const newsCommentJson = (row: NewsCommentRow) => ({
  id: row.id,
  authorId: row.author_id,
  authorName: row.author_name,
  parentId: row.parent_id,
  body: row.body,
  createdAt: row.created_at.toISOString(),
  likes: Number(row.like_count),
  isLiked: row.is_liked,
});

app.get('/v1/community/news/:id/comments', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const rows = await db.query<NewsCommentRow>(
      `${newsCommentSelect('$2')} WHERE c.article_id=$1 AND c.deleted_at IS NULL AND c.moderation_state='active' ORDER BY c.created_at ASC LIMIT 100`,
      [id, userId],
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
    const row = await db.query<NewsCommentRow>(`${newsCommentSelect('$2')} WHERE c.id=$1`, [inserted.rows[0]!.id, userId]);
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

// The same heart, on the other comment list. A published article is readable by
// everybody, so there is no visibility question here - only whether the comment
// is still standing.
app.put('/v1/community/news/comments/:id/likes', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const restricted = await activeRestriction(userId);
    if (restricted) return reply.code(403).send(restrictionError(restricted));
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = commentLikeBody.parse(request.body);
    const readable = await db.query(
      `SELECT 1 FROM news_comments c JOIN news_articles a ON a.id=c.article_id
        WHERE c.id=$1 AND c.deleted_at IS NULL AND c.moderation_state='active' AND ${NEWS_VISIBLE}`,
      [id],
    );
    if (!readable.rows[0]) return reply.code(404).send({ error: { code: 'COMMENT_NOT_FOUND', message: 'Yorum bulunamadı.' } });
    if (input.enabled) await db.query('INSERT INTO news_comment_reactions(comment_id,actor_id) VALUES($1,$2) ON CONFLICT DO NOTHING', [id, userId]);
    else await db.query('DELETE FROM news_comment_reactions WHERE comment_id=$1 AND actor_id=$2', [id, userId]);
    const tally = await db.query<{ like_count: string }>('SELECT count(*) like_count FROM news_comment_reactions WHERE comment_id=$1', [id]);
    return { data: { likes: Number(tally.rows[0]!.like_count), isLiked: input.enabled } };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400).send({ error: { code: 'NEWS_COMMENT_LIKE_FAILED', message: 'Beğenin kaydedilemedi.' } });
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
      // Aynı işlemin içinde: akışa çıkması istenen bir haberin yayınlanıp
      // akışta görünmemesi diye bir ara durum olmamalı.
      if (input.shareToFeed) await shareArticleToFeed(client, article.rows[0]!.id);
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

/// What the console shows an editor after they publish.
///
/// The public listing is not usable here: it hides anything scheduled for later
/// and carries the viewer's own reaction, which an operator does not have. This
/// one shows scheduled pieces too - an article dated for tomorrow is invisible
/// everywhere else, so the only way to notice a wrong date was to wait for it.
///
/// Read-only, and it never returns the body: the list is for deciding which
/// piece to act on, not for reading them in the panel.
const gateworkNewsQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(50),
  category: z.enum(newsCategories).optional(),
});

app.get('/v1/internal/gatework/news', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor', 'moderator', 'auditor']);
    const input = gateworkNewsQuery.parse(request.query);
    const rows = await db.query<{
      id: string; title: string; summary: string; category: string; author_id: string; author_name: string;
      region_code: string | null; published_at: Date; headline_rank: number | null; comments_enabled: boolean;
      hero_url: string | null; comment_count: string; reaction_count: string; in_feed: boolean;
    }>(
      `SELECT a.id,a.title,a.summary,a.category,a.author_id,a.author_name,a.region_code,a.published_at,
              a.headline_rank,a.comments_enabled,m.safe_url hero_url,
              EXISTS(SELECT 1 FROM community_posts p WHERE p.news_article_id=a.id) in_feed,
              (SELECT count(*) FROM news_comments c WHERE c.article_id=a.id AND c.deleted_at IS NULL AND c.moderation_state='active') comment_count,
              (SELECT count(*) FROM news_reactions r WHERE r.article_id=a.id) reaction_count
         FROM news_articles a
         LEFT JOIN media_assets m ON m.id=a.hero_media_id AND m.status='ready'
        WHERE a.deleted_at IS NULL AND ($2::text IS NULL OR a.category=$2)
        ORDER BY a.published_at DESC, a.id DESC
        LIMIT $1`,
      [input.limit, input.category ?? null],
    );
    return {
      data: await Promise.all(rows.rows.map(async (row) => ({
        id: row.id,
        title: row.title,
        summary: row.summary,
        category: row.category,
        authorId: row.author_id,
        authorName: row.author_name,
        regionCode: row.region_code,
        publishedAt: row.published_at.toISOString(),
        // The distinction the public list erases: written, but not yet readable.
        live: row.published_at.getTime() <= Date.now(),
        headlineRank: row.headline_rank,
        commentsEnabled: row.comments_enabled,
        imageUrl: row.hero_url ? await mediaObjectUrl(row.hero_url) : null,
        commentCount: Number(row.comment_count),
        reactionCount: Number(row.reaction_count),
        // Akışta da duruyor mu. Panelin bunu okuyamadığı bir dünyada düğme
        // "aç/kapat" değil "bir şey yap" olurdu; editör hangi haberin akışta
        // olduğunu ancak uygulamayı açarak görebilirdi.
        inFeed: row.in_feed,
      }))),
    };
  } catch (error) {
    return reply.code(error instanceof Error && error.message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'GATEWORK_NEWS_UNAVAILABLE', message: 'Haber listesi okunamadı.' } });
  }
});

/// Hangi haberin akışta paylaşılacağı kararı.
///
/// Yayın anında da verilebiliyor (`shareToFeed`), ama karar sonradan da
/// değişebilmeli: bir haber gün içinde önem kazanır, bir başkası akışta yer
/// kaplamayı hak etmez. Kapatmak haberi geri çekmiyor - Haber Merkezi'nde
/// okunmaya, beğenilmeye ve yorumlanmaya devam ediyor.
const gateworkNewsFeedBody = z.object({
  enabled: z.boolean(),
  reason: z.string().trim().min(5).max(500),
});

app.put('/v1/internal/gatework/news/:id/feed', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = gateworkNewsFeedBody.parse(request.body);
    await client.query('BEGIN');
    const article = await client.query('SELECT 1 FROM news_articles WHERE id=$1 AND deleted_at IS NULL', [id]);
    if (!article.rows[0]) {
      await client.query('ROLLBACK');
      return reply.code(404).send({ error: { code: 'NEWS_NOT_FOUND', message: 'Haber bulunamadı.' } });
    }
    const changed = input.enabled ? await shareArticleToFeed(client, id) : await removeArticleFromFeed(client, id);
    await auditGateworkOperation({
      actorId: actor.actorId, roles: actor.roles,
      action: input.enabled ? 'news_article.feed_share' : 'news_article.feed_remove',
      targetType: 'news_article', targetId: id, reason: input.reason, requestId: request.id,
      rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded',
    });
    await client.query('COMMIT');
    // `changed` false ise haber zaten istenen durumdaydı; panel iki sekmede
    // açıksa ikinci tık hata değil, teyit.
    return { data: { inFeed: input.enabled, changed } };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    const message = (error as Error).message;
    return reply.code(message === 'FORBIDDEN' ? 403 : message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'GATEWORK_NEWS_FEED_REJECTED', message: 'Akış kararı kaydedilemedi.' } });
  } finally {
    client.release();
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
// The whole running order arrives at once rather than one "move up" per card.
// Two operators dragging at the same time then overwrite each other's list
// instead of interleaving into an order neither of them chose.
const promotionOrderBody = z.object({
  ids: z.array(z.string().uuid()).min(1).max(50),
  reason: z.string().trim().min(5).max(500),
});

type PromotionRow = {
  id: string; owner_id: string; placement: string; title: string; subtitle: string | null;
  media_url: string | null; target_kind: string | null; target_value: string | null;
  region_code: string | null; city: string | null; starts_at: Date; ends_at: Date;
  status: string; decision_reason: string | null; request_note?: string | null;
  created_at: Date; display_order: number | null; official: boolean;
  owner_name?: string; impressions?: string; clicks?: string;
};

const PROMOTION_SELECT = `
  SELECT p.id,p.owner_id,p.placement,p.title,p.subtitle,m.safe_url media_url,p.target_kind,p.target_value,
         p.region_code,p.city,p.starts_at,p.ends_at,p.status,p.decision_reason,p.request_note,p.created_at,
         p.display_order,
         -- Platformun kendi karti mi, birinin yerlestirdigi tanitim mi. Uygulama
         -- ikisini ayni "Sponsorlu" etiketiyle gosteriyordu; kimsenin para
         -- odemedigi bir karta reklam demek uyeye yanlis bilgi vermek.
         EXISTS(SELECT 1 FROM community_system_accounts o WHERE o.user_id=p.owner_id AND o.role='official') official
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
  // NULL is "not hand-ordered", which is a different thing from "first".
  displayOrder: row.display_order,
  // True when the card belongs to the platform itself. The app labels those as
  // TurkSquare's own rather than "Sponsorlu".
  official: row.official === true,
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
        -- Hand order first when an operator has set one; everything else keeps
        -- the newest-first behaviour it had before the column existed.
        ORDER BY p.display_order ASC NULLS LAST,p.starts_at DESC,p.id DESC LIMIT 20`,
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
      // A pending queue is worked oldest-first, but an approved list is the
      // running order - so it is read in the order the home screen will use it.
      `${PROMOTION_SELECT} WHERE p.status=$1
        ORDER BY ${input.status === 'approved' ? 'p.display_order ASC NULLS LAST,p.starts_at DESC,p.id DESC' : 'p.created_at ASC'}
        LIMIT $2 OFFSET $3`,
      [input.status, input.limit, input.offset],
    );
    const ids = rows.rows.map((row) => row.id);
    const [owners, totals] = await Promise.all([
      db.query<{ user_id: string; display_name: string }>(
        'SELECT user_id,display_name FROM community_profile_projection WHERE user_id=ANY($1::uuid[])',
        [rows.rows.map((row) => row.owner_id)],
      ),
      // These counters already existed and the member could see their own; the
      // operator deciding whether to keep a placement running could not. Without
      // them "is this working" was answered by opinion.
      db.query<{ promotion_id: string; impressions: string; clicks: string }>(
        `SELECT promotion_id,sum(impressions) impressions,sum(clicks) clicks
           FROM promotion_impressions WHERE promotion_id=ANY($1::uuid[]) GROUP BY promotion_id`,
        [ids],
      ),
    ]);
    const names = new Map(owners.rows.map((row) => [row.user_id, row.display_name]));
    const counters = new Map(totals.rows.map((row) => [row.promotion_id, row]));
    return {
      data: await Promise.all(rows.rows.map(async (row) => ({
        ...await promotionJson(row),
        ownerId: row.owner_id,
        ownerName: names.get(row.owner_id) ?? 'TurkSquare üyesi',
        requestNote: row.request_note ?? null,
        impressions: Number(counters.get(row.id)?.impressions ?? 0),
        clicks: Number(counters.get(row.id)?.clicks ?? 0),
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

/// Hand ordering the live cards. Only approved rows can be ordered: a pending
/// request has no place on the home screen, so dragging one into the running
/// list must fail loudly rather than quietly place it.
app.put('/v1/internal/gatework/promotions/order', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const input = promotionOrderBody.parse(request.body);
    // A repeated id would give one card two positions and steal one from
    // another card, and the row count check below would still pass.
    if (new Set(input.ids).size !== input.ids.length) throw Error('DUPLICATE_ID');
    await client.query('BEGIN');
    // Written as one statement, so the home screen cannot read a half-applied
    // order in which two cards share a position.
    const updated = await client.query(
      `UPDATE promotions p SET display_order=v.rank,updated_at=now()
         FROM unnest($1::uuid[]) WITH ORDINALITY AS v(id,rank)
        WHERE p.id=v.id AND p.status='approved'`,
      [input.ids],
    );
    // The console sends the list it was showing. A short count means that list
    // is stale - something ended or was pulled while it was open - and applying
    // the rest would order a screen the operator never actually saw.
    if (updated.rowCount !== input.ids.length) {
      await client.query('ROLLBACK');
      return reply.code(409).send({ error: { code: 'PROMOTION_ORDER_STALE', message: 'Liste değişmiş. Sayfayı yenileyip sıralamayı tekrar kaydet.' } });
    }
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'promotion.reorder', targetType: 'promotion', targetId: input.ids[0]!, reason: `${input.reason} (${input.ids.length} kart)`, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    await client.query('COMMIT');
    return { data: { ordered: updated.rowCount } };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    const message = (error as Error).message;
    return reply.code(message === 'FORBIDDEN' ? 403 : message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'PROMOTION_ORDER_FAILED', message: 'Sıralama kaydedilemedi.' } });
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

// The whole order at once, like the promotion one: setting ordinals one row at
// a time leaves the list briefly holding two categories with the same number,
// and the tie is broken by title - so the forum reshuffles itself mid-edit.
const gateworkForumCategoryOrder = z.object({
  ids: z.array(z.string().uuid()).min(1).max(60),
  reason: z.string().trim().min(5).max(500),
});

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

/// The order the sections appear in, for members and here. Both the app's list
/// and the console's read ORDER BY ordinal, so this is the one write that
/// decides what people see first when they open the forum.
app.put('/v1/internal/gatework/forum/categories/order', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, FORUM_EDIT_ROLES);
    const input = gateworkForumCategoryOrder.parse(request.body);
    // A repeated id would give one category two positions and steal one from
    // another, and the row count check below would still pass.
    if (new Set(input.ids).size !== input.ids.length) throw Error('DUPLICATE_ID');
    await client.query('BEGIN');
    const updated = await client.query(
      `UPDATE forum_categories c SET ordinal=v.rank
         FROM unnest($1::uuid[]) WITH ORDINALITY AS v(id,rank)
        WHERE c.id=v.id`,
      [input.ids],
    );
    // A short count means the console is ordering a list that no longer
    // matches the table; applying the rest would order a forum nobody saw.
    if (updated.rowCount !== input.ids.length) {
      await client.query('ROLLBACK');
      return reply.code(409).send({ error: { code: 'FORUM_ORDER_STALE', message: 'Kategori listesi değişmiş. Sayfayı yenileyip sıralamayı tekrar kaydet.' } });
    }
    await auditGateworkOperation({
      actorId: actor.actorId, roles: actor.roles, action: 'forum_category.reorder', targetType: 'forum_category',
      targetId: input.ids[0]!, reason: `${input.reason} (${input.ids.length} kategori)`, requestId: request.id,
      rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded',
    });
    await client.query('COMMIT');
    return { data: { ordered: updated.rowCount } };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    const message = (error as Error).message;
    return reply.code(message === 'FORBIDDEN' ? 403 : message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'FORUM_ORDER_REJECTED', message: 'Sıralama kaydedilemedi.' } });
  } finally {
    client.release();
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
    const rows = await db.query<{ id: string; title: string; category_id: string; category_title: string; author_id: string; author_name: string | null; excerpt: string; reply_count: number; view_count: string; is_pinned: boolean; is_locked: boolean; moderation_state: string; created_at: Date; last_activity_at: Date }>(
      // An excerpt rather than the whole body: locking a thread is a judgement
      // about what it says, and a title alone does not carry that. Truncated
      // because fifty full topics is half a megabyte to read one paragraph of.
      `SELECT t.id,t.title,t.category_id,c.title category_title,t.author_id,p.display_name author_name,
              left(t.body,600) excerpt,
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
        id: row.id, title: row.title, categoryId: row.category_id, categoryTitle: row.category_title, authorId: row.author_id,
        authorName: row.author_name, excerpt: row.excerpt, replyCount: row.reply_count, viewCount: Number(row.view_count),
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

// --- Marketplace operations ----------------------------------------------
// Listings and auctions are member-created and money-adjacent, and until now
// nobody could see them from the outside: the public list shows active listings
// only, and auctions have no read endpoint at all. A fraudulent listing could
// only be found by scrolling the app as a member.
//
// Two things about the auction schema the reads here have to work around:
// nothing ever advances marketplace_auctions.status - it is written 'scheduled'
// and stays there - and bidding is gated on starts_at/ends_at instead. So the
// state shown is derived from the clock, with the stored value carried
// alongside rather than trusted, and cancelling is made real by teaching the bid
// endpoint about it (see /v1/marketplace/auctions/:id/bids).
const MARKETPLACE_READ_ROLES: GateworkRole[] = ['owner', 'security_admin', 'operations_admin', 'moderator', 'analyst', 'auditor'];
const MARKETPLACE_ACT_ROLES: GateworkRole[] = ['owner', 'security_admin', 'operations_admin', 'moderator'];

const gateworkListingsQuery = z.object({
  status: z.enum(['all', 'draft', 'active', 'reserved', 'sold', 'inactive']).default('all'),
  query: z.string().trim().min(2).max(140).optional(),
  regionCode: z.string().trim().regex(/^[A-Za-z]{2}$/).optional(),
  category: z.enum(['vehicle', 'rental', 'home', 'electronics', 'collectible', 'art', 'other']).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).max(10_000).default(0),
});
// Only these two. 'draft', 'reserved' and 'sold' describe what the seller is
// doing with their own item; an operator marking somebody's listing sold would
// be inventing a transaction that never happened. Taking it down is the whole
// power this screen needs.
const gateworkListingStatus = z.object({
  status: z.enum(['active', 'inactive']),
  reason: z.string().trim().min(5).max(500),
});
const gateworkAuctionsQuery = z.object({
  state: z.enum(['all', 'scheduled', 'active', 'closed', 'cancelled']).default('all'),
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).max(10_000).default(0),
});
const gateworkAuctionCancel = z.object({ reason: z.string().trim().min(5).max(500) });

// Written once, used by both the list and the overview so the two can never
// disagree about what 'active' means.
const AUCTION_STATE_SQL = `CASE WHEN a.status='cancelled' THEN 'cancelled' WHEN a.ends_at<=now() THEN 'closed' WHEN a.starts_at>now() THEN 'scheduled' ELSE 'active' END`;

/**
 * What is measurably unusual about a listing.
 *
 * A member-to-member marketplace is where fraud lands first, and until now the
 * console showed a listing exactly as its seller wrote it: a title, a price and
 * a name. Nothing on that card distinguishes an honest $400 sofa from a $400
 * car, or a neighbour's second listing from the fortieth one an account opened
 * this morning under forty different titles that are all the same sentence.
 *
 * These are measurements, not a verdict. No score is stored, no listing is
 * hidden automatically, and the thresholds that turn a number into a warning
 * live in the console next to the sentence an operator reads - a rule about
 * what counts as "too cheap" should be arguable without a migration, and a
 * takedown should always be a person's decision with a reason attached.
 *
 * The median deliberately excludes the listing itself and is only meaningful
 * with enough comparable rows; `categorySample` is returned so the console can
 * say "not enough listings to compare" instead of quietly comparing against
 * two.
 */
type ListingSignals = {
  categoryMedianPrice: number | null;
  categorySample: number;
  sellerListingsLast24h: number;
  sellerActiveListings: number;
  sellerOpenReports: number;
  sellerFraudReports: number;
  sellerVerified: boolean;
  duplicateTitleOwners: number;
};

async function listingRiskSignals(ids: string[]): Promise<Map<string, ListingSignals>> {
  const rows = await db.query<{ id: string; category_median: string | null; category_sample: string; seller_listings_24h: string; seller_active_listings: string; seller_open_reports: string; seller_fraud_reports: string; seller_verified: boolean; duplicate_title_owners: string }>(
    `SELECT l.id,
            med.median category_median,med.sample category_sample,
            (SELECT count(*) FROM marketplace_listings s WHERE s.owner_id=l.owner_id AND s.created_at>now()-interval '24 hours') seller_listings_24h,
            (SELECT count(*) FROM marketplace_listings s WHERE s.owner_id=l.owner_id AND s.status='active') seller_active_listings,
            (SELECT count(*) FROM content_reports r WHERE r.reported_user_id=l.owner_id AND r.status IN ('open','in_review')) seller_open_reports,
            (SELECT count(*) FROM content_reports r WHERE r.reported_user_id=l.owner_id AND r.category IN ('scam_fraud','illegal_goods') AND r.created_at>now()-interval '180 days') seller_fraud_reports,
            COALESCE((SELECT c.identity_verified FROM member_capabilities c WHERE c.user_id=l.owner_id),false) seller_verified,
            (SELECT count(DISTINCT o.owner_id) FROM marketplace_listings o WHERE lower(o.title)=lower(l.title) AND o.owner_id<>l.owner_id) duplicate_title_owners
       FROM marketplace_listings l
       LEFT JOIN LATERAL (
         SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY s.price) median,count(*) sample
           FROM marketplace_listings s
          WHERE s.category=l.category AND s.status='active' AND s.id<>l.id
       ) med ON true
      WHERE l.id=ANY($1::uuid[])`,
    [ids],
  );
  return new Map(rows.rows.map((row) => [row.id, {
    categoryMedianPrice: row.category_median === null ? null : Number(row.category_median),
    categorySample: Number(row.category_sample),
    sellerListingsLast24h: Number(row.seller_listings_24h),
    sellerActiveListings: Number(row.seller_active_listings),
    sellerOpenReports: Number(row.seller_open_reports),
    sellerFraudReports: Number(row.seller_fraud_reports),
    sellerVerified: row.seller_verified,
    duplicateTitleOwners: Number(row.duplicate_title_owners),
  }]));
}

app.get('/v1/internal/gatework/marketplace/listings', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, MARKETPLACE_READ_ROLES);
    const input = gateworkListingsQuery.parse(request.query);
    const rows = await db.query<{ id: string; title: string; description: string; price: string; status: string; category: string; city: string | null; region_code: string | null; owner_id: string; owner_name: string | null; created_at: Date; updated_at: Date; auction_id: string | null; auction_state: string | null; bid_count: string }>(
      `SELECT l.id,l.title,l.description,l.price,l.status,l.category,l.city,l.region_code,l.owner_id,
              p.display_name owner_name,l.created_at,l.updated_at,
              a.id auction_id,${AUCTION_STATE_SQL} auction_state,
              (SELECT count(*) FROM marketplace_auction_bids b WHERE b.auction_id=a.id) bid_count
         FROM marketplace_listings l
         LEFT JOIN community_profile_projection p ON p.user_id=l.owner_id
         LEFT JOIN marketplace_auctions a ON a.listing_id=l.id
        WHERE ($1::text = 'all' OR l.status=$1)
          AND ($2::text IS NULL OR l.title ILIKE '%'||$2||'%')
          AND ($3::text IS NULL OR l.region_code=$3)
          AND ($6::text IS NULL OR l.category=$6)
        ORDER BY l.created_at DESC,l.id DESC
        LIMIT $4 OFFSET $5`,
      [input.status, input.query ?? null, input.regionCode?.toUpperCase() ?? null, input.limit + 1, input.offset, input.category ?? null],
    );
    const page = rows.rows.slice(0, input.limit);
    const signals = page.length > 0 ? await listingRiskSignals(page.map((row) => row.id)) : new Map<string, ListingSignals>();
    return {
      data: page.map((row) => ({
        id: row.id, title: row.title, description: row.description, price: Number(row.price), status: row.status,
        category: row.category,
        city: row.city, regionCode: row.region_code, ownerId: row.owner_id, ownerName: row.owner_name,
        createdAt: row.created_at.toISOString(), updatedAt: row.updated_at.toISOString(),
        auction: row.auction_id ? { id: row.auction_id, state: row.auction_state!, bidCount: Number(row.bid_count) } : null,
        signals: signals.get(row.id) ?? null,
      })),
      meta: { nextOffset: rows.rows.length > input.limit ? input.offset + input.limit : null },
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'MARKETPLACE_LISTINGS_UNAVAILABLE', message: 'İlanlar okunamadı.' } });
  }
});

// Taking a listing down takes its auction with it, in one transaction. An item
// pulled for being counterfeit whose auction kept accepting bids would leave
// people bidding real money on something the operator already decided does not
// exist here.
app.post('/v1/internal/gatework/marketplace/listings/:id/status', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, MARKETPLACE_ACT_ROLES);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = gateworkListingStatus.parse(request.body);
    await client.query('BEGIN');
    const updated = await client.query<{ status: string }>(
      'UPDATE marketplace_listings SET status=$2,updated_at=now() WHERE id=$1 RETURNING status',
      [id, input.status],
    );
    if (!updated.rows[0]) { await client.query('ROLLBACK'); return reply.code(404).send({ error: { code: 'LISTING_NOT_FOUND', message: 'İlan bulunamadı.' } }); }
    const cancelled = input.status === 'inactive'
      ? await client.query<{ id: string }>("UPDATE marketplace_auctions SET status='cancelled' WHERE listing_id=$1 AND status<>'cancelled' AND ends_at>now() RETURNING id", [id])
      : { rows: [] as { id: string }[] };
    await client.query('COMMIT');
    await auditGateworkOperation({
      actorId: actor.actorId, roles: actor.roles, action: 'marketplace_listing.status', targetType: 'marketplace_listing', targetId: id,
      reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded',
    });
    // A separate line per auction: the reason it was cancelled is the listing
    // decision, but somebody looking up that auction later has to find it under
    // its own id rather than by knowing which listing it hung off.
    for (const row of cancelled.rows) {
      await auditGateworkOperation({
        actorId: actor.actorId, roles: actor.roles, action: 'marketplace_auction.cancel', targetType: 'marketplace_auction', targetId: row.id,
        reason: `İlan yayından kaldırıldı: ${input.reason}`, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded',
      });
    }
    return { data: { id, status: updated.rows[0].status, cancelledAuctions: cancelled.rows.length } };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'LISTING_STATUS_REJECTED', message: 'İlan durumu değiştirilemedi.' } });
  } finally {
    client.release();
  }
});

app.get('/v1/internal/gatework/marketplace/auctions', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, MARKETPLACE_READ_ROLES);
    const input = gateworkAuctionsQuery.parse(request.query);
    const rows = await db.query<{ id: string; listing_id: string; listing_title: string; listing_status: string; seller_id: string; seller_name: string | null; seller_eligible: boolean; starting_price: string; minimum_increment: string; starts_at: Date; ends_at: Date; stored_status: string; state: string; bid_count: string; top_bid: string | null; top_bidder_id: string | null; top_bidder_name: string | null; created_at: Date }>(
      `SELECT a.id,a.listing_id,l.title listing_title,l.status listing_status,a.seller_id,p.display_name seller_name,
              a.starting_price,a.minimum_increment,a.starts_at,a.ends_at,a.status stored_status,
              ${AUCTION_STATE_SQL} state,a.created_at,
              -- The badge is checked when the auction opens and never again. A
              -- running auction whose seller has since lost it is the row an
              -- operator most needs to see, and it looked identical to the rest.
              COALESCE(c.auction_seller_eligible,false) seller_eligible,
              (SELECT count(*) FROM marketplace_auction_bids b WHERE b.auction_id=a.id) bid_count,
              top.amount top_bid,top.bidder_id top_bidder_id,bp.display_name top_bidder_name
         FROM marketplace_auctions a
         JOIN marketplace_listings l ON l.id=a.listing_id
         LEFT JOIN member_capabilities c ON c.user_id=a.seller_id
         LEFT JOIN community_profile_projection p ON p.user_id=a.seller_id
         LEFT JOIN LATERAL (
           SELECT b.amount,b.bidder_id FROM marketplace_auction_bids b
            WHERE b.auction_id=a.id ORDER BY b.amount DESC,b.created_at ASC LIMIT 1
         ) top ON true
         LEFT JOIN community_profile_projection bp ON bp.user_id=top.bidder_id
        WHERE ($1::text = 'all' OR ${AUCTION_STATE_SQL}=$1)
        ORDER BY a.ends_at DESC,a.id DESC
        LIMIT $2 OFFSET $3`,
      [input.state, input.limit + 1, input.offset],
    );
    const page = rows.rows.slice(0, input.limit);
    return {
      data: page.map((row) => ({
        id: row.id, listingId: row.listing_id, listingTitle: row.listing_title, listingStatus: row.listing_status,
        sellerId: row.seller_id, sellerName: row.seller_name, sellerEligible: row.seller_eligible,
        startingPrice: Number(row.starting_price), minimumIncrement: Number(row.minimum_increment),
        startsAt: row.starts_at.toISOString(), endsAt: row.ends_at.toISOString(),
        storedStatus: row.stored_status, state: row.state,
        bidCount: Number(row.bid_count), topBid: row.top_bid === null ? null : Number(row.top_bid),
        topBidderId: row.top_bidder_id, topBidderName: row.top_bidder_name,
        createdAt: row.created_at.toISOString(),
      })),
      meta: { nextOffset: rows.rows.length > input.limit ? input.offset + input.limit : null },
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'MARKETPLACE_AUCTIONS_UNAVAILABLE', message: 'İhaleler okunamadı.' } });
  }
});

// Cancelling stops bids and nothing else: the bids already placed stay in the
// table. Deleting them would erase the evidence of the very behaviour that
// usually causes the cancellation.
app.post('/v1/internal/gatework/marketplace/auctions/:id/cancel', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, MARKETPLACE_ACT_ROLES);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = gateworkAuctionCancel.parse(request.body);
    const updated = await db.query<{ id: string }>("UPDATE marketplace_auctions SET status='cancelled' WHERE id=$1 AND status<>'cancelled' RETURNING id", [id]);
    if (!updated.rows[0]) return reply.code(404).send({ error: { code: 'AUCTION_NOT_CANCELLABLE', message: 'İhale bulunamadı veya zaten iptal edilmiş.' } });
    await auditGateworkOperation({
      actorId: actor.actorId, roles: actor.roles, action: 'marketplace_auction.cancel', targetType: 'marketplace_auction', targetId: id,
      reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded',
    });
    return { data: { id, state: 'cancelled' } };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'AUCTION_CANCEL_REJECTED', message: 'İhale iptal edilemedi.' } });
  }
});

app.get('/v1/internal/gatework/marketplace/overview', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, MARKETPLACE_READ_ROLES);
    const listings = await db.query<{ status: string; total: string }>('SELECT status,count(*) total FROM marketplace_listings GROUP BY status');
    const auctions = await db.query<{ state: string; total: string }>(`SELECT ${AUCTION_STATE_SQL} state,count(*) total FROM marketplace_auctions a GROUP BY 1`);
    const activity = await db.query<{ new_listings: string; bids_last_7_days: string; ending_soon: string; eligible_sellers: string }>(
      `SELECT (SELECT count(*) FROM marketplace_listings WHERE created_at>now()-interval '7 days') new_listings,
              (SELECT count(*) FROM marketplace_auction_bids WHERE created_at>now()-interval '7 days') bids_last_7_days,
              (SELECT count(*) FROM marketplace_auctions a WHERE a.status<>'cancelled' AND a.ends_at>now() AND a.ends_at<now()+interval '24 hours') ending_soon,
              (SELECT count(*) FROM member_capabilities WHERE auction_seller_eligible) eligible_sellers`,
    );
    const row = activity.rows[0]!;
    return {
      data: {
        listings: Object.fromEntries(listings.rows.map((r) => [r.status, Number(r.total)])),
        auctions: Object.fromEntries(auctions.rows.map((r) => [r.state, Number(r.total)])),
        newListingsLast7Days: Number(row.new_listings),
        bidsLast7Days: Number(row.bids_last_7_days),
        endingSoon: Number(row.ending_soon),
        eligibleSellers: Number(row.eligible_sellers),
      },
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'MARKETPLACE_OVERVIEW_UNAVAILABLE', message: 'Çarşı özeti okunamadı.' } });
  }
});

// --- Safety and SOS -------------------------------------------------------
// The one flow in this service that handles an exact position, and the rules
// around it are the reason it is written out at length rather than folded into
// the sections above.
//
// A member asks for help and may send a point with the request. That point is
// sealed: listing alerts never returns it, and reading it takes a separate
// grant with a written reason and an expiry, which the operator has to ask for
// by name. Closing the alert revokes every grant and deletes the point in the
// same transaction, so the coordinates of somebody who has been helped do not
// stay in an operations console.
//
// The member can always cancel, and cancelling deletes the point too. "I am
// fine" has to mean the position stops existing, not that a card turns grey.
const SAFETY_READ_ROLES: GateworkRole[] = ['owner', 'security_admin', 'operations_admin', 'auditor'];
const SAFETY_ACT_ROLES: GateworkRole[] = ['owner', 'security_admin', 'operations_admin'];

const sosTriggerSchema = z.object({
  kind: z.enum(['personal_safety', 'medical', 'harassment', 'accident', 'other']),
  note: z.string().trim().min(1).max(500).optional(),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),
  accuracyMeters: z.number().int().min(0).max(100_000).optional(),
  locationNote: z.string().trim().max(200).optional(),
}).refine((value) => (value.latitude === undefined) === (value.longitude === undefined), { message: 'latitude and longitude travel together' });

const sosCloseSchema = z.object({ status: z.enum(['resolved', 'cancelled']), reason: z.string().trim().min(5).max(1000) });
const sosLocationAccessSchema = z.object({
  reason: z.string().trim().min(5).max(500),
  // Bounded on both ends. Too short is a grant an operator has to keep
  // re-opening in the middle of an emergency; too long is a seal that is not
  // one. The default is the whole of a normal response.
  minutes: z.coerce.number().int().min(5).max(120).default(30),
});

// A member pressing a panic button presses it more than once. Sending the same
// SOS again must therefore not fail and must not open a second card: the newer
// position simply replaces the older one on the alert already open.
app.post('/v1/safety/sos', { config: { rateLimit: { max: 30, timeWindow: '5 minutes' } } }, async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const input = sosTriggerSchema.parse(request.body);
    const point = input.latitude !== undefined && input.longitude !== undefined
      ? { lat: input.latitude, lon: input.longitude }
      : null;
    // ST_MakePoint is strict, so a missing coordinate yields NULL and the
    // no-location case needs no second statement. The casts are not decoration:
    // an unreferenced or untyped parameter is a bind error, not a NULL.
    const row = await db.query<{ id: string; status: string; created_at: Date; has_location: boolean }>(
      `INSERT INTO sos_alerts(member_id,kind,note,location_cell,location_accuracy_m,location_captured_at,location_note)
       VALUES($1,$2,$3,
              ST_SetSRID(ST_MakePoint($5::float8,$4::float8),4326)::geography,
              $6::int,
              CASE WHEN $4::float8 IS NULL THEN NULL ELSE now() END,
              $7)
       ON CONFLICT (member_id) WHERE status IN ('active','acknowledged') DO UPDATE SET
         kind=EXCLUDED.kind,
         note=COALESCE(EXCLUDED.note,sos_alerts.note),
         location_cell=COALESCE(EXCLUDED.location_cell,sos_alerts.location_cell),
         location_accuracy_m=COALESCE(EXCLUDED.location_accuracy_m,sos_alerts.location_accuracy_m),
         location_captured_at=COALESCE(EXCLUDED.location_captured_at,sos_alerts.location_captured_at),
         location_note=COALESCE(EXCLUDED.location_note,sos_alerts.location_note)
       RETURNING id,status,created_at,location_cell IS NOT NULL has_location`,
      [userId, input.kind, input.note ?? null, point?.lat ?? null, point?.lon ?? null, input.accuracyMeters ?? null, input.locationNote ?? null],
    );
    const alert = row.rows[0]!;
    // The alert's state, not this request's payload: a second press that sends
    // no point does not un-share the point already on the open alert, and a
    // response saying otherwise would be read as "my location was dropped".
    return reply.code(201).send({ data: { id: alert.id, status: alert.status, createdAt: alert.created_at.toISOString(), locationShared: alert.has_location } });
  } catch (error) {
    return reply.code((error as { statusCode?: number }).statusCode ?? 400).send({ error: { code: 'SOS_NOT_SENT', message: 'Yardım çağrısı gönderilemedi.' } });
  }
});

app.get('/v1/safety/sos/active', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const row = await db.query<{ id: string; kind: string; status: string; note: string | null; location_note: string | null; created_at: Date; acknowledged_at: Date | null; has_location: boolean; watchers: string }>(
      `SELECT a.id,a.kind,a.status,a.note,a.location_note,a.created_at,a.acknowledged_at,
              a.location_cell IS NOT NULL has_location,
              (SELECT count(*) FROM sos_location_grants g WHERE g.alert_id=a.id AND g.revoked_at IS NULL AND g.expires_at>now()) watchers
       FROM sos_alerts a WHERE a.member_id=$1 AND a.status IN ('active','acknowledged')`,
      [userId],
    );
    const alert = row.rows[0];
    if (!alert) return { data: null };
    return {
      data: {
        id: alert.id,
        kind: alert.kind,
        status: alert.status,
        note: alert.note,
        locationNote: alert.location_note,
        locationShared: alert.has_location,
        createdAt: alert.created_at.toISOString(),
        acknowledgedAt: alert.acknowledged_at?.toISOString() ?? null,
        // The member is told how many operators can currently see their
        // position. Being watched without knowing it is the thing the grant
        // was built to prevent, and a count they cannot see is not a seal.
        activeLocationWatchers: Number(alert.watchers),
      },
    };
  } catch {
    return reply.code(401).send({ error: { code: 'SOS_UNAVAILABLE', message: 'Yardım çağrısı okunamadı.' } });
  }
});

// Cancelling is destructive on purpose: the point is deleted and every live
// grant is revoked in the same statement.
app.post('/v1/safety/sos/:id/cancel', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const client = await db.connect();
    try {
      await client.query('BEGIN');
      const closed = await client.query(
        `UPDATE sos_alerts SET status='cancelled',closed_at=now(),closed_by=$1,closure_reason='Üye çağrıyı geri aldı.',
                location_cell=NULL,location_accuracy_m=NULL,location_captured_at=NULL
         WHERE id=$2 AND member_id=$1 AND status IN ('active','acknowledged')`,
        [userId, id],
      );
      if (!closed.rowCount) { await client.query('ROLLBACK'); return reply.code(404).send({ error: { code: 'SOS_NOT_OPEN', message: 'Açık bir yardım çağrısı bulunamadı.' } }); }
      await client.query('UPDATE sos_location_grants SET revoked_at=now() WHERE alert_id=$1 AND revoked_at IS NULL', [id]);
      await client.query('COMMIT');
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    return reply.code(204).send();
  } catch (error) {
    return reply.code((error as { statusCode?: number }).statusCode ?? 400).send({ error: { code: 'SOS_CANCEL_REJECTED', message: 'Çağrı geri alınamadı.' } });
  }
});

// The operator queue. No coordinates in this response at any role: what an
// operator sees is that there is a point and whether they are currently allowed
// to look at it.
app.get('/v1/internal/gatework/safety/alerts', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, SAFETY_READ_ROLES);
    const input = z.object({ state: z.enum(['open', 'all']).default('open'), limit: z.coerce.number().int().min(1).max(100).default(50) }).parse(request.query);
    const rows = await db.query<{ id: string; member_id: string; member_name: string | null; kind: string; status: string; note: string | null; location_note: string | null; has_location: boolean; location_captured_at: Date | null; location_accuracy_m: number | null; created_at: Date; acknowledged_at: Date | null; closed_at: Date | null; closure_reason: string | null; grant_expires_at: Date | null; watchers: string }>(
      `SELECT a.id,a.member_id,cp.display_name member_name,a.kind,a.status,a.note,a.location_note,
              a.location_cell IS NOT NULL has_location,a.location_captured_at,a.location_accuracy_m,
              a.created_at,a.acknowledged_at,a.closed_at,a.closure_reason,
              (SELECT max(g.expires_at) FROM sos_location_grants g WHERE g.alert_id=a.id AND g.operator_id=$1 AND g.revoked_at IS NULL AND g.expires_at>now()) grant_expires_at,
              (SELECT count(*) FROM sos_location_grants g WHERE g.alert_id=a.id AND g.revoked_at IS NULL AND g.expires_at>now()) watchers
       FROM sos_alerts a LEFT JOIN community_profile_projection cp ON cp.user_id=a.member_id
       WHERE ($2='all' OR a.status IN ('active','acknowledged'))
       ORDER BY (a.status IN ('active','acknowledged')) DESC, a.created_at ASC LIMIT $3`,
      [actor.actorId, input.state, input.limit],
    );
    return {
      data: rows.rows.map((row) => ({
        id: row.id,
        memberId: row.member_id,
        memberName: row.member_name,
        kind: row.kind,
        status: row.status,
        note: row.note,
        locationNote: row.location_note,
        location: {
          shared: row.has_location,
          capturedAt: row.location_captured_at?.toISOString() ?? null,
          accuracyMeters: row.location_accuracy_m,
          // Whether this operator may read it, and until when. The coordinates
          // themselves are a different endpoint on purpose.
          accessExpiresAt: row.grant_expires_at?.toISOString() ?? null,
          activeWatchers: Number(row.watchers),
        },
        createdAt: row.created_at.toISOString(),
        acknowledgedAt: row.acknowledged_at?.toISOString() ?? null,
        closedAt: row.closed_at?.toISOString() ?? null,
        closureReason: row.closure_reason,
      })),
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'SOS_ALERTS_UNAVAILABLE', message: 'Yardım çağrıları okunamadı.' } });
  }
});

// Taking the call. Separate from closing it: "somebody is on this" and "this is
// over" are different facts, and a queue that cannot tell them apart makes two
// operators answer the same person while a third alert waits.
app.post('/v1/internal/gatework/safety/alerts/:id/acknowledge', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, SAFETY_ACT_ROLES);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const updated = await db.query('UPDATE sos_alerts SET status=\'acknowledged\',acknowledged_at=now(),acknowledged_by=$1 WHERE id=$2 AND status=\'active\'', [actor.actorId, id]);
    if (!updated.rowCount) return reply.code(409).send({ error: { code: 'SOS_NOT_ACTIONABLE', message: 'Çağrı zaten üstlenilmiş veya kapanmış.' } });
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'sos.acknowledge', targetType: 'sos_alert', targetId: id, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    return reply.code(204).send();
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'SOS_ACKNOWLEDGE_REJECTED', message: 'Çağrı üstlenilemedi.' } });
  }
});

// Breaking the seal. The reason is required and stored on the grant itself, not
// only in the audit log: the grant is what a member is entitled to see when
// they ask who looked and why.
app.post('/v1/internal/gatework/safety/alerts/:id/location-access', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, SAFETY_ACT_ROLES);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = sosLocationAccessSchema.parse(request.body);
    // Only an open alert. A closed one has had its point deleted, and a grant
    // over nothing is a permission somebody would later mistake for evidence.
    const alert = await db.query<{ has_location: boolean }>("SELECT location_cell IS NOT NULL has_location FROM sos_alerts WHERE id=$1 AND status IN ('active','acknowledged')", [id]);
    if (!alert.rows.length) return reply.code(404).send({ error: { code: 'SOS_NOT_OPEN', message: 'Açık çağrı bulunamadı.' } });
    if (!alert.rows[0]!.has_location) return reply.code(409).send({ error: { code: 'SOS_NO_LOCATION', message: 'Bu çağrıda konum paylaşılmamış.' } });
    const grant = await db.query<{ id: string; expires_at: Date }>(
      "INSERT INTO sos_location_grants(alert_id,operator_id,operator_roles,reason,expires_at) VALUES($1,$2,$3,$4,now()+make_interval(mins=>$5::int)) RETURNING id,expires_at",
      [id, actor.actorId, actor.roles, input.reason, input.minutes],
    );
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'sos.location_access', targetType: 'sos_alert', targetId: id, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    return reply.code(201).send({ data: { grantId: grant.rows[0]!.id, expiresAt: grant.rows[0]!.expires_at.toISOString() } });
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'SOS_LOCATION_ACCESS_REJECTED', message: 'Konum erişimi açılamadı.' } });
  }
});

// The point itself, and the only route that returns it. The grant is checked in
// the same statement that reads the coordinates rather than in a prior query:
// two statements leave a window in which a revoked grant still answers.
app.get('/v1/internal/gatework/safety/alerts/:id/location', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, SAFETY_ACT_ROLES);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const row = await db.query<{ latitude: number; longitude: number; accuracy: number | null; captured_at: Date | null; expires_at: Date }>(
      `SELECT ST_Y(a.location_cell::geometry) latitude,ST_X(a.location_cell::geometry) longitude,
              a.location_accuracy_m accuracy,a.location_captured_at captured_at,g.expires_at
       FROM sos_alerts a
       JOIN sos_location_grants g ON g.alert_id=a.id AND g.operator_id=$2 AND g.revoked_at IS NULL AND g.expires_at>now()
       WHERE a.id=$1 AND a.location_cell IS NOT NULL AND a.status IN ('active','acknowledged')
       ORDER BY g.expires_at DESC LIMIT 1`,
      [id, actor.actorId],
    );
    const point = row.rows[0];
    if (!point) return reply.code(403).send({ error: { code: 'SOS_LOCATION_SEALED', message: 'Bu konumu görme yetkin yok veya süresi doldu.' } });
    return { data: { latitude: point.latitude, longitude: point.longitude, accuracyMeters: point.accuracy, capturedAt: point.captured_at?.toISOString() ?? null, accessExpiresAt: point.expires_at.toISOString() } };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'SOS_LOCATION_UNAVAILABLE', message: 'Konum okunamadı.' } });
  }
});

// Closing. The point goes with it, in the same transaction as the status: an
// alert that is over is not a reason to keep somebody's coordinates, and the
// closure reason is the record of what happened instead.
app.post('/v1/internal/gatework/safety/alerts/:id/close', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, SAFETY_ACT_ROLES);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = sosCloseSchema.parse(request.body);
    const client = await db.connect();
    try {
      await client.query('BEGIN');
      const closed = await client.query(
        `UPDATE sos_alerts SET status=$1,closed_at=now(),closed_by=$2,closure_reason=$3,
                location_cell=NULL,location_accuracy_m=NULL,location_captured_at=NULL
         WHERE id=$4 AND status IN ('active','acknowledged')`,
        [input.status, actor.actorId, input.reason, id],
      );
      if (!closed.rowCount) { await client.query('ROLLBACK'); return reply.code(409).send({ error: { code: 'SOS_NOT_OPEN', message: 'Çağrı zaten kapanmış.' } }); }
      await client.query('UPDATE sos_location_grants SET revoked_at=now() WHERE alert_id=$1 AND revoked_at IS NULL', [id]);
      await client.query('COMMIT');
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'sos.close', targetType: 'sos_alert', targetId: id, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    return reply.code(204).send();
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'SOS_CLOSE_REJECTED', message: 'Çağrı kapatılamadı.' } });
  }
});

// --- Etkinlikler ----------------------------------------------------------
// The app has had an Etkinlikler tab since its first release, wired to a mock
// repository: four invented meetups, the same four for every member, with no
// route behind them - `GET /v1/events` has never existed. Migration 022 gives
// them a table; below are the two reads the app makes, the RSVP it writes, and
// the console's publishing desk.
//
// Events are published from the console. The app has no composer for them, and
// inventing one here would mean shipping a moderation queue in the same breath;
// an operator publishing under a known, audited name is the honest version of
// "official event".
const eventsQuery = z.object({ cursor: z.string().max(128).optional(), limit: z.coerce.number().int().min(1).max(50).default(20) });
const rsvpBody = z.object({ status: z.enum(['going', 'interested', 'none']) });
// `viewer` is the placeholder holding the member id, or null for the console -
// which has no RSVP of its own and must not be told anybody else's.
const eventSelect = (viewer: string | null) => `SELECT e.id,e.title,e.description,e.category,e.starts_at,e.ends_at,e.venue_label,e.city,e.region_code,e.price_label,e.external_url,e.capacity,e.status,e.cancellation_reason,e.created_at,
  m.safe_url media_url,
  ${viewer ? `(SELECT r.status FROM event_rsvps r WHERE r.event_id=e.id AND r.member_id=${viewer})` : 'NULL'} viewer_status,
  (SELECT count(*) FROM event_rsvps r WHERE r.event_id=e.id AND r.status='going') going_count,
  (SELECT count(*) FROM event_rsvps r WHERE r.event_id=e.id AND r.status='interested') interested_count
  FROM community_events e LEFT JOIN media_assets m ON m.id=e.media_id`;
type EventRow = { id: string; title: string; description: string; category: string; starts_at: Date; ends_at: Date | null; venue_label: string; city: string; region_code: string; price_label: string; external_url: string | null; capacity: number | null; status: string; cancellation_reason: string | null; created_at: Date; media_url: string | null; viewer_status: string | null; going_count: string; interested_count: string };
const eventCursor = (row: EventRow) => Buffer.from(`${row.starts_at.toISOString()}|${row.id}`).toString('base64url');
const eventJson = async (row: EventRow) => ({
  id: row.id,
  title: row.title,
  description: row.description,
  category: row.category,
  startsAt: row.starts_at.toISOString(),
  endsAt: row.ends_at?.toISOString() ?? null,
  // The card draws one line under the title and the detail sheet draws two, so
  // the venue and the city travel separately.
  location: row.venue_label,
  city: row.city,
  regionCode: row.region_code,
  priceLabel: row.price_label,
  externalUrl: row.external_url,
  capacity: row.capacity,
  // Signed on the way out, never stored - the rule posts, stories, news and
  // promotions all follow.
  imageUrl: row.media_url ? await mediaObjectUrl(row.media_url) : null,
  // A count leaves; the going-list does not. Who was where on a given evening
  // is exactly the record this service has spent twenty migrations not keeping,
  // and the app only ever draws the number.
  attendeeCount: Number(row.going_count),
  interestedCount: Number(row.interested_count),
  status: row.status,
  cancellationReason: row.cancellation_reason,
  rsvpStatus: row.viewer_status ?? 'none',
});

/// Upcoming published events, soonest first. One that has already started drops
/// off here rather than being filtered client-side: "yaklasan" is the whole
/// promise of the tab, and two app versions must not disagree about it.
app.get('/v1/events', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const input = eventsQuery.parse(request.query);
    const cursor = decodeCursor(input.cursor);
    const params: unknown[] = [userId];
    let where = `e.status='published' AND e.starts_at > now()`;
    if (cursor) { params.push(cursor.createdAt, cursor.id); where += ` AND (e.starts_at,e.id) > ($${params.length - 1}::timestamptz,$${params.length}::uuid)`; }
    params.push(input.limit + 1);
    const result = await db.query<EventRow>(`${eventSelect('$1')} WHERE ${where} ORDER BY e.starts_at ASC,e.id ASC LIMIT $${params.length}`, params);
    const page = result.rows.slice(0, input.limit);
    const next = result.rows.length > input.limit ? eventCursor(page[page.length - 1]!) : null;
    return { data: await Promise.all(page.map(eventJson)), meta: { nextCursor: next } };
  } catch (error) {
    const status = readFailureStatus(error);
    if (status >= 500) request.log.error({ err: error }, 'events read failed');
    return reply.code(status).send({ error: { code: 'EVENTS_UNAVAILABLE', message: 'Etkinlikler yüklenemedi.' } });
  }
});

/// A single event, cancellation included. A cancelled one stays readable on
/// purpose: somebody with it in their calendar needs to find out why, not find
/// a 404.
app.get('/v1/events/:id', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const row = await db.query<EventRow>(`${eventSelect('$1')} WHERE e.id=$2 AND e.status<>'draft'`, [userId, id]);
    if (!row.rows[0]) return reply.code(404).send({ error: { code: 'EVENT_NOT_FOUND', message: 'Etkinlik bulunamadı.' } });
    return { data: await eventJson(row.rows[0]) };
  } catch (error) {
    const status = readFailureStatus(error);
    if (status >= 500) request.log.error({ err: error }, 'event read failed');
    return reply.code(status).send({ error: { code: 'EVENT_UNAVAILABLE', message: 'Etkinlik yüklenemedi.' } });
  }
});

/// Saying you are going, or taking it back. 'none' deletes the row instead of
/// storing a third state: a withdrawn RSVP is not a fact worth keeping, and
/// keeping it would turn this table into an attendance history.
app.put('/v1/events/:id/rsvp', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = rsvpBody.parse(request.body);
    const event = await db.query<{ status: string; capacity: number | null }>('SELECT status,capacity FROM community_events WHERE id=$1', [id]);
    if (!event.rows[0]) return reply.code(404).send({ error: { code: 'EVENT_NOT_FOUND', message: 'Etkinlik bulunamadı.' } });
    if (event.rows[0].status !== 'published') return reply.code(409).send({ error: { code: 'EVENT_CLOSED', message: 'Bu etkinlik katılıma açık değil.' } });
    if (input.status === 'none') await db.query('DELETE FROM event_rsvps WHERE event_id=$1 AND member_id=$2', [id, userId]);
    else {
      // The door count is checked here, not trusted from the client, and only
      // for 'going' - being interested in a full event costs nobody a seat.
      const seated = await db.query<{ member_id: string }>(
        `INSERT INTO event_rsvps(event_id,member_id,status) SELECT $1::uuid,$2::uuid,$3
         WHERE $3<>'going' OR $4::int IS NULL OR (SELECT count(*) FROM event_rsvps r WHERE r.event_id=$1 AND r.status='going' AND r.member_id<>$2) < $4::int
         ON CONFLICT (event_id,member_id) DO UPDATE SET status=EXCLUDED.status,updated_at=now() RETURNING member_id`,
        [id, userId, input.status, event.rows[0].capacity],
      );
      if (!seated.rows[0]) return reply.code(409).send({ error: { code: 'EVENT_FULL', message: 'Kontenjan doldu.' } });
    }
    const row = await db.query<EventRow>(`${eventSelect('$1')} WHERE e.id=$2`, [userId, id]);
    return { data: await eventJson(row.rows[0]!) };
  } catch (error) {
    return reply.code((error as { statusCode?: number }).statusCode ?? 400).send({ error: { code: 'EVENT_RSVP_REJECTED', message: 'Katılım kaydedilemedi.' } });
  }
});

// --- Event operations -----------------------------------------------------
const gateworkEventQuery = z.object({ status: z.enum(['draft', 'published', 'cancelled']).default('published'), limit: z.coerce.number().int().min(1).max(100).default(50), offset: z.coerce.number().int().min(0).default(0) });
const gateworkEventBody = z.object({
  title: z.string().trim().min(3).max(140),
  description: z.string().trim().max(4000).default(''),
  category: z.string().trim().min(2).max(40).default('Etkinlik'),
  startsAt: z.string().datetime(),
  endsAt: z.string().datetime().optional(),
  venueLabel: z.string().trim().min(2).max(200),
  city: z.string().trim().min(2).max(80),
  regionCode: z.string().trim().length(2),
  mediaId: z.string().uuid().optional(),
  priceLabel: z.string().trim().min(1).max(60).default('Ücretsiz'),
  externalUrl: z.string().url().startsWith('https://').max(500).optional(),
  capacity: z.number().int().min(1).max(100000).optional(),
  // Publishing on creation is the normal case; a draft is for the one somebody
  // is still writing.
  publish: z.boolean().default(false),
  idempotencyKey: z.string().min(8).max(120),
});
const eventCancelBody = z.object({ reason: z.string().trim().min(3).max(500), idempotencyKey: z.string().min(8).max(120) });

app.get('/v1/internal/gatework/events', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor', 'moderator', 'auditor']);
    const input = gateworkEventQuery.parse(request.query);
    const rows = await db.query<EventRow>(`${eventSelect(null)} WHERE e.status=$1 ORDER BY e.starts_at DESC LIMIT $2 OFFSET $3`, [input.status, input.limit, input.offset]);
    return { data: await Promise.all(rows.rows.map(eventJson)), nextOffset: rows.rows.length === input.limit ? input.offset + input.limit : null };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'EVENT_QUEUE_UNAVAILABLE', message: 'Etkinlikler okunamadı.' } });
  }
});

app.post('/v1/internal/gatework/events', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const input = gateworkEventBody.parse(request.body);
    await client.query('BEGIN');
    const prior = await client.query<{ result_id: string | null }>(
      "SELECT result_id FROM gatework_command_dedup WHERE actor_id=$1 AND idempotency_key=$2 AND command_type='event.create' FOR UPDATE",
      [actor.actorId, input.idempotencyKey],
    );
    if (prior.rows[0]?.result_id) { await client.query('COMMIT'); return reply.code(200).send({ data: { id: prior.rows[0].result_id, duplicate: true } }); }
    if (input.mediaId) {
      const media = await client.query("SELECT 1 FROM media_assets WHERE id=$1 AND status='ready'", [input.mediaId]);
      if (!media.rows[0]) throw Error('MEDIA_NOT_READY');
    }
    const row = await client.query<{ id: string }>(
      `INSERT INTO community_events(title,description,category,starts_at,ends_at,venue_label,city,region_code,media_id,price_label,external_url,capacity,status,published_at,created_by)
       VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,CASE WHEN $13='published' THEN now() END,$14) RETURNING id`,
      [input.title, input.description, input.category, input.startsAt, input.endsAt ?? null, input.venueLabel, input.city, input.regionCode.toUpperCase(),
        input.mediaId ?? null, input.priceLabel, input.externalUrl ?? null, input.capacity ?? null, input.publish ? 'published' : 'draft', actor.actorId],
    );
    await client.query("INSERT INTO gatework_command_dedup(actor_id,idempotency_key,command_type,result_id) VALUES($1,$2,'event.create',$3)", [actor.actorId, input.idempotencyKey, row.rows[0]!.id]);
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: input.publish ? 'event.publish' : 'event.draft', targetType: 'event', targetId: row.rows[0]!.id, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    await client.query('COMMIT');
    return reply.code(201).send({ data: { id: row.rows[0]!.id, duplicate: false } });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'EVENT_CREATE_REJECTED', message: 'Etkinlik kaydedilemedi.' } });
  } finally {
    client.release();
  }
});

app.post('/v1/internal/gatework/events/:id/publish', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const row = await db.query<{ id: string }>("UPDATE community_events SET status='published',published_at=COALESCE(published_at,now()),updated_at=now() WHERE id=$1 AND status='draft' RETURNING id", [id]);
    if (!row.rows[0]) return reply.code(409).send({ error: { code: 'EVENT_NOT_DRAFT', message: 'Bu etkinlik taslak değil.' } });
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'event.publish', targetType: 'event', targetId: id, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    return reply.code(204).send();
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'EVENT_PUBLISH_REJECTED', message: 'Etkinlik yayınlanamadı.' } });
  }
});

/// Cancelling keeps the row and the reason. People planned around this date;
/// deleting it would empty their evening without saying why.
app.post('/v1/internal/gatework/events/:id/cancel', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor']);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = eventCancelBody.parse(request.body);
    const row = await db.query<{ id: string }>("UPDATE community_events SET status='cancelled',cancellation_reason=$2,updated_at=now() WHERE id=$1 AND status<>'cancelled' RETURNING id", [id, input.reason]);
    if (!row.rows[0]) return reply.code(409).send({ error: { code: 'EVENT_ALREADY_CANCELLED', message: 'Bu etkinlik zaten iptal edilmiş.' } });
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'event.cancel', targetType: 'event', targetId: id, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    return reply.code(204).send();
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'EVENT_CANCEL_REJECTED', message: 'Etkinlik iptal edilemedi.' } });
  }
});

// --- Announcements --------------------------------------------------------
/**
 * "Global duyuru geç".
 *
 * The button has been in the command centre since it was built and disabled the
 * whole time: no service could put a sentence in every member's inbox. It can
 * now, and the shape is deliberately the narrowest thing that does the job.
 *
 * It writes to the bell rather than sending mail or a push. The bell is a place
 * a member already checks, it costs nothing to deliver, and it is the one
 * channel that cannot reach somebody who has left. An announcement that must
 * arrive on a phone that is not open is a different feature with a different
 * consent question, and it is not this one.
 *
 * There is no audience picker. Reaching some members and not others is a
 * decision that needs a way to say who and why, and inventing one here - "only
 * New Jersey", "only verified" - would ship a targeting system nobody reviewed.
 * Everybody, or nothing.
 */
const announcementBody = z.object({
  title: z.string().trim().min(3).max(120),
  body: z.string().trim().min(3).max(2000),
  idempotencyKey: z.string().uuid(),
});

app.post('/v1/internal/gatework/announcements', { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const actor = await gateworkActor(request.headers);
    // Deliberately the shortest list on any write route here. This is the only
    // operation in the console that speaks to every member at once, in the
    // platform's own voice, and it cannot be recalled once the rows are in.
    requireGateworkRole(actor, ['owner', 'operations_admin']);
    const input = announcementBody.parse(request.body);
    await client.query('BEGIN');
    // A double-clicked button must not be two announcements: every member would
    // get the same sentence twice and there is no way to take one back.
    const prior = await client.query<{ result_id: string | null }>(
      "SELECT result_id FROM gatework_command_dedup WHERE actor_id=$1 AND idempotency_key=$2 AND command_type='announcement.send' FOR UPDATE",
      [actor.actorId, input.idempotencyKey],
    );
    if (prior.rows[0]?.result_id) { await client.query('COMMIT'); return reply.code(200).send({ data: { id: prior.rows[0].result_id, recipientCount: 0, duplicate: true } }); }
    const created = await client.query<{ id: string }>(
      'INSERT INTO member_announcements(title,body,created_by) VALUES($1,$2,$3) RETURNING id',
      [input.title, input.body, actor.actorId],
    );
    const id = created.rows[0]!.id;
    // One statement, no read-then-write: the recipient list is whoever the
    // projection holds at this instant. `last_actor_id` is the operator, which
    // is why the bell's LEFT JOIN on the member projection has to stay a LEFT
    // JOIN - an operator need not be a member.
    const fanout = await client.query(
      `INSERT INTO member_notifications(user_id,kind,subject_id,last_actor_id)
       SELECT p.user_id,'announcement',$1,$2 FROM community_profile_projection p
       ON CONFLICT(user_id,kind,subject_id) DO NOTHING`,
      [id, actor.actorId],
    );
    await client.query('UPDATE member_announcements SET recipient_count=$2 WHERE id=$1', [id, fanout.rowCount ?? 0]);
    await client.query("INSERT INTO gatework_command_dedup(actor_id,idempotency_key,command_type,result_id) VALUES($1,$2,'announcement.send',$3)", [actor.actorId, input.idempotencyKey, id]);
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'announcement.send', targetType: 'announcement', targetId: id, reason: input.title, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    await client.query('COMMIT');
    return reply.code(201).send({ data: { id, recipientCount: fanout.rowCount ?? 0, duplicate: false } });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 400).send({ error: { code: 'ANNOUNCEMENT_REJECTED', message: 'Duyuru gönderilemedi.' } });
  } finally {
    client.release();
  }
});

/// What was already said, so the next operator does not repeat it an hour later.
/// `read_count` is how many of the inboxes it landed in have opened it - the
/// only feedback there is on whether an announcement was worth sending.
app.get('/v1/internal/gatework/announcements', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ['owner', 'operations_admin', 'content_editor', 'moderator', 'analyst', 'auditor']);
    const rows = await db.query<{ id: string; title: string; body: string; recipient_count: number; read_count: string; created_at: Date; author_name: string }>(
      `SELECT a.id,a.title,a.body,a.recipient_count,a.created_at,
         COALESCE(cp.display_name,'Panel') author_name,
         (SELECT count(*) FROM member_notifications n WHERE n.kind='announcement' AND n.subject_id=a.id AND n.read_at IS NOT NULL) read_count
       FROM member_announcements a
       LEFT JOIN community_profile_projection cp ON cp.user_id=a.created_by
       ORDER BY a.created_at DESC LIMIT 30`,
    );
    return {
      data: rows.rows.map((row) => ({
        id: row.id,
        title: row.title,
        body: row.body,
        recipientCount: row.recipient_count,
        readCount: Number(row.read_count),
        authorName: row.author_name,
        createdAt: row.created_at.toISOString(),
      })),
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'ANNOUNCEMENTS_UNAVAILABLE', message: 'Duyurular okunamadı.' } });
  }
});

// --- Gurbet Yolculugu: rozet katalogu ------------------------------------
//
// Katalogda elli civari rozet var, motorun verebildigi on iki tanesi. Aradaki
// fark bugune kadar hicbir ekranda gorunmuyordu: uye Yolculuk ekraninda "Milli
// Mac Muhtari - milli mac gunu izleme etkinligi paylastin" satirini goruyor ve
// o rozeti verecek bir kural yok. Panelde de gorunmuyordu, cunku panelde rozet
// diye bir sey yoktu.
//
// Bu uc uc su soruyu cevapliyor: hangi rozet gercekten dagitiliyor, hangisi
// katalogda duruyor ama kimseye gitmiyor, ve elle verilmesi gerekenler kime
// verildi.
const JOURNEY_READ_ROLES: GateworkRole[] = ['owner', 'security_admin', 'operations_admin', 'content_editor', 'analyst', 'auditor'];
// Bir rozet vermek, uyenin profiline kalici bir sey yazmak ve ona XP eklemek
// demek. Duyuru kadar geri alinamaz degil - geri alinabiliyor - ama yine de
// platform adina verilen bir karar, o yuzden editorlerde degil.
const JOURNEY_GRANT_ROLES: GateworkRole[] = ['owner', 'operations_admin'];

const badgeGrantSchema = z.object({
  userId: z.string().uuid(),
  // Gerekce zorunlu. Elle verilen rozetin tek denetlenebilir tarafi bu: alti ay
  // sonra "bu madalya neden verilmis" diye bakan kisi cevabi burada bulmali.
  reason: z.string().trim().min(3).max(240),
});

app.get('/v1/internal/gatework/journey/badges', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, JOURNEY_READ_ROLES);
    const [catalogue, totals, levels] = await Promise.all([
      db.query<{
        code: string; title: string; description: string; icon: string; category: string; tier: string;
        points: number; is_secret: boolean; manual_only: boolean; holders: string; manual_holders: string;
        in_progress: string; last_granted_at: Date | null;
      }>(
        `SELECT d.code,d.title,d.description,d.icon,d.category,d.tier,d.points,d.is_secret,d.manual_only,
           (SELECT count(*) FROM member_badges b WHERE b.badge_code=d.code) holders,
           (SELECT count(*) FROM member_badges b WHERE b.badge_code=d.code AND b.granted_by IS NOT NULL) manual_holders,
           -- Sayaci ilerlemis ama henuz almamis uyeler. Sifir olmasi "kimse
           -- ilgilenmiyor" degil, "bu rozetin sayaci hic islemiyor" da olabilir.
           (SELECT count(*) FROM member_badge_progress p WHERE p.badge_code=d.code AND p.current>0) in_progress,
           (SELECT max(b.earned_at) FROM member_badges b WHERE b.badge_code=d.code) last_granted_at
         FROM badge_definitions d
         ORDER BY d.sort_order, d.code`,
      ),
      db.query<{ members: string; granted: string; manual: string }>(
        `SELECT
           (SELECT count(*) FROM member_scores) members,
           (SELECT count(*) FROM member_badges) granted,
           (SELECT count(*) FROM member_badges WHERE granted_by IS NOT NULL) manual`,
      ),
      // Sadece uyesi olan basamaklar. Elli satirlik bos merdiven, kac kisinin
      // nerede oldugunu gostermek yerine gizler.
      db.query<{ level: number; title: string; members: string }>(
        `SELECT s.level, COALESCE(l.title,'Gurbetci') title, count(*) members
           FROM member_scores s LEFT JOIN journey_levels l ON l.level=s.level
          GROUP BY s.level, l.title ORDER BY s.level`,
      ),
    ]);
    const totalRow = totals.rows[0]!;
    const automated = new Set(AUTOMATED_BADGE_CODES);
    return {
      data: {
        members: Number(totalRow.members),
        granted: Number(totalRow.granted),
        manualGrants: Number(totalRow.manual),
        levels: levels.rows.map((row) => ({ level: row.level, title: row.title, members: Number(row.members) })),
        badges: catalogue.rows.map((row) => ({
          code: row.code,
          title: row.title,
          description: row.description,
          icon: row.icon,
          category: row.category,
          tier: row.tier,
          points: row.points,
          isSecret: row.is_secret,
          manualOnly: row.manual_only,
          // Panelin en onemli tek alani. `false` olan bir rozet katalogda duran
          // bir vaat: uye kriterini okuyor, onu saglayacak kural yok.
          automated: automated.has(row.code),
          holders: Number(row.holders),
          manualHolders: Number(row.manual_holders),
          inProgress: Number(row.in_progress),
          lastGrantedAt: row.last_granted_at?.toISOString() ?? null,
        })),
      },
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401)
      .send({ error: { code: 'JOURNEY_BADGES_UNAVAILABLE', message: 'Rozet katalogu okunamadi.' } });
  }
});

/// Bir rozeti kimlerin tasidigi.
///
/// Elle verilmis satirlar icin gerekce ve veren kisi de geliyor: "Dayanisma
/// Madalyasi'ni kime, neden verdik" sorusunun cevabi baska hicbir ekranda yok.
/// Motorun verdigi satirlar da listede, cunku bir rozetin dagitiminin saglikli
/// olup olmadigi ancak ikisi yan yana gorununce anlasilir.
app.get('/v1/internal/gatework/journey/badges/:code/holders', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, JOURNEY_READ_ROLES);
    const code = (request.params as { code: string }).code;
    const rows = await db.query<{
      user_id: string; display_name: string | null; earned_at: Date;
      granted_by: string | null; granted_by_name: string | null; granted_reason: string | null;
    }>(
      `SELECT b.user_id,cp.display_name,b.earned_at,b.granted_by,
              op.display_name granted_by_name,b.granted_reason
         FROM member_badges b
         LEFT JOIN community_profile_projection cp ON cp.user_id=b.user_id
         LEFT JOIN community_profile_projection op ON op.user_id=b.granted_by
        WHERE b.badge_code=$1
        ORDER BY b.earned_at DESC
        LIMIT 100`,
      [code],
    );
    return {
      data: rows.rows.map((row) => ({
        userId: row.user_id,
        // Projeksiyon henuz yetismemis bir uye adsiz gelir. Uydurma bir ad
        // yerine kimligi kaliyor: operatorun elinde en azindan aranabilir bir
        // sey olur.
        displayName: row.display_name,
        earnedAt: row.earned_at.toISOString(),
        grantedBy: row.granted_by,
        grantedByName: row.granted_by_name,
        grantedReason: row.granted_reason,
      })),
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401)
      .send({ error: { code: 'BADGE_HOLDERS_UNAVAILABLE', message: 'Rozeti tasiyanlar okunamadi.' } });
  }
});

/// Elle rozet verir.
///
/// Kurali olan bir rozet buradan verilemez. Motorun dagittigi bir rozeti elle
/// eklemek, o rozeti kazanmis herkesin emegini karsilastirilamaz hale getirir;
/// dahasi sayac hala isliyor olur ve uye ilerleme cubugunu doldururken rozetin
/// zaten kendisinde oldugunu gorur. Reddin sebebi operatore aynen yaziliyor.
app.post('/v1/internal/gatework/journey/badges/:code/grant', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (request, reply) => {
  const code = (request.params as { code: string }).code;
  const client = await db.connect();
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, JOURNEY_GRANT_ROLES);
    const input = badgeGrantSchema.parse(request.body);
    if (AUTOMATED_BADGE_CODES.includes(code)) throw Error('BADGE_AUTOMATED');
    await client.query('BEGIN');
    const definition = await client.query('SELECT 1 FROM badge_definitions WHERE code=$1', [code]);
    if (!definition.rowCount) throw Error('BADGE_UNKNOWN');
    const member = await client.query('SELECT 1 FROM community_profile_projection WHERE user_id=$1', [input.userId]);
    if (!member.rowCount) throw Error('MEMBER_UNKNOWN');
    const granted = await awardBadge(client, input.userId, code, {
      allowManual: true,
      grantedBy: actor.actorId,
      reason: input.reason,
    });
    if (granted) {
      // Sessizce verilen rozet verilmemis sayilir: uye Yolculuk ekranini
      // kendiliginden acmadikca haberi olmaz.
      const row = await client.query<{ id: string }>('SELECT id FROM member_badges WHERE user_id=$1 AND badge_code=$2', [input.userId, code]);
      await client.query(
        `INSERT INTO member_notifications(user_id,kind,subject_id,last_actor_id)
         VALUES($1,'badge_earned',$2,$3) ON CONFLICT(user_id,kind,subject_id) DO NOTHING`,
        [input.userId, row.rows[0]!.id, actor.actorId],
      );
    }
    await auditGateworkOperation({
      actorId: actor.actorId, roles: actor.roles, action: 'journey.badge.grant', targetType: 'member',
      targetId: input.userId, reason: `${code}: ${input.reason}`, requestId: request.id,
      rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded',
    });
    await client.query('COMMIT');
    // `granted:false` bir hata degil: uye rozeti zaten tasiyor. Panelin bunu
    // "verildi" diye gostermesi, olmayan bir degisikligi bildirmek olurdu.
    return reply.code(granted ? 201 : 200).send({ data: { code, userId: input.userId, granted } });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    const message = (error as Error).message;
    const known: Record<string, [number, string]> = {
      FORBIDDEN: [403, 'Bu islem icin yetkin yok.'],
      BADGE_AUTOMATED: [409, 'Bu rozetin otomatik kurali var; elle verilemez.'],
      BADGE_UNKNOWN: [404, 'Boyle bir rozet yok.'],
      MEMBER_UNKNOWN: [404, 'Uye bulunamadi.'],
    };
    const known_entry = known[message] ?? [400, 'Rozet verilemedi.'];
    return reply.code(known_entry[0] as number).send({ error: { code: 'BADGE_GRANT_REJECTED', message: known_entry[1] as string } });
  } finally {
    client.release();
  }
});

/// Yanlis verilmis rozeti geri alir.
///
/// Sadece elle verilmis olanlar. Motorun verdigi rozeti panelden silmek, uyenin
/// gercekten yaptigi bir seyi geri almak olurdu; motor da bir sonraki tetikte
/// ayni rozeti yeniden verirdi.
app.delete('/v1/internal/gatework/journey/badges/:code/holders/:userId', { config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (request, reply) => {
  const params = request.params as { code: string; userId: string };
  const client = await db.connect();
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, JOURNEY_GRANT_ROLES);
    await client.query('BEGIN');
    const held = await client.query<{ granted_by: string | null; id: string }>(
      'SELECT granted_by,id FROM member_badges WHERE user_id=$1 AND badge_code=$2',
      [params.userId, params.code],
    );
    if (!held.rowCount) throw Error('BADGE_NOT_HELD');
    if (held.rows[0]!.granted_by === null) throw Error('BADGE_EARNED');
    // Zildeki satir da gidiyor: geri alinmis bir rozetin kutlamasi ekranda
    // kalirsa uye onu hala tasidigini sanir.
    await client.query("DELETE FROM member_notifications WHERE user_id=$1 AND kind='badge_earned' AND subject_id=$2", [params.userId, held.rows[0]!.id]);
    await revokeBadge(client, params.userId, params.code);
    await auditGateworkOperation({
      actorId: actor.actorId, roles: actor.roles, action: 'journey.badge.revoke', targetType: 'member',
      targetId: params.userId, reason: params.code, requestId: request.id,
      rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded',
    });
    await client.query('COMMIT');
    return reply.code(204).send();
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    const message = (error as Error).message;
    const known: Record<string, [number, string]> = {
      FORBIDDEN: [403, 'Bu islem icin yetkin yok.'],
      BADGE_NOT_HELD: [404, 'Uyede bu rozet yok.'],
      BADGE_EARNED: [409, 'Bu rozet kazanilmis; panelden geri alinamaz.'],
    };
    const known_entry = known[message] ?? [400, 'Rozet geri alinamadi.'];
    return reply.code(known_entry[0] as number).send({ error: { code: 'BADGE_REVOKE_REJECTED', message: known_entry[1] as string } });
  } finally {
    client.release();
  }
});

// --- Analytics and locality ----------------------------------------------
// The console's Analitik ve Konum screen. Two rules shape everything below,
// and both come from how locality was designed in migration 008: locality is a
// chosen city/state preference, never a continuous exact trail. So:
//
// 1. viewer_location_projection.approximate_cell and community_posts.location_cell
//    are per-member coordinates. Nothing here reads them. What an operator gets
//    is the city and state a member chose to publish, never where they were.
// 2. A count is aggregate only if the bucket is big enough to hide in. One
//    member in a city, next to the Uyeler screen's city filter, names a person.
//    So buckets under ANALYTICS_MIN_BUCKET are not shown one by one; they are
//    folded into a single "esik alti" total, which keeps the sum honest without
//    handing back the small bucket.
//
// Read-only, and no audit row: these are counts of nobody in particular, and
// auditing a dashboard load would bury the acts that matter under page views.
// content_editor and moderator are not on the list - neither role needs
// population figures to do its job.
const ANALYTICS_READ_ROLES: GateworkRole[] = ['owner', 'security_admin', 'operations_admin', 'analyst', 'auditor'];
const ANALYTICS_MIN_BUCKET = LOCALITY_MIN_BUCKET;

// Weeks, not days: a daily curve over a community this size is mostly noise,
// and generate_series is here so an empty week is a zero on the chart instead
// of a gap that reads as "no data".
const ANALYTICS_WEEKS = 12;
const analyticsSeriesSql = (source: string, extra = '') => `
  SELECT w.week_start, count(s.id)::int total
  FROM generate_series(date_trunc('week', now()) - interval '${ANALYTICS_WEEKS - 1} weeks', date_trunc('week', now()), interval '1 week') w(week_start)
  LEFT JOIN ${source} s ON date_trunc('week', s.created_at) = w.week_start ${extra}
  GROUP BY w.week_start ORDER BY w.week_start`;

app.get('/v1/internal/gatework/analytics/overview', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ANALYTICS_READ_ROLES);
    const totals = await db.query<{ members: string; located_members: string; posts: string; posts_7d: string; comments_7d: string; topics: string; replies_7d: string; active_listings: string; live_stories: string }>(
      `SELECT (SELECT count(*) FROM community_profile_projection) members,
              (SELECT count(*) FROM community_profile_projection WHERE region_code IS NOT NULL) located_members,
              (SELECT count(*) FROM community_posts WHERE deleted_at IS NULL AND moderation_state='active') posts,
              (SELECT count(*) FROM community_posts WHERE created_at>now()-interval '7 days' AND deleted_at IS NULL) posts_7d,
              (SELECT count(*) FROM community_comments WHERE created_at>now()-interval '7 days' AND deleted_at IS NULL) comments_7d,
              (SELECT count(*) FROM forum_topics WHERE deleted_at IS NULL AND moderation_state='active') topics,
              (SELECT count(*) FROM forum_replies WHERE created_at>now()-interval '7 days' AND deleted_at IS NULL) replies_7d,
              (SELECT count(*) FROM marketplace_listings WHERE status='active') active_listings,
              (SELECT count(*) FROM stories WHERE expires_at>now()) live_stories`,
    );
    const [posts, topics, listings, mutes] = await Promise.all([
      db.query<{ week_start: Date; total: number }>(analyticsSeriesSql('community_posts', 'AND s.deleted_at IS NULL')),
      db.query<{ week_start: Date; total: number }>(analyticsSeriesSql('forum_topics', 'AND s.deleted_at IS NULL')),
      db.query<{ week_start: Date; total: number }>(analyticsSeriesSql('marketplace_listings')),
      // Uyenin zilde neyi kapattigi. Toplam sayilar; kimin kapattigi degil,
      // kac kisinin kapattigi. Panelin bunu bilmesi lazim: bir turu herkesin
      // kapatmis olmasi, o bildirimin rahatsiz ettiginin tek isareti.
      db.query<{ kind: string; members: string }>(
        `SELECT kind, count(*) members FROM member_notification_preferences WHERE enabled=false GROUP BY kind`,
      ),
    ]);
    const row = totals.rows[0]!;
    const mutedByKind: Record<string, number> = {};
    for (const kind of MUTABLE_NOTIFICATION_KINDS) mutedByKind[kind] = 0;
    for (const mute of mutes.rows) {
      if (mute.kind in mutedByKind) mutedByKind[mute.kind] = Number(mute.members);
    }
    return {
      data: {
        members: Number(row.members),
        locatedMembers: Number(row.located_members),
        posts: Number(row.posts),
        postsLast7Days: Number(row.posts_7d),
        commentsLast7Days: Number(row.comments_7d),
        forumTopics: Number(row.topics),
        forumRepliesLast7Days: Number(row.replies_7d),
        activeListings: Number(row.active_listings),
        liveStories: Number(row.live_stories),
        // Uyeler paydasi ayrica gonderiliyor: "412 kisi kapatmis" tek basina
        // buyuk mu kucuk mu belli degil, toplam uye sayisiyla birlikte belli.
        notificationMutes: { totalMembers: Number(row.members), byKind: mutedByKind },
        // Three series, one week axis: the console draws them together, so they
        // are built from the same generate_series and are guaranteed aligned.
        weeks: posts.rows.map((week, index) => ({
          weekStart: week.week_start.toISOString(),
          posts: week.total,
          forumTopics: topics.rows[index]?.total ?? 0,
          listings: listings.rows[index]?.total ?? 0,
        })),
      },
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'ANALYTICS_OVERVIEW_UNAVAILABLE', message: 'Analitik özeti okunamadı.' } });
  }
});

// Where the community actually is. Members come from the profile projection,
// posts and listings from their own region_code, and they are merged per bucket
// rather than joined in SQL - a state with listings and no resident profile has
// to still appear, and an inner join would hide exactly that.
app.get('/v1/internal/gatework/analytics/locations', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, ANALYTICS_READ_ROLES);
    const [members, posts, listings, cityMembers, cityListings] = await Promise.all([
      db.query<{ region_code: string; total: number }>("SELECT region_code,count(*)::int total FROM community_profile_projection WHERE region_code IS NOT NULL GROUP BY 1"),
      db.query<{ region_code: string; total: number }>("SELECT region_code,count(*)::int total FROM community_posts WHERE region_code IS NOT NULL AND deleted_at IS NULL AND moderation_state='active' GROUP BY 1"),
      db.query<{ region_code: string; total: number }>("SELECT region_code,count(*)::int total FROM marketplace_listings WHERE region_code IS NOT NULL AND status='active' GROUP BY 1"),
      db.query<{ region_code: string; city: string; total: number }>("SELECT region_code,city,count(*)::int total FROM community_profile_projection WHERE region_code IS NOT NULL AND city IS NOT NULL GROUP BY 1,2"),
      db.query<{ region_code: string; city: string; total: number }>("SELECT region_code,city,count(*)::int total FROM marketplace_listings WHERE region_code IS NOT NULL AND city IS NOT NULL AND status='active' GROUP BY 1,2"),
    ]);
    const regions = new Map<string, LocalityBucket>();
    const take = (key: string, field: keyof LocalityBucket, total: number) => {
      const bucket = regions.get(key) ?? emptyLocalityBucket();
      bucket[field] += total;
      regions.set(key, bucket);
    };
    for (const row of members.rows) take(row.region_code, 'members', row.total);
    for (const row of posts.rows) take(row.region_code, 'posts', row.total);
    for (const row of listings.rows) take(row.region_code, 'listings', row.total);
    // Cities are keyed case-insensitively: "Paterson" and "paterson" are one
    // place, and two rows of two members each must not slip past a threshold
    // that four members would not have.
    const cities = new Map<string, LocalityBucket & { city: string; regionCode: string }>();
    const takeCity = (regionCode: string, city: string, field: keyof LocalityBucket, total: number) => {
      const key = `${regionCode}/${city.toLocaleLowerCase('tr-TR')}`;
      const bucket = cities.get(key) ?? { ...emptyLocalityBucket(), city, regionCode };
      bucket[field] += total;
      cities.set(key, bucket);
    };
    for (const row of cityMembers.rows) takeCity(row.region_code, row.city, 'members', row.total);
    for (const row of cityListings.rows) takeCity(row.region_code, row.city, 'listings', row.total);

    const regionResult = suppressSmallBuckets([...regions].map(([regionCode, bucket]) => ({ regionCode, ...bucket })), ANALYTICS_MIN_BUCKET);
    const cityResult = suppressSmallBuckets([...cities.values()], ANALYTICS_MIN_BUCKET);
    const unplaced = await db.query<{ members: string; posts: string; listings: string }>(
      `SELECT (SELECT count(*) FROM community_profile_projection WHERE region_code IS NULL) members,
              (SELECT count(*) FROM community_posts WHERE region_code IS NULL AND deleted_at IS NULL AND moderation_state='active') posts,
              (SELECT count(*) FROM marketplace_listings WHERE region_code IS NULL AND status='active') listings`,
    );
    const missing = unplaced.rows[0]!;
    return {
      data: {
        threshold: ANALYTICS_MIN_BUCKET,
        regions: regionResult.shown,
        cities: cityResult.shown.map((row) => ({ city: row.city, regionCode: row.regionCode, members: row.members, listings: row.listings })),
        suppressedRegions: regionResult.suppressed,
        suppressedCities: { buckets: cityResult.suppressed.buckets, members: cityResult.suppressed.members, listings: cityResult.suppressed.listings },
        // Not a privacy number, a data quality one: how much of the community
        // has told us nothing about where it is.
        unplaced: { members: Number(missing.members), posts: Number(missing.posts), listings: Number(missing.listings) },
      },
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401).send({ error: { code: 'ANALYTICS_LOCATIONS_UNAVAILABLE', message: 'Konum dağılımı okunamadı.' } });
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

// --- Yardim ve Destek ---------------------------------------------------
//
// Uyenin platformun kendisiyle konustugu tek yer. Sikayet mekanizmasindan
// ayri: o baska bir uyeyi isaret ediyor, bu bizi.
//
// Bir sey bilerek yapilmadi: kisitlanmis uye de destek yazabiliyor. Susturulan
// ya da askiya alinan bir uyenin "neden" diye sorabilecegi bir yer kalmazsa,
// karari itiraz edilemez hale getirmis oluruz. Kisitlama paylasimi durdurur,
// itirazi degil.
const SUPPORT_READ_ROLES: GateworkRole[] = ['owner', 'security_admin', 'operations_admin', 'moderator', 'auditor'];
const SUPPORT_ACT_ROLES: GateworkRole[] = ['owner', 'security_admin', 'operations_admin', 'moderator'];

// Ayni anda acik durabilecek talep sayisi. Sinir yoksa tek bir uye kuyrugu
// dolduruyor ve sirada bekleyen herkesin cevabi geciciyor.
const SUPPORT_OPEN_LIMIT = 5;

const supportCreateBody = z.object({
  topic: z.enum(['account', 'safety', 'marketplace', 'content', 'technical', 'other']),
  subject: z.string().trim().min(3).max(120),
  body: z.string().trim().min(10).max(4000),
  appVersion: z.string().trim().max(40).optional(),
  platform: z.enum(['android', 'ios', 'web']).optional(),
  clientToken: z.string().uuid(),
});
const supportReplyBody = z.object({ body: z.string().trim().min(2).max(4000) });
const supportStaffReplyBody = z.object({ body: z.string().trim().min(2).max(4000), close: z.boolean().default(false) });
const supportCloseBody = z.object({ reason: z.string().trim().min(5).max(500) });

const supportRequestRow = (row: {
  id: string; topic: string; subject: string; status: string; app_version: string | null; platform: string | null;
  created_at: Date; updated_at: Date; last_member_at: Date; last_staff_at: Date | null; closed_at: Date | null; closure_reason: string | null;
}) => ({
  id: row.id,
  topic: row.topic,
  subject: row.subject,
  status: row.status,
  appVersion: row.app_version,
  platform: row.platform,
  createdAt: row.created_at.toISOString(),
  updatedAt: row.updated_at.toISOString(),
  lastMemberAt: row.last_member_at.toISOString(),
  lastStaffAt: row.last_staff_at?.toISOString() ?? null,
  closedAt: row.closed_at?.toISOString() ?? null,
  closureReason: row.closure_reason,
});

app.post('/v1/support/requests', { config: { rateLimit: { max: 5, timeWindow: '10 minutes' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const userId = await viewer(request.headers);
    const input = supportCreateBody.parse(request.body);
    await client.query('BEGIN');
    // Ayni form iki kez gonderildiginde ikinci gonderim yeni bir talep degil,
    // birincinin kendisi. Uyeye "gonderildi" demek ve arkada iki kayit acmak,
    // operatorun ayni soruyu iki kez cevaplamasi demek.
    const existing = await client.query<{ id: string }>(
      'SELECT id FROM support_requests WHERE member_id=$1 AND client_token=$2',
      [userId, input.clientToken],
    );
    if (existing.rows[0]) {
      await client.query('COMMIT');
      return reply.code(200).send({ data: { id: existing.rows[0].id, duplicate: true } });
    }
    const open = await client.query<{ count: string }>(
      "SELECT count(*) count FROM support_requests WHERE member_id=$1 AND status<>'closed'",
      [userId],
    );
    if (Number(open.rows[0]?.count ?? 0) >= SUPPORT_OPEN_LIMIT) {
      await client.query('ROLLBACK');
      return reply.code(409).send({ error: { code: 'SUPPORT_TOO_MANY_OPEN', message: `Aynı anda en fazla ${SUPPORT_OPEN_LIMIT} açık talebin olabilir. Yeni bir talep açmak için önce mevcut taleplerinden birinin yanıtını bekle.` } });
    }
    const created = await client.query<{ id: string }>(
      `INSERT INTO support_requests(member_id,topic,subject,app_version,platform,client_token)
       VALUES($1,$2,$3,$4,$5,$6) RETURNING id`,
      [userId, input.topic, input.subject, input.appVersion ?? null, input.platform ?? null, input.clientToken],
    );
    const id = created.rows[0]!.id;
    await client.query(
      "INSERT INTO support_messages(request_id,author_kind,author_id,body) VALUES($1,'member',$2,$3)",
      [id, userId, input.body],
    );
    await client.query('COMMIT');
    return reply.code(201).send({ data: { id, duplicate: false } });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'SUPPORT_REQUEST_REJECTED', message: 'Destek talebi gönderilemedi.' } });
  } finally {
    client.release();
  }
});

app.get('/v1/support/requests', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const rows = await db.query(
      `SELECT id,topic,subject,status,app_version,platform,created_at,updated_at,last_member_at,last_staff_at,closed_at,closure_reason
         FROM support_requests WHERE member_id=$1 ORDER BY updated_at DESC LIMIT 50`,
      [userId],
    );
    return { data: rows.rows.map((row) => supportRequestRow(row as Parameters<typeof supportRequestRow>[0])) };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'SUPPORT_REQUESTS_UNAVAILABLE', message: 'Destek taleplerin okunamadı.' } });
  }
});

app.get('/v1/support/requests/:id', async (request, reply) => {
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const found = await db.query(
      `SELECT id,topic,subject,status,app_version,platform,created_at,updated_at,last_member_at,last_staff_at,closed_at,closure_reason
         FROM support_requests WHERE id=$1 AND member_id=$2`,
      [id, userId],
    );
    if (!found.rows.length) return reply.code(404).send({ error: { code: 'SUPPORT_REQUEST_NOT_FOUND', message: 'Destek talebi bulunamadı.' } });
    const messages = await db.query<{ id: string; author_kind: string; body: string; created_at: Date }>(
      'SELECT id,author_kind,body,created_at FROM support_messages WHERE request_id=$1 ORDER BY created_at ASC',
      [id],
    );
    return {
      data: {
        ...supportRequestRow(found.rows[0] as Parameters<typeof supportRequestRow>[0]),
        // Operatorun kimligi uyeye gitmiyor: cevap veren kisi degil, platform.
        // Bir destek yanitinin altinda calisanin adi, uyenin o kisiyi profilden
        // bulmasi demek.
        messages: messages.rows.map((message) => ({
          id: message.id,
          from: message.author_kind === 'staff' ? 'destek' : 'uye',
          body: message.body,
          createdAt: message.created_at.toISOString(),
        })),
      },
    };
  } catch (error) {
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'SUPPORT_REQUEST_UNAVAILABLE', message: 'Destek talebi okunamadı.' } });
  }
});

app.post('/v1/support/requests/:id/messages', { config: { rateLimit: { max: 20, timeWindow: '10 minutes' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const userId = await viewer(request.headers);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = supportReplyBody.parse(request.body);
    await client.query('BEGIN');
    // Kapali talebe yazilamaz. Yazilabilseydi kimse fark etmeden konusma
    // devam ederdi: kapali talep hicbir kuyrukta gorunmuyor.
    const updated = await client.query(
      "UPDATE support_requests SET status='open',last_member_at=now(),updated_at=now() WHERE id=$1 AND member_id=$2 AND status<>'closed'",
      [id, userId],
    );
    if (!updated.rowCount) {
      await client.query('ROLLBACK');
      return reply.code(409).send({ error: { code: 'SUPPORT_REQUEST_CLOSED', message: 'Bu talep kapanmış. Yeni bir talep açabilirsin.' } });
    }
    await client.query("INSERT INTO support_messages(request_id,author_kind,author_id,body) VALUES($1,'member',$2,$3)", [id, userId, input.body]);
    await client.query('COMMIT');
    return reply.code(204).send();
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'SUPPORT_MESSAGE_REJECTED', message: 'Mesaj gönderilemedi.' } });
  } finally {
    client.release();
  }
});

// Panel tarafi. Kuyruk sirasi cevap bekleme suresine gore: uc gundur bekleyen
// talep, bu sabah gelenin onunde.
app.get('/v1/internal/gatework/support/requests', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, SUPPORT_READ_ROLES);
    const input = z.object({
      state: z.enum(['waiting', 'open', 'closed', 'all']).default('waiting'),
      topic: z.enum(['account', 'safety', 'marketplace', 'content', 'technical', 'other']).optional(),
      limit: z.coerce.number().int().min(1).max(100).default(50),
    }).parse(request.query);
    const rows = await db.query(
      `SELECT r.id,r.topic,r.subject,r.status,r.app_version,r.platform,r.created_at,r.updated_at,
              r.last_member_at,r.last_staff_at,r.closed_at,r.closure_reason,
              r.member_id,cp.display_name member_name,
              (SELECT m.body FROM support_messages m WHERE m.request_id=r.id ORDER BY m.created_at DESC LIMIT 1) last_body,
              (SELECT count(*) FROM support_messages m WHERE m.request_id=r.id) message_count
         FROM support_requests r
         LEFT JOIN community_profile_projection cp ON cp.user_id=r.member_id
        WHERE ($1='all'
               OR ($1='waiting' AND r.status='open')
               OR ($1='open' AND r.status<>'closed')
               OR ($1='closed' AND r.status='closed'))
          AND ($2::text IS NULL OR r.topic=$2)
        ORDER BY (r.status='open') DESC, r.last_member_at ASC
        LIMIT $3`,
      [input.state, input.topic ?? null, input.limit],
    );
    return {
      data: rows.rows.map((row) => {
        const typed = row as Parameters<typeof supportRequestRow>[0] & { member_id: string; member_name: string | null; last_body: string | null; message_count: string };
        return {
          ...supportRequestRow(typed),
          memberId: typed.member_id,
          // Topluluk projeksiyonu bu uyeyi henuz gormemis olabilir; adi
          // uydurmak yerine bos birakiliyor, ekran "ad gelmedi" diyor.
          memberName: typed.member_name,
          lastMessage: typed.last_body,
          messageCount: Number(typed.message_count),
        };
      }),
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401)
      .send({ error: { code: 'SUPPORT_QUEUE_UNAVAILABLE', message: 'Destek kuyruğu okunamadı.' } });
  }
});

app.get('/v1/internal/gatework/support/requests/:id', async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, SUPPORT_READ_ROLES);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const found = await db.query(
      `SELECT r.id,r.topic,r.subject,r.status,r.app_version,r.platform,r.created_at,r.updated_at,
              r.last_member_at,r.last_staff_at,r.closed_at,r.closure_reason,r.member_id,cp.display_name member_name
         FROM support_requests r
         LEFT JOIN community_profile_projection cp ON cp.user_id=r.member_id
        WHERE r.id=$1`,
      [id],
    );
    if (!found.rows.length) return reply.code(404).send({ error: { code: 'SUPPORT_REQUEST_NOT_FOUND', message: 'Destek talebi bulunamadı.' } });
    const messages = await db.query<{ id: string; author_kind: string; author_id: string; author_roles: string[] | null; body: string; created_at: Date }>(
      'SELECT id,author_kind,author_id,author_roles,body,created_at FROM support_messages WHERE request_id=$1 ORDER BY created_at ASC',
      [id],
    );
    const typed = found.rows[0] as Parameters<typeof supportRequestRow>[0] & { member_id: string; member_name: string | null };
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'support.request.read', targetType: 'support_request', targetId: id, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    return {
      data: {
        ...supportRequestRow(typed),
        memberId: typed.member_id,
        memberName: typed.member_name,
        messages: messages.rows.map((message) => ({
          id: message.id,
          authorKind: message.author_kind,
          // Panelde cevabi kimin yazdigi duruyor - uyeye gitmiyor, ama ekip
          // ici sorumluluk icin gerekli.
          authorId: message.author_id,
          authorRoles: message.author_roles ?? [],
          body: message.body,
          createdAt: message.created_at.toISOString(),
        })),
      },
    };
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : 401)
      .send({ error: { code: 'SUPPORT_REQUEST_UNAVAILABLE', message: 'Destek talebi okunamadı.' } });
  }
});

app.post('/v1/internal/gatework/support/requests/:id/reply', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (request, reply) => {
  const client = await db.connect();
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, SUPPORT_ACT_ROLES);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = supportStaffReplyBody.parse(request.body);
    await client.query('BEGIN');
    const updated = await client.query<{ member_id: string }>(
      `UPDATE support_requests
          SET status=CASE WHEN $2 THEN 'closed' ELSE 'answered' END,
              last_staff_at=now(),updated_at=now(),
              closed_at=CASE WHEN $2 THEN now() ELSE closed_at END,
              closed_by=CASE WHEN $2 THEN $3::uuid ELSE closed_by END
        WHERE id=$1 AND status<>'closed'
        RETURNING member_id`,
      [id, input.close, actor.actorId],
    );
    if (!updated.rowCount) {
      await client.query('ROLLBACK');
      return reply.code(409).send({ error: { code: 'SUPPORT_REQUEST_CLOSED', message: 'Bu talep kapanmış; yeniden yanıtlanamaz.' } });
    }
    await client.query(
      "INSERT INTO support_messages(request_id,author_kind,author_id,author_roles,body) VALUES($1,'staff',$2,$3,$4)",
      [id, actor.actorId, actor.roles, input.body],
    );
    // Zil. Cevabi gormek icin uyenin destek ekranini kendiliginden acmasini
    // beklemek, cevabi gondermemekle ayni sey.
    await client.query(
      `INSERT INTO member_notifications(user_id,kind,subject_id,last_actor_id)
       VALUES($1,'support_answer',$2,$3)
       ON CONFLICT(user_id,kind,subject_id) DO UPDATE SET updated_at=now(),read_at=NULL,last_actor_id=EXCLUDED.last_actor_id`,
      [updated.rows[0]!.member_id, id, actor.actorId],
    );
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: input.close ? 'support.request.reply_and_close' : 'support.request.reply', targetType: 'support_request', targetId: id, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    await client.query('COMMIT');
    return reply.code(204).send();
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'SUPPORT_REPLY_REJECTED', message: 'Yanıt gönderilemedi.' } });
  } finally {
    client.release();
  }
});

// Yanitsiz kapatma. Yanlislikla acilmis ya da kendi kendine cozulmus talepler
// icin; sebep zorunlu cunku uye bu cumleyi goruyor.
app.post('/v1/internal/gatework/support/requests/:id/close', { config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (request, reply) => {
  try {
    const actor = await gateworkActor(request.headers);
    requireGateworkRole(actor, SUPPORT_ACT_ROLES);
    const id = z.string().uuid().parse((request.params as { id: string }).id);
    const input = supportCloseBody.parse(request.body);
    const updated = await db.query(
      "UPDATE support_requests SET status='closed',closed_at=now(),closed_by=$2,closure_reason=$3,updated_at=now() WHERE id=$1 AND status<>'closed'",
      [id, actor.actorId, input.reason],
    );
    if (!updated.rowCount) return reply.code(409).send({ error: { code: 'SUPPORT_REQUEST_CLOSED', message: 'Talep zaten kapalı.' } });
    await auditGateworkOperation({ actorId: actor.actorId, roles: actor.roles, action: 'support.request.close', targetType: 'support_request', targetId: id, reason: input.reason, requestId: request.id, rayId: request.headers['cf-ray'] as string | undefined, outcome: 'succeeded' });
    return reply.code(204).send();
  } catch (error) {
    return reply.code((error as Error).message === 'FORBIDDEN' ? 403 : (error as Error).message === 'UNAUTHORIZED' ? 401 : 400)
      .send({ error: { code: 'SUPPORT_CLOSE_REJECTED', message: 'Talep kapatılamadı.' } });
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
