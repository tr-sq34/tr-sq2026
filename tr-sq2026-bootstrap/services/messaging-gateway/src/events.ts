import { z } from 'zod';

/**
 * Canonical contract for the `messaging-projection` Service Bus queue.
 *
 * Producers live in other packages (Identity emits the user events, Community
 * emits the block events) and keep their own literal copies of these strings.
 * This file is the definition they must match; changing an `eventType` value or
 * a payload field here is a breaking change for both producers.
 *
 * Deactivation is deliberately modelled as `messaging.user_upserted` with
 * `active: false` rather than a separate event type. Two event types writing the
 * same projection row would each need their own ordering guard, and a
 * `user_deactivated` overtaking a later `user_upserted` would silently
 * resurrect the account.
 */

export const MESSAGING_PROJECTION_EVENT_TYPES = [
  'messaging.user_upserted',
  'messaging.user_blocked',
  'messaging.user_unblocked',
] as const;

const uuid = z.string().uuid();

/**
 * `occurredAt` is the producer's transaction time, not the publish time. It is
 * the only ordering signal the consumer has, so it must be stamped when the
 * source row changes — not when the outbox row is drained.
 */
const envelope = {
  eventId: uuid,
  occurredAt: z.string().datetime({ offset: true }),
};

export const userUpsertedEvent = z.object({
  ...envelope,
  eventType: z.literal('messaging.user_upserted'),
  payload: z.object({
    userId: uuid,
    displayName: z.string().trim().min(1).max(100),
    active: z.boolean(),
  }),
});

const blockPayload = z.object({
  blockerId: uuid,
  blockedId: uuid,
}).refine((value) => value.blockerId !== value.blockedId, {
  message: 'blockerId and blockedId must differ',
});

export const userBlockedEvent = z.object({
  ...envelope,
  eventType: z.literal('messaging.user_blocked'),
  payload: blockPayload,
});

export const userUnblockedEvent = z.object({
  ...envelope,
  eventType: z.literal('messaging.user_unblocked'),
  payload: blockPayload,
});

export const messagingProjectionEvent = z.discriminatedUnion('eventType', [
  userUpsertedEvent,
  userBlockedEvent,
  userUnblockedEvent,
]);

export type MessagingProjectionEvent = z.infer<typeof messagingProjectionEvent>;
