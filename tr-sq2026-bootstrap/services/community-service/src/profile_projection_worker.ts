import { ServiceBusClient, ServiceBusReceiver } from '@azure/service-bus';
import { createDatabasePool } from './database.js';
import { awardBadge } from './journey.js';

const connectionString = process.env.AZURE_SERVICE_BUS_CONNECTION_STRING;
const queueName = process.env.AZURE_COMMUNITY_PROFILE_QUEUE_NAME;
if (!connectionString || !queueName) throw new Error('Missing AZURE_SERVICE_BUS_CONNECTION_STRING or AZURE_COMMUNITY_PROFILE_QUEUE_NAME');

const db = createDatabasePool();
const sbClient = new ServiceBusClient(connectionString);
const receiver = sbClient.createReceiver(queueName, { receiveMode: 'peekLock' });

type Event = { eventId: string; eventType: 'community.profile_upserted' | 'community.member_capabilities_upserted' | 'community.account_status_changed'; payload: { userId: string; displayName?: string; city?: string; countryCode?: string; regionCode?: string | null; interests?: string[]; primaryIntent?: string | null; bornInUs?: boolean; arrivedMonth?: number | null; arrivedYear?: number | null; originCountry?: string | null; originCity?: string | null; identityVerified?: boolean; auctionSellerEligible?: boolean; status?: 'active' | 'frozen' | 'deletion_pending' } };

/// Identity already range-checks these, but a projection that trusts its
/// producer stores whatever a replayed bad payload contains. Out-of-range values
/// become NULL instead of failing the event: an implausible arrival year is not
/// worth wedging the queue over, and the profile simply shows no arrival date.
const monthOrNull = (value: number | null | undefined) =>
  typeof value === 'number' && value >= 1 && value <= 12 ? value : null;
const yearOrNull = (value: number | null | undefined) =>
  typeof value === 'number' && value >= 1950 && value <= 2100 ? value : null;
const countryOrNull = (value: string | null | undefined) =>
  typeof value === 'string' && /^[A-Za-z]{2}$/.test(value) ? value.toUpperCase() : null;
const originCityOrNull = (value: string | null | undefined) => {
  const trimmed = value?.trim();
  return trimmed && trimmed.length >= 2 && trimmed.length <= 100 ? trimmed : null;
};

async function processEvent(event: Event) {
  if (!['community.profile_upserted','community.member_capabilities_upserted','community.account_status_changed'].includes(event.eventType)) return;
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const inserted = await client.query('INSERT INTO processed_identity_events(event_id) VALUES($1) ON CONFLICT DO NOTHING RETURNING event_id', [event.eventId]);
    if (inserted.rowCount && event.eventType === 'community.profile_upserted') {
      const input = event.payload;
      if (!input.displayName || !input.city || !input.interests) throw new Error('Invalid profile projection event');
      // A member living outside the US has no state code. Locality ranking
      // simply skips them; rejecting the event would wedge the queue instead.
      const regionCode = input.regionCode ? input.regionCode.toUpperCase() : null;
      // Someone born in the US has no arrival date and no country of origin.
      // Dropping them here as well as in identity means a stale producer cannot
      // leave the profile claiming both.
      const bornInUs = input.bornInUs === true;
      await client.query(
        `INSERT INTO community_profile_projection(user_id,display_name,city,region_code,interests,born_in_us,arrived_month,arrived_year,origin_country,origin_city,primary_intent)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
         ON CONFLICT(user_id) DO UPDATE SET display_name=EXCLUDED.display_name,city=EXCLUDED.city,region_code=EXCLUDED.region_code,interests=EXCLUDED.interests,born_in_us=EXCLUDED.born_in_us,arrived_month=EXCLUDED.arrived_month,arrived_year=EXCLUDED.arrived_year,origin_country=EXCLUDED.origin_country,origin_city=EXCLUDED.origin_city,primary_intent=EXCLUDED.primary_intent,updated_at=now()`,
        [
          input.userId,
          input.displayName,
          input.city,
          regionCode,
          input.interests,
          bornInUs,
          bornInUs ? null : monthOrNull(input.arrivedMonth),
          bornInUs ? null : yearOrNull(input.arrivedYear),
          bornInUs ? null : countryOrNull(input.originCountry),
          bornInUs ? null : originCityOrNull(input.originCity),
          input.primaryIntent ?? null,
        ],
      );
      // The leaderboard reads locality straight off member_scores so that
      // "this week in Paterson" is an index scan rather than a join over every
      // member in the state. It is a cache of the line above, refreshed in the
      // same transaction so the two can never disagree.
      await client.query(
        `INSERT INTO member_scores(user_id,city,region_code)
         VALUES($1,$2,$3)
         ON CONFLICT(user_id) DO UPDATE SET city=EXCLUDED.city,region_code=EXCLUDED.region_code,updated_at=now()`,
        [input.userId, input.city, regionCode],
      );
      // Finishing onboarding is the first task on the journey map, and it is
      // the one moment we know the member picked a city.
      await awardBadge(client, input.userId, 'jfk_welcomed');
    }
    // Hesabin acilip kapanmasi. Projeksiyon satiri yoksa hicbir sey yapilmiyor:
    // henuz kurulumu bitirmemis bir uyenin burada satiri olmaz ve olmayan bir
    // satiri "kapali" diye yaratmak, hic var olmamis bir profili kapatilmis
    // gibi gostermek olurdu.
    if (inserted.rowCount && event.eventType === 'community.account_status_changed') {
      const status = event.payload.status;
      if (status !== 'active' && status !== 'frozen' && status !== 'deletion_pending') {
        throw new Error('Invalid account status event');
      }
      await client.query(
        status === 'active'
          ? 'UPDATE community_profile_projection SET closed_at=NULL,closed_reason=NULL,updated_at=now() WHERE user_id=$1'
          : 'UPDATE community_profile_projection SET closed_at=COALESCE(closed_at, now()),closed_reason=$2,updated_at=now() WHERE user_id=$1',
        status === 'active' ? [event.payload.userId] : [event.payload.userId, status],
      );
    }
    if (inserted.rowCount && event.eventType === 'community.member_capabilities_upserted') {
      await client.query(`INSERT INTO member_capabilities(user_id,identity_verified,auction_seller_eligible) VALUES($1,$2,$3) ON CONFLICT(user_id) DO UPDATE SET identity_verified=EXCLUDED.identity_verified,auction_seller_eligible=EXCLUDED.auction_seller_eligible,updated_at=now()`, [event.payload.userId, event.payload.identityVerified === true, event.payload.auctionSellerEligible === true]);
      // I-94 Temiz is exactly "the identity checks passed", so it is awarded
      // where that becomes true rather than being inferred later by a poll.
      if (event.payload.identityVerified === true) {
        await awardBadge(client, event.payload.userId, 'i94_clean');
      }
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
}

async function run() {
  receiver.subscribe({
    processMessage: async (message) => {
      try {
        const event = JSON.parse(message.body ? JSON.stringify(message.body) : '{}') as Event;
        // Service Bus already delivers parsed body for JSON messages; if body is an object, use it directly.
        const parsedEvent = (typeof message.body === 'string' ? JSON.parse(message.body) : message.body) as Event;
        await processEvent(parsedEvent);
        await receiver.completeMessage(message);
      } catch (error) {
        await receiver.abandonMessage(message);
        console.error('Identity profile projection delivery failed', error instanceof Error ? error.name : 'unknown');
      }
    },
    processError: async (error) => {
      console.error('Service Bus receiver error', error.error.message);
    }
  });
}

void run();
process.on('SIGTERM', async () => {
  await receiver.close();
  await sbClient.close();
});
