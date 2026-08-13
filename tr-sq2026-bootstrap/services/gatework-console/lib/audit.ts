import { delegation } from './gatework';
import { getSession } from './session';
import type { AuditRow } from './audit-labels';
import type { GateworkRole } from './types';

/**
 * Console side of Sistem ve Denetim.
 *
 * Every privileged action in this platform already wrote an audit row; none of
 * them could be read back outside a database console. Three services keep three
 * logs and none of them knows about the others, so the merge happens here: each
 * is asked for its own page, the rows are normalised into one shape and sorted
 * by time. Read-only by construction - there is no write path in this module,
 * and an audit trail the console can edit is not an audit trail.
 *
 * One service being down must not empty the screen. A failed source is reported
 * by name and the rest of the page still renders, because an operator checking
 * who removed a post should not be blocked by the messaging gateway restarting.
 */
const identityBase = () => (process.env.IDENTITY_API_BASE_URL ?? 'http://localhost:8080').replace(/\/$/, '');
const communityBase = () => (process.env.COMMUNITY_API_BASE_URL ?? 'http://localhost:8081').replace(/\/$/, '');
const messagingBase = () => (process.env.MESSAGING_API_BASE_URL ?? 'http://localhost:8082').replace(/\/$/, '');

export { SERVICE_LABELS, OUTCOME_LABELS, ACTION_LABELS, actionLabel, actorLabel } from './audit-labels';
export type { AuditRow } from './audit-labels';

// Mirrors the gate each service applies to its own log. Not moderator: a
// moderator acts and is recorded, and letting the recorded party curate their
// own view of the record is the one thing this screen exists to prevent.
export const canSeeAudit = (roles: GateworkRole[]) => roles.some((role) => ['owner', 'security_admin', 'auditor'].includes(role));

export type AuditFilters = { action?: string; actorId?: string; outcome?: string; limit?: number };
export type AuditPage = { rows: AuditRow[]; failures: string[] };

function query(filters: AuditFilters) {
  const search = new URLSearchParams({ limit: String(filters.limit ?? 100) });
  if (filters.action && filters.action.trim().length >= 2) search.set('action', filters.action.trim());
  if (filters.actorId) search.set('actorId', filters.actorId);
  if (filters.outcome) search.set('outcome', filters.outcome);
  return search;
}

async function read(url: string, token: string) {
  const response = await fetch(url, { headers: { authorization: `Bearer ${token}` }, cache: 'no-store' });
  if (!response.ok) throw new Error(String(response.status));
  return (await response.json()).data as Record<string, unknown>[];
}

export async function auditPage(filters: AuditFilters = {}): Promise<AuditPage> {
  const session = await getSession();
  if (!session) throw new Error('UNAUTHENTICATED');
  const search = query(filters);
  // Identity answers the operator's own token; the other two answer a
  // delegation minted for this operator, exactly like every other screen here.
  const operatorToken = session.accessToken;
  const delegated = await delegation(operatorToken);

  const sources: { service: AuditRow['service']; label: string; load: () => Promise<AuditRow[]> }[] = [
    {
      service: 'identity',
      label: 'Kimlik',
      load: async () => (await read(`${identityBase()}/v1/auth/gatework/audit?${search}`, operatorToken)).map((row) => normalise(row, 'identity', 'identity')),
    },
    {
      service: 'community',
      label: 'Topluluk',
      load: async () => (await read(`${communityBase()}/v1/internal/gatework/audit?${search}`, delegated)).map((row) => normalise(row, 'community', String(row.source ?? 'operation'))),
    },
    {
      // The gateway's log predates this screen and has no outcome or actor name:
      // it only records decisions that were applied, so they normalise to
      // succeeded rather than to an empty cell that would read as unknown.
      service: 'messaging',
      label: 'Mesajlaşma',
      load: async () => {
        if (filters.outcome && filters.outcome !== 'succeeded') return [];
        return (await read(`${messagingBase()}/v1/internal/gatework/messaging/audit?limit=${filters.limit ?? 100}`, delegated))
          .map((row) => normalise(row, 'messaging', 'moderation'))
          .filter((row) => (!filters.action || row.action.startsWith(filters.action.trim())) && (!filters.actorId || row.actorId === filters.actorId));
      },
    },
  ];

  const settled = await Promise.allSettled(sources.map((source) => source.load()));
  const rows: AuditRow[] = [];
  const failures: string[] = [];
  settled.forEach((result, index) => {
    if (result.status === 'fulfilled') rows.push(...result.value);
    else failures.push(sources[index]!.label);
  });
  rows.sort((left, right) => right.createdAt.localeCompare(left.createdAt));
  return { rows, failures };
}

function normalise(row: Record<string, unknown>, service: AuditRow['service'], stream: string): AuditRow {
  return {
    id: `${service}:${String(row.id)}`,
    service,
    stream,
    actorId: String(row.actorId ?? ''),
    actorName: (row.actorName as string | null) ?? null,
    actorEmail: (row.actorEmail as string | null) ?? null,
    actorRoles: (row.actorRoles as string[] | undefined) ?? [],
    action: String(row.action ?? ''),
    targetType: String(row.targetType ?? ''),
    targetId: String(row.targetId ?? ''),
    reason: (row.reason as string | null) ?? null,
    outcome: String(row.outcome ?? 'succeeded'),
    createdAt: String(row.createdAt ?? ''),
  };
}
