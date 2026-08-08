import { ServiceBusClient, ServiceBusSender } from "@azure/service-bus";

const connectionString = process.env.AZURE_SERVICE_BUS_CONNECTION_STRING;
const queueName = process.env.AZURE_VERIFICATION_CAPABILITY_QUEUE_NAME;

let sender: ServiceBusSender | undefined;

function getSender(): ServiceBusSender | undefined {
  if (!connectionString || !queueName) return undefined;
  if (!sender) {
    const client = new ServiceBusClient(connectionString);
    sender = client.createSender(queueName);
  }
  return sender;
}

export async function sendVerificationCapabilityEvent(event: {
  eventId: string;
  eventType: string;
  payload: unknown;
}): Promise<void> {
  const s = getSender();
  if (!s) {
    throw new Error(
      "Azure Service Bus is not configured; set AZURE_SERVICE_BUS_CONNECTION_STRING and AZURE_VERIFICATION_CAPABILITY_QUEUE_NAME"
    );
  }
  await s.sendMessages({ body: event });
}
