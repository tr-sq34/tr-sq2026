import { ServiceBusClient, type ServiceBusReceivedMessage } from '@azure/service-bus';
import type pg from 'pg';
import { createDatabasePool } from './database.js';
import { messagingProjectionEvent, type MessagingProjectionEvent } from './events.js';

/**
 * Fills `messaging_user_projection` and `messaging_block_projection` from the
 * Identity and Community outboxes.
 *
 * Without this worker the gateway rejects every conversation with
 * USER_NOT_AVAILABLE, because ensureConversation() requires both participants to
 * already exist in the user projection.
 *
 * The projection is deliberately a narrow copy: display name and an active flag,
 * plus the block edges. No credential, email, phone number or identity document
 * is replicated into the messaging database.
 */

const required = (key: string): string => {
  const value = process.env[key];
  if (!value) throw new Error(`Missing required environment variable: ${key}`);
  return value;
};

const connectionString = required('AZURE_SERVICE_BUS_CONNECTION_STRING');
const queueName = required('AZURE_MESSAGING_PROJECTION_QUEUE_NAME');
const maxConcurrentCalls = Number(process.env.PROJECTION_MAX_CONCURRENCY ?? 8);

// Matches the queue's default_message_ttl (P14D). Once a message can no longer
// be redelivered, its dedup row has no value and would grow the table forever.
const PROCESSED_EVENT_RETENTION = '14 days';

const db = createDatabasePool(10);
const sbClient = new ServiceBusClient(connectionString);
const receiver = sbClient.createReceiver(queueName, { receiveMode: 'peekLock' });

const log = (level: 'info' | 'warn' | 'error', message: string, fields: Record<string, unknown> = {}) => {
  // Payloads are never logged: display names are personal data and block edges
  // reveal the social graph.
  console[level === 'info' ? 'log' : level](JSON.stringify({ level, service: 'messaging-projection', message, ...fields }));
};

/**
 * Applies one event inside a single transaction together with its dedup row, so
 * a crash between the two can only replay — never skip — the projection write.
 *
 * Returns false when the event was already applied.
 */
async function applyEvent(client: pg.PoolClient, event: MessagingProjectionEvent): Promise<boolean> {
  const claimed = await client.query(
    'INSERT INTO processed_messaging_events(event_id, event_type) VALUES($1,$2) ON CONFLICT (event_id) DO NOTHING RETURNING event_id',
    [event.eventId, event.eventType],
  );
  if (!claimed.rowCount) return false;

  const occurredAt = event.occurredAt;

  if (event.eventType === 'messaging.user_upserted') {
    // The ordering guard lives in the WHERE clause of DO UPDATE rather than in a
    // read-then-write, so two concurrent consumers cannot interleave a stale
    // write between another consumer's read and update.
    await client.query(
      `INSERT INTO messaging_user_projection(user_id, display_name, active, source_event_at, updated_at)
       VALUES($1,$2,$3,$4,now())
       ON CONFLICT (user_id) DO UPDATE
         SET display_name = EXCLUDED.display_name,
             active = EXCLUDED.active,
             source_event_at = EXCLUDED.source_event_at,
             updated_at = now()
         WHERE EXCLUDED.source_event_at >= messaging_user_projection.source_event_at`,
      [event.payload.userId, event.payload.displayName, event.payload.active, occurredAt],
    );
    return true;
  }

  const active = event.eventType === 'messaging.user_blocked';
  await client.query(
    `INSERT INTO messaging_block_projection(blocker_id, blocked_id, active, source_event_at, updated_at)
     VALUES($1,$2,$3,$4,now())
     ON CONFLICT (blocker_id, blocked_id) DO UPDATE
       SET active = EXCLUDED.active,
           source_event_at = EXCLUDED.source_event_at,
           updated_at = now()
       WHERE EXCLUDED.source_event_at >= messaging_block_projection.source_event_at`,
    [event.payload.blockerId, event.payload.blockedId, active, occurredAt],
  );
  return true;
}

async function processMessage(message: ServiceBusReceivedMessage): Promise<void> {
  // Service Bus hands back an already-decoded object for JSON messages, but a
  // producer using a raw Buffer/string body is still valid AMQP.
  const raw = typeof message.body === 'string' ? safeJsonParse(message.body) : message.body;
  const parsed = messagingProjectionEvent.safeParse(raw);

  if (!parsed.success) {
    // A malformed event will never become valid on redelivery. Abandoning it
    // would spin until maxDeliveryCount; dead-lettering surfaces it immediately.
    log('error', 'Rejecting malformed projection event', {
      messageId: message.messageId,
      issues: parsed.error.issues.map((issue) => issue.path.join('.')).slice(0, 10),
    });
    await receiver.deadLetterMessage(message, {
      deadLetterReason: 'SchemaValidationFailed',
      deadLetterErrorDescription: 'Event does not match the messaging projection contract',
    });
    return;
  }

  const event = parsed.data;
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const applied = await applyEvent(client, event);
    await client.query('COMMIT');
    if (!applied) log('info', 'Skipped duplicate projection event', { eventId: event.eventId, eventType: event.eventType });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }

  await receiver.completeMessage(message);
}

function safeJsonParse(value: string): unknown {
  try {
    return JSON.parse(value);
  } catch {
    return undefined;
  }
}

async function pruneProcessedEvents(): Promise<void> {
  try {
    const result = await db.query(
      `DELETE FROM processed_messaging_events WHERE processed_at < now() - INTERVAL '${PROCESSED_EVENT_RETENTION}'`,
    );
    if (result.rowCount) log('info', 'Pruned expired dedup rows', { rows: result.rowCount });
  } catch (error) {
    log('warn', 'Dedup prune deferred', { error: error instanceof Error ? error.name : 'unknown' });
  }
}

const subscription = receiver.subscribe(
  {
    processMessage: async (message) => {
      try {
        await processMessage(message);
      } catch (error) {
        // Transient failure (database unavailable, lock lost). Abandon so the
        // broker redelivers; maxDeliveryCount eventually dead-letters it.
        log('error', 'Projection event delivery failed', {
          messageId: message.messageId,
          deliveryCount: message.deliveryCount,
          error: error instanceof Error ? error.name : 'unknown',
        });
        await receiver.abandonMessage(message).catch(() => undefined);
      }
    },
    processError: async (args) => {
      log('error', 'Service Bus receiver error', { source: args.errorSource, error: args.error.message });
    },
  },
  { maxConcurrentCalls, autoCompleteMessages: false },
);

log('info', 'Messaging projection worker started', { queueName, maxConcurrentCalls });

const pruneTimer = setInterval(() => void pruneProcessedEvents(), 6 * 60 * 60 * 1000);
pruneTimer.unref();
void pruneProcessedEvents();

const shutdown = async (signal: string) => {
  log('info', 'Messaging projection worker stopping', { signal });
  clearInterval(pruneTimer);
  await subscription.close().catch(() => undefined);
  await receiver.close().catch(() => undefined);
  await sbClient.close().catch(() => undefined);
  await db.end().catch(() => undefined);
  process.exit(0);
};

process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
