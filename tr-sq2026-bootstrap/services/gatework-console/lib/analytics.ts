import { delegation } from './gatework';
import { getSession } from './session';
import type { AccountAnalytics, CommunityAnalytics, LocationAnalytics } from './analytics-labels';
import type { GateworkRole } from './types';

/**
 * Console side of Analitik ve Konum.
 *
 * The screen is assembled from two services because the numbers belong to two
 * services: Identity owns accounts and email verification, Community owns
 * profiles, posts, forum and listings. Neither is asked for the other's data.
 *
 * What is deliberately not here: any per-member location. Community keeps an
 * approximate cell per viewer and a point per post, and this screen reads
 * neither. It reads the city and state a member chose to publish, aggregated,
 * and only for buckets big enough that a count does not name a person - the
 * suppression itself happens in Community, so the small buckets never travel.
 *
 * Read-only end to end. There is no action on this screen, so there is nothing
 * to audit and no write path to get wrong.
 */
const communityBase = () => (process.env.COMMUNITY_API_BASE_URL ?? 'http://localhost:8081').replace(/\/$/, '');
const identityBase = () => (process.env.IDENTITY_API_BASE_URL ?? 'http://localhost:8080').replace(/\/$/, '');

export type { AccountAnalytics, CommunityAnalytics, LocationAnalytics } from './analytics-labels';

// Mirrors the gate on both services. content_editor and moderator are absent:
// neither role needs population figures to do its job, and the list is the one
// place where "everyone in the console" would have been the easy answer.
export const canSeeAnalytics = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin', 'operations_admin', 'analyst', 'auditor'].includes(role));

async function readJson(url: string, token: string) {
  const response = await fetch(url, { headers: { authorization: `Bearer ${token}` }, cache: 'no-store' });
  if (!response.ok) {
    const detail = await response.json().catch(() => null) as { error?: { message?: string } } | null;
    throw new Error(detail?.error?.message ?? `ANALYTICS_${response.status}`);
  }
  return response.json();
}

export type AnalyticsPage = {
  accounts: AccountAnalytics | null;
  community: CommunityAnalytics | null;
  locations: LocationAnalytics | null;
  failures: string[];
};

// Three independent reads, and one failing must not blank the other two: an
// Identity outage should cost the account cards, not the map. Each failure is
// named on the screen so a missing panel reads as "this service did not answer"
// rather than as a zero.
export async function analyticsPage(): Promise<AnalyticsPage> {
  const session = await getSession();
  if (!session) throw new Error('UNAUTHENTICATED');
  const token = await delegation(session.accessToken);

  const [accounts, community, locations] = await Promise.all([
    readJson(`${identityBase()}/v1/auth/gatework/analytics`, session.accessToken).then((body) => body.data as AccountAnalytics).catch((error: Error) => error),
    readJson(`${communityBase()}/v1/internal/gatework/analytics/overview`, token).then((body) => body.data as CommunityAnalytics).catch((error: Error) => error),
    readJson(`${communityBase()}/v1/internal/gatework/analytics/locations`, token).then((body) => body.data as LocationAnalytics).catch((error: Error) => error),
  ]);

  const failures: string[] = [];
  const unwrap = <T>(value: T | Error, label: string): T | null => {
    if (value instanceof Error) { failures.push(`${label}: ${value.message}`); return null; }
    return value;
  };
  return {
    accounts: unwrap(accounts, 'Kimlik'),
    community: unwrap(community, 'Topluluk'),
    locations: unwrap(locations, 'Konum'),
    failures,
  };
}
