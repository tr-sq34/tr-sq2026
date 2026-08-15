import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { delegation } from './gatework';
import { getSession } from './session';
import type { GateworkRole } from './types';

/**
 * Console side of "Global duyuru geç".
 *
 * The button existed in the command centre from the day it was built and did
 * nothing: no service could write a sentence into every member's inbox. It
 * lands in the app's bell now.
 *
 * The narrowest role list of any write in this console, and on purpose. This is
 * the only action that speaks to every member at once, in the platform's own
 * voice, and nothing takes it back once it is sent - so it sits with the two
 * roles that answer for the platform rather than with the editors.
 */
const communityBase = () => (process.env.COMMUNITY_API_BASE_URL ?? 'http://localhost:8081').replace(/\/$/, '');

async function communityFetch(path: string, init: RequestInit = {}) {
  const session = await getSession();
  if (!session) throw new Error('UNAUTHENTICATED');
  const token = await delegation(session.accessToken);
  const response = await fetch(`${communityBase()}${path}`, {
    ...init,
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}`, ...(init.headers ?? {}) },
    cache: 'no-store',
  });
  if (!response.ok) {
    const detail = await response.json().catch(() => null) as { error?: { message?: string } } | null;
    throw new Error(detail?.error?.message ?? `COMMUNITY_${response.status}`);
  }
  if (response.status === 204) return null;
  return response.json();
}

export const canSendAnnouncement = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'operations_admin'].includes(role));
export const canSeeAnnouncements = (roles: GateworkRole[]) =>
  roles.some((role) => ['owner', 'operations_admin', 'content_editor', 'moderator', 'analyst', 'auditor'].includes(role));

// Mirrors the service's bounds so the operator is told before the send, not
// after. 2000 characters is a notice, not an article: anything longer belongs
// in Haber Merkezi, where members can read it at length and come back to it.
export const announcementSchema = z.object({
  title: z.string().trim().min(3, 'Başlık en az 3 karakter olmalı.').max(120, 'Başlık en fazla 120 karakter olabilir.'),
  body: z.string().trim().min(3, 'Duyuru metni en az 3 karakter olmalı.').max(2000, 'Duyuru en fazla 2000 karakter olabilir.'),
});

export type AnnouncementRow = {
  id: string;
  title: string;
  body: string;
  recipientCount: number;
  readCount: number;
  authorName: string;
  createdAt: string;
};

export async function listAnnouncements(): Promise<AnnouncementRow[]> {
  return (await communityFetch('/v1/internal/gatework/announcements')).data as AnnouncementRow[];
}

export async function sendAnnouncement(raw: unknown) {
  const input = announcementSchema.parse(raw);
  // The key is minted here rather than in the browser: a retry after a timeout
  // must carry the same one, and a component that remounts loses whatever it
  // was holding. Same reason events does it.
  const body = { ...input, idempotencyKey: randomUUID() };
  return (await communityFetch('/v1/internal/gatework/announcements', { method: 'POST', body: JSON.stringify(body) }))
    .data as { id: string; recipientCount: number; duplicate: boolean };
}
