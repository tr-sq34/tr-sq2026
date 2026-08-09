import { ServiceBusClient, ServiceBusSender } from '@azure/service-bus';

/**
 * Community publishes block edges to the messaging projection queue.
 *
 * Only the block edge is exported. Posts, stories and the relationship graph
 * stay inside Community: the messaging database is deliberately limited to what
 * the gateway needs to authorize a conversation.
 */

const connectionString = process.env.AZURE_SERVICE_BUS_CONNECTION_STRING;
const messagingProjectionQueue = process.env.AZURE_MESSAGING_PROJECTION_QUEUE_NAME;

let client: ServiceBusClient | undefined;
let sender: ServiceBusSender | undefined;

export function isMessagingProjectionConfigured(): boolean {
  return Boolean(connectionString && messagingProjectionQueue);
}

export async function sendMessagingProjectionEvent(event: {
  eventId: string;
  eventType: string;
  /** Producer transaction time; the consumer discards writes older than the row it holds. */
  occurredAt: string;
  payload: unknown;
}): Promise<void> {
  if (!connectionString || !messagingProjectionQueue) {
    throw new Error('Azure Service Bus is not configured; set AZURE_SERVICE_BUS_CONNECTION_STRING and AZURE_MESSAGING_PROJECTION_QUEUE_NAME');
  }
  client ??= new ServiceBusClient(connectionString);
  sender ??= client.createSender(messagingProjectionQueue);
  await sender.sendMessages({ body: event, messageId: event.eventId });
}

export async function closeServiceBus(): Promise<void> {
  await sender?.close().catch(() => undefined);
  sender = undefined;
  await client?.close().catch(() => undefined);
  client = undefined;
}
