'use client';
import { useCallback, useMemo, useState } from 'react';
import { ChevronRight, Search } from 'lucide-react';
import { apiData, errorText, formatDate } from '@/lib/api-client';
import { ROLE_LABELS, type IdentityMember, type MemberPermissions } from '@/lib/member-labels';
import { gateworkRoles } from '@/lib/types';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { DataTable, type ColumnDef } from '@/components/ui/data-table';
import { Select } from '@/components/ui/field';
import { Sheet, SheetContent } from '@/components/ui/sheet';
import { MemberDrawer } from './member-drawer';

/**
 * Üyeler: a table you scan and a panel you work in.
 *
 * The list this replaces was a 380px column of stacked cards next to a
 * permanently-mounted detail pane. Nothing lined up, so nothing could be
 * compared - "which of these accounts registered this week" meant reading every
 * card - and the detail pane was always there, taking half the screen even when
 * no member was selected.
 *
 * Search stays on the server. Identity holds far more accounts than a page, so
 * a client-side filter over the loaded rows would quietly answer "bulunamadı"
 * for a member who exists. That is why the table's own filter box is not used
 * here: one search box that searches everything beats two that disagree.
 */
export function MemberDesk({
  initialMembers,
  permissions,
  selfId,
  loadFailure,
}: {
  initialMembers: IdentityMember[];
  permissions: MemberPermissions;
  selfId: string;
  loadFailure: string | null;
}) {
  const [members, setMembers] = useState(initialMembers);
  const [query, setQuery] = useState('');
  const [roleFilter, setRoleFilter] = useState('');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(loadFailure);
  const [searching, setSearching] = useState(false);

  const selected = members.find((row) => row.id === selectedId) ?? null;

  const search = useCallback(async (nextQuery: string, nextRole: string) => {
    setSearching(true); setError(null);
    try {
      const params = new URLSearchParams();
      // Identity's floor is two characters; sending one back would be a 400
      // where the operator expected the unfiltered list.
      if (nextQuery.trim().length >= 2) params.set('query', nextQuery.trim());
      if (nextRole) params.set('role', nextRole);
      setMembers(await apiData<IdentityMember[]>(`/api/members?${params}`));
    } catch (caught) {
      setError(errorText(caught, 'Arama başarısız.'));
    } finally {
      setSearching(false);
    }
  }, []);

  // Called after a role grant: the row in the table carries the roles, so it has
  // to be refreshed or the drawer and the list disagree about the same account.
  const refresh = useCallback(async () => {
    const params = new URLSearchParams();
    if (query.trim().length >= 2) params.set('query', query.trim());
    if (roleFilter) params.set('role', roleFilter);
    const rows = await apiData<IdentityMember[]>(`/api/members?${params}`).catch(() => null);
    if (rows) setMembers(rows);
  }, [query, roleFilter]);

  const columns = useMemo<ColumnDef<IdentityMember, unknown>[]>(
    () => [
      {
        id: 'member',
        header: 'Üye',
        accessorFn: (row) => `${row.displayName} ${row.email}`,
        cell: ({ row }) => (
          <div className="min-w-0">
            <p className="truncate font-medium text-ink">{row.original.displayName}</p>
            <p className="truncate text-xs text-ink-faint">{row.original.email}</p>
          </div>
        ),
      },
      {
        id: 'roles',
        header: 'Panel yetkisi',
        accessorFn: (row) => row.roles.length,
        cell: ({ row }) =>
          row.original.roles.length === 0 ? (
            <span className="text-xs text-ink-faint">Panel yetkisi yok</span>
          ) : (
            <div className="flex flex-wrap gap-1">
              {row.original.roles.map((role) => (
                <Badge key={role} tone={role === 'owner' ? 'brand' : 'neutral'}>{ROLE_LABELS[role]}</Badge>
              ))}
            </div>
          ),
      },
      {
        id: 'emailVerified',
        header: 'E-posta',
        accessorFn: (row) => (row.emailVerified ? 1 : 0),
        cell: ({ row }) =>
          row.original.emailVerified
            ? <Badge tone="success" dot>Doğrulandı</Badge>
            : <Badge tone="warning" dot>Bekliyor</Badge>,
      },
      {
        id: 'createdAt',
        header: 'Kayıt',
        accessorFn: (row) => row.createdAt,
        cell: ({ row }) => <span className="text-xs whitespace-nowrap">{formatDate(row.original.createdAt)}</span>,
      },
      {
        id: 'open',
        header: '',
        enableSorting: false,
        cell: () => <ChevronRight size={15} className="text-ink-faint" />,
      },
    ],
    [],
  );

  return (
    <>
      {error && (
        <div className="mb-4 rounded-card border border-warning/30 bg-warning-soft p-4 text-sm text-warning">
          {error} Arama kutusu çalışmaya devam eder.
        </div>
      )}

      <form
        className="mb-4 flex flex-wrap items-end gap-3"
        onSubmit={(event) => { event.preventDefault(); void search(query, roleFilter); }}
      >
        <div className="relative min-w-56 flex-1">
          <Search size={15} className="absolute top-1/2 left-3 -translate-y-1/2 text-ink-faint" />
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="E-posta veya ad ara (en az 2 harf)"
            aria-label="Üye ara"
            className="h-10 w-full rounded-lg border border-hairline bg-canvas pr-3 pl-9 text-sm text-ink outline-none transition placeholder:text-ink-faint focus:border-brand-400"
          />
        </div>
        <Select
          value={roleFilter}
          onChange={(event) => setRoleFilter(event.target.value)}
          aria-label="Role göre süz"
          className="h-10 w-auto min-w-44"
        >
          <option value="">Tüm üyeler</option>
          {gateworkRoles.map((role) => <option key={role} value={role}>{ROLE_LABELS[role]}</option>)}
        </Select>
        <Button type="submit" variant="primary" disabled={searching}>{searching ? 'Aranıyor…' : 'Ara'}</Button>
      </form>

      <DataTable
        columns={columns}
        rows={members}
        rowKey={(row) => row.id}
        onRowClick={(row) => setSelectedId(row.id)}
        emptyLabel="Bu filtrede üye yok."
      />

      <Sheet open={selected !== null} onOpenChange={(open) => { if (!open) setSelectedId(null); }}>
        {selected && (
          <SheetContent title={selected.displayName} description={selected.email}>
            {/* Keyed by member so the drawer refetches Community instead of
                showing the previous account's counts for a moment. */}
            <MemberDrawer
              key={selected.id}
              member={selected}
              permissions={permissions}
              selfId={selfId}
              onIdentityChanged={refresh}
            />
          </SheetContent>
        )}
      </Sheet>
    </>
  );
}
