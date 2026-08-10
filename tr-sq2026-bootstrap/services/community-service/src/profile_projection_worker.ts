import { ServiceBusClient, ServiceBusReceiver } from '@azure/service-bus';
import { createDatabasePool } from './database.js';

const connectionString = process.env.AZURE_SERVICE_BUS_CONNECTION_STRING;
const queueName = process.env.AZURE_COMMUNITY_PROFILE_QUEUE_NAME;
if (!connectionString || !queueName) throw new Error('Missing AZURE_SERVICE_BUS_CONNECTION_STRING or AZURE_COMMUNITY_PROFILE_QUEUE_NAME');

const db = createDatabasePool();
const sbClient = new ServiceBusClient(connectionString);
const receiver = sbClient.createReceiver(queueName, { receiveMode: 'peekLock' });

type Event = { eventId: string; eventType: 'community.profile_upserted' | 'community.member_capabilities_upserted'; payload: { userId: string; displayName?: string; city?: string; countryCode?: string; regionCode?: string | null; interests?: string[]; identityVerified?: boolean; auctionSellerEligible?: boolean } };

async function processEvent(event: Event) {
  if (!['community.profile_upserted','community.member_capabilities_upserted'].includes(event.eventType)) return;
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
      await client.query(
        `INSERT INTO community_profile_projection(user_id,display_name,city,region_code,interests)
         VALUES($1,$2,$3,$4,$5)
         ON CONFLICT(user_id) DO UPDATE SET display_name=EXCLUDED.display_name,city=EXCLUDED.city,region_code=EXCLUDED.region_code,interests=EXCLUDED.interests,updated_at=now()`,
        [input.userId, input.displayName, input.city, regionCode, input.interests],
      );
    }
    if (inserted.rowCount && event.eventType === 'community.member_capabilities_upserted') {
      await client.query(`INSERT INTO member_capabilities(user_id,identity_verified,auction_seller_eligible) VALUES($1,$2,$3) ON CONFLICT(user_id) DO UPDATE SET identity_verified=EXCLUDED.identity_verified,auction_seller_eligible=EXCLUDED.auction_seller_eligible,updated_at=now()`, [event.payload.userId, event.payload.identityVerified === true, event.payload.auctionSellerEligible === true]);
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
