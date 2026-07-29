import { DeleteMessageCommand, ReceiveMessageCommand, SQSClient } from '@aws-sdk/client-sqs';
import { createDatabasePool } from './database.js';

const queueUrl = process.env.IDENTITY_PROFILE_PROJECTION_QUEUE_URL;
if (!queueUrl) throw new Error('Missing IDENTITY_PROFILE_PROJECTION_QUEUE_URL');

const db = createDatabasePool();
const sqs = new SQSClient({});
type Event = { eventId: string; eventType: 'community.profile_upserted' | 'community.member_capabilities_upserted'; payload: { userId: string; displayName?: string; city?: string; regionCode?: string; interests?: string[]; identityVerified?: boolean; auctionSellerEligible?: boolean } };

async function processEvent(event: Event) {
  if (!['community.profile_upserted','community.member_capabilities_upserted'].includes(event.eventType)) return;
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const inserted = await client.query('INSERT INTO processed_identity_events(event_id) VALUES($1) ON CONFLICT DO NOTHING RETURNING event_id', [event.eventId]);
    if (inserted.rowCount && event.eventType === 'community.profile_upserted') {
      const input = event.payload;
      if (!input.displayName || !input.city || !input.regionCode || !input.interests) throw new Error('Invalid profile projection event');
      await client.query(
        `INSERT INTO community_profile_projection(user_id,display_name,city,region_code,interests)
         VALUES($1,$2,$3,$4,$5)
         ON CONFLICT(user_id) DO UPDATE SET display_name=EXCLUDED.display_name,city=EXCLUDED.city,region_code=EXCLUDED.region_code,interests=EXCLUDED.interests,updated_at=now()`,
        [input.userId, input.displayName, input.city, input.regionCode.toUpperCase(), input.interests],
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

async function poll() {
  const response = await sqs.send(new ReceiveMessageCommand({ QueueUrl: queueUrl, WaitTimeSeconds: 20, MaxNumberOfMessages: 10, VisibilityTimeout: 60 }));
  for (const message of response.Messages ?? []) {
    if (!message.Body || !message.ReceiptHandle) continue;
    try {
      const event = JSON.parse(message.Body) as Event;
      await processEvent(event);
      await sqs.send(new DeleteMessageCommand({ QueueUrl: queueUrl, ReceiptHandle: message.ReceiptHandle }));
    } catch (error) {
      // Let SQS redeliver; no payload is logged because it contains profile data.
      console.error('Identity profile projection delivery failed', error instanceof Error ? error.name : 'unknown');
    }
  }
}

async function run() {
  while (true) await poll();
}
void run();
