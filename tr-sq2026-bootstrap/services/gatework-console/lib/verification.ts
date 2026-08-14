import { delegation } from './gatework';
import { getSession } from './session';
import type { VerificationOverview, VerificationSession } from './verification-labels';
import type { GateworkRole } from './types';

/**
 * Console side of Doğrulama.
 *
 * The vault answers a delegation token like every other operator-facing service
 * and returns status only: it holds no document, no image and no detail from
 * Stripe, so there is nothing here that could show one. What the screen adds is
 * the member's name, fetched from Identity by id - the vault deliberately does
 * not keep a copy of it, and a list of UUIDs is not a screen anybody can work
 * from.
 *
 * Read-only. Identity verification is decided by Stripe and recorded by the
 * webhook; a button here that marked somebody verified would be a way to hand
 * out the badge without the check, which is the entire point of the check.
 */
const verificationBase = () => (process.env.VERIFICATION_API_BASE_URL ?? 'http://localhost:8083').replace(/\/$/, '');
const identityBase = () => (process.env.IDENTITY_API_BASE_URL ?? 'http://localhost:8080').replace(/\/$/, '');

export { VERIFICATION_STATUS_LABELS, VERIFICATION_STATUS_HINTS } from './verification-labels';
export type { VerificationOverview, VerificationSession } from './verification-labels';

// Mirrors the vault's own gate. Moderator is absent on both sides: moderation is
// about what a member posted, and who holds an approved identity document is a
// different question with a different reason to be asked.
export const canSeeVerification = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin', 'operations_admin', 'auditor'].includes(role));

async function vaultFetch(path: string, token: string) {
  const response = await fetch(`${verificationBase()}${path}`, { headers: { authorization: `Bearer ${token}` }, cache: 'no-store' });
  if (!response.ok) {
    const detail = await response.json().catch(() => null) as { error?: { message?: string } } | null;
    throw new Error(detail?.error?.message ?? `VERIFICATION_${response.status}`);
  }
  return response.json();
}

// One call for the whole page rather than one per row. Failing this lookup must
// not empty the screen: a name is what makes the list readable, a status is what
// makes it useful, and the second one still works without the first.
async function memberNames(userIds: string[], accessToken: string) {
  const unique = [...new Set(userIds)].slice(0, 100);
  if (!unique.length) return new Map<string, { name: string; email: string }>();
  try {
    const response = await fetch(`${identityBase()}/v1/auth/gatework/members?limit=100&ids=${unique.join(',')}`, {
      headers: { authorization: `Bearer ${accessToken}` },
      cache: 'no-store',
    });
    if (!response.ok) return new Map<string, { name: string; email: string }>();
    const rows = (await response.json()).data as { id: string; displayName: string; email: string }[];
    return new Map(rows.map((row) => [row.id, { name: row.displayName, email: row.email }]));
  } catch {
    return new Map<string, { name: string; email: string }>();
  }
}

export async function verificationPage(params: { status?: string } = {}): Promise<{ overview: VerificationOverview | null; sessions: VerificationSession[]; failure: string | null }> {
  const search = new URLSearchParams({ limit: '100' });
  if (params.status) search.set('status', params.status);

  // Minting the delegation token used to sit outside this try, and that is how
  // an Identity hiccup became a 500 on the Komuta Merkezi rather than one card
  // saying the vault did not answer. Everything that talks to another service
  // belongs inside.
  try {
    const session = await getSession();
    if (!session) throw new Error('UNAUTHENTICATED');
    const token = await delegation(session.accessToken);
    const [overview, list] = await Promise.all([
      vaultFetch('/v1/internal/gatework/verification/overview', token),
      vaultFetch(`/v1/internal/gatework/verification/sessions?${search}`, token),
    ]);
    const rows = list.data as Omit<VerificationSession, 'memberName' | 'memberEmail'>[];
    const names = await memberNames(rows.map((row) => row.userId), session.accessToken);
    return {
      overview: overview.data as VerificationOverview,
      sessions: rows.map((row) => ({ ...row, memberName: names.get(row.userId)?.name ?? null, memberEmail: names.get(row.userId)?.email ?? null })),
      failure: null,
    };
  } catch (error) {
    return { overview: null, sessions: [], failure: error instanceof Error ? error.message : 'Doğrulama servisine ulaşılamadı.' };
  }
}
