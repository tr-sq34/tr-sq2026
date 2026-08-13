/**
 * Browser-safe half of the Analitik ve Konum screen.
 *
 * Split from lib/analytics.ts for the same reason as the other label modules:
 * the screen is a client component and the server module reads the session
 * cookie.
 */

// Identity's half: accounts, not profiles. Community cannot answer these -
// community_profile_projection has no created_at, so growth read there would
// count profile edits as signups.
export type AccountAnalytics = {
  accounts: number;
  verifiedAccounts: number;
  newLast7Days: number;
  newLast30Days: number;
  operators: number;
  weeks: { weekStart: string; signups: number; verified: number }[];
};

export type CommunityAnalytics = {
  members: number;
  locatedMembers: number;
  posts: number;
  postsLast7Days: number;
  commentsLast7Days: number;
  forumTopics: number;
  forumRepliesLast7Days: number;
  activeListings: number;
  liveStories: number;
  weeks: { weekStart: string; posts: number; forumTopics: number; listings: number }[];
};

// `threshold` and the two `suppressed` totals are part of the data, not a
// footnote: a screen that quietly dropped the small buckets would read as "the
// community is only in these nine states".
export type LocationAnalytics = {
  threshold: number;
  regions: { regionCode: string; members: number; posts: number; listings: number }[];
  cities: { city: string; regionCode: string; members: number; listings: number }[];
  suppressedRegions: { buckets: number; members: number; posts: number; listings: number };
  suppressedCities: { buckets: number; members: number; listings: number };
  unplaced: { members: number; posts: number; listings: number };
};

const REGION_NAMES: Record<string, string> = {
  AL: 'Alabama', AK: 'Alaska', AZ: 'Arizona', AR: 'Arkansas', CA: 'Kaliforniya', CO: 'Colorado', CT: 'Connecticut',
  DE: 'Delaware', DC: 'Washington DC', FL: 'Florida', GA: 'Georgia', HI: 'Hawaii', ID: 'Idaho', IL: 'Illinois',
  IN: 'Indiana', IA: 'Iowa', KS: 'Kansas', KY: 'Kentucky', LA: 'Louisiana', ME: 'Maine', MD: 'Maryland',
  MA: 'Massachusetts', MI: 'Michigan', MN: 'Minnesota', MS: 'Mississippi', MO: 'Missouri', MT: 'Montana',
  NE: 'Nebraska', NV: 'Nevada', NH: 'New Hampshire', NJ: 'New Jersey', NM: 'New Mexico', NY: 'New York',
  NC: 'Kuzey Carolina', ND: 'Kuzey Dakota', OH: 'Ohio', OK: 'Oklahoma', OR: 'Oregon', PA: 'Pennsylvania',
  PR: 'Porto Riko', RI: 'Rhode Island', SC: 'Güney Carolina', SD: 'Güney Dakota', TN: 'Tennessee', TX: 'Teksas',
  UT: 'Utah', VT: 'Vermont', VA: 'Virginia', WA: 'Washington', WV: 'Batı Virginia', WI: 'Wisconsin', WY: 'Wyoming',
};

// An unknown code is shown as itself. The column is a free CHECK-ed two-letter
// field, so a code this map has not heard of is data, not an error to hide.
export const regionLabel = (code: string) => REGION_NAMES[code] ?? code;

export const count = (value: number) => value.toLocaleString('tr-TR');
export const percent = (part: number, whole: number) => (whole > 0 ? `%${Math.round((part / whole) * 100)}` : '—');
export const weekLabel = (iso: string) => new Date(iso).toLocaleDateString('tr-TR', { day: '2-digit', month: 'short' });
