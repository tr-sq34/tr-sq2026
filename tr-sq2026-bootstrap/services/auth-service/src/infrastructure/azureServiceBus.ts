import { ServiceBusClient, ServiceBusSender } from "@azure/service-bus";

/**
 * Identity publishes to two independent projection queues. They are separate
 * queues rather than one topic because the consumers have different owners,
 * different retention needs and different failure blast radius: a poisoned
 * community event must not stall messaging delivery.
 */
export type OutboxQueue = "community-profile" | "messaging-projection";

const connectionString = process.env.AZURE_SERVICE_BUS_CONNECTION_STRING;

const queueNames: Record<OutboxQueue, string | undefined> = {
  "community-profile": process.env.AZURE_COMMUNITY_PROFILE_QUEUE_NAME,
  "messaging-projection": process.env.AZURE_MESSAGING_PROJECTION_QUEUE_NAME,
};

const senders = new Map<OutboxQueue, ServiceBusSender>();
let client: ServiceBusClient | undefined;

export function isQueueConfigured(queue: OutboxQueue): boolean {
  return Boolean(connectionString && queueNames[queue]);
}

function getSender(queue: OutboxQueue): ServiceBusSender | undefined {
  const queueName = queueNames[queue];
  if (!connectionString || !queueName) return undefined;
  let sender = senders.get(queue);
  if (!sender) {
    client ??= new ServiceBusClient(connectionString);
    sender = client.createSender(queueName);
    senders.set(queue, sender);
  }
  return sender;
}

export async function sendOutboxEvent(
  queue: OutboxQueue,
  event: {
    eventId: string;
    eventType: string;
    /**
     * Producer transaction time. The messaging projection consumer uses it to
     * discard writes that are older than the row's current state, so it must be
     * the time the domain row changed, not the time the outbox was drained.
     */
    occurredAt?: string;
    payload: unknown;
  }
): Promise<void> {
  const sender = getSender(queue);
  if (!sender) {
    throw new Error(
      `Azure Service Bus queue "${queue}" is not configured; set AZURE_SERVICE_BUS_CONNECTION_STRING and the matching queue name variable`
    );
  }
  // messageId lets the broker's duplicate detection collapse a redelivery caused
  // by a crash between send and the published_at update.
  await sender.sendMessages({ body: event, messageId: event.eventId });
}

/** @deprecated Use sendOutboxEvent("community-profile", event). */
export async function sendCommunityProfileEvent(event: {
  eventId: string;
  eventType: string;
  payload: unknown;
}): Promise<void> {
  await sendOutboxEvent("community-profile", event);
}

export async function closeServiceBus(): Promise<void> {
  for (const sender of senders.values()) await sender.close().catch(() => undefined);
  senders.clear();
  await client?.close().catch(() => undefined);
  client = undefined;
}
