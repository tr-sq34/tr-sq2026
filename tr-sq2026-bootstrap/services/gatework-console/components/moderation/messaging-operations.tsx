'use client';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { apiData, errorText, formatDateTime } from '@/lib/api-client';
import { MODERATION_ACTION_LABELS, type AuditRow, type ModeratedGroup, type RestrictionRow } from '@/lib/moderation-labels';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { DataTable, type ColumnDef } from '@/components/ui/data-table';
import { ReasonDialog } from '@/components/ui/reason-dialog';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';

/**
 * Groups, standing restrictions and the action trail.
 *
 * The two acts here used `window.prompt` to collect a reason, which cannot show
 * which row is about to be closed, cannot enforce the five-character minimum the
 * service requires, and is suppressible per browser. Both now go through
 * ReasonDialog, so the sentence that lands in the audit record is written in
 * front of the row it describes.
 */
type Pending =
  | { kind: 'takedown'; id: string; name: string }
  | { kind: 'lift'; id: string; name: string };

export function MessagingOperations({ groups, restrictions, audit, canTakeDown, canAct }: {
  groups: ModeratedGroup[]; restrictions: RestrictionRow[]; audit: AuditRow[]; canTakeDown: boolean; canAct: boolean;
}) {
  const router = useRouter();
  const [pending, setPending] = useState<Pending | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  async function confirm(reason: string) {
    if (!pending) return;
    if (pending.kind === 'takedown') {
      await apiData(`/api/moderation/groups/${pending.id}/takedown`, { method: 'POST', body: JSON.stringify({ reason }) });
      setNotice(`"${pending.name}" grubu kapatıldı.`);
    } else {
      await apiData(`/api/moderation/restrictions/${pending.id}`, { method: 'DELETE', body: JSON.stringify({ reason }) });
      setNotice(`${pending.name} üzerindeki kısıtlama kaldırıldı.`);
    }
    router.refresh();
  }

  const groupColumns: ColumnDef<ModeratedGroup, unknown>[] = [
    {
      id: 'name',
      header: 'Grup',
      accessorFn: (row) => `${row.name} ${row.city}`,
      cell: ({ row }) => {
        const group = row.original;
        return (
          <div className="min-w-48">
            <p className="font-medium text-ink">{group.name}</p>
            <p className="text-xs text-ink-faint">
              {group.city} · {group.privacy === 'public' ? 'herkese açık' : 'özel'}
              {group.removedAt && ` · kapatıldı: ${group.removedReason ?? ''}`}
            </p>
          </div>
        );
      },
    },
    { id: 'owner', header: 'Kurucu', accessorFn: (row) => row.ownerName ?? row.ownerId, cell: ({ row }) => row.original.ownerName ?? row.original.ownerId.slice(0, 8) },
    { id: 'members', header: 'Üye', accessorFn: (row) => row.memberCount, cell: ({ row }) => row.original.memberCount },
    {
      id: 'openReports',
      header: 'Açık şikâyet',
      accessorFn: (row) => row.openReports,
      cell: ({ row }) => (row.original.openReports > 0
        ? <Badge tone="danger">{row.original.openReports}</Badge>
        : <span className="text-ink-faint">0</span>),
    },
    { id: 'lastMessageAt', header: 'Son mesaj', accessorFn: (row) => row.lastMessageAt, cell: ({ row }) => <span className="whitespace-nowrap">{formatDateTime(row.original.lastMessageAt)}</span> },
    {
      id: 'actions',
      header: '',
      enableSorting: false,
      cell: ({ row }) => (canTakeDown && !row.original.removedAt ? (
        <Button size="sm" variant="danger" onClick={() => setPending({ kind: 'takedown', id: row.original.id, name: row.original.name })}>
          Grubu kapat
        </Button>
      ) : null),
    },
  ];

  const restrictionColumns: ColumnDef<RestrictionRow, unknown>[] = [
    { id: 'user', header: 'Kullanıcı', accessorFn: (row) => row.displayName ?? row.userId, cell: ({ row }) => <span className="font-medium text-ink">{row.original.displayName ?? row.original.userId.slice(0, 8)}</span> },
    {
      id: 'restriction',
      header: 'Tür',
      accessorFn: (row) => row.restriction,
      cell: ({ row }) => (
        <Badge tone={row.original.restriction === 'suspended' ? 'danger' : 'warning'}>
          {row.original.restriction === 'suspended' ? 'Askıya alındı' : 'Susturuldu'}
        </Badge>
      ),
    },
    {
      id: 'expiresAt',
      header: 'Bitiş',
      accessorFn: (row) => row.expiresAt ?? '',
      cell: ({ row }) => <span className="whitespace-nowrap">{row.original.expiresAt ? formatDateTime(row.original.expiresAt) : 'süresiz'}</span>,
    },
    { id: 'reason', header: 'Gerekçe', accessorFn: (row) => row.reason, cell: ({ row }) => <span className="block max-w-md">{row.original.reason}</span> },
    {
      id: 'actions',
      header: '',
      enableSorting: false,
      cell: ({ row }) => (canAct ? (
        <Button size="sm" variant="outline" onClick={() => setPending({ kind: 'lift', id: row.original.userId, name: row.original.displayName ?? row.original.userId.slice(0, 8) })}>
          Kaldır
        </Button>
      ) : null),
    },
  ];

  const auditColumns: ColumnDef<AuditRow, unknown>[] = [
    { id: 'createdAt', header: 'Zaman', accessorFn: (row) => row.createdAt, cell: ({ row }) => <span className="whitespace-nowrap">{formatDateTime(row.original.createdAt)}</span> },
    { id: 'action', header: 'İşlem', accessorFn: (row) => MODERATION_ACTION_LABELS[row.action] ?? row.action, cell: ({ row }) => <span className="font-medium text-ink">{MODERATION_ACTION_LABELS[row.original.action] ?? row.original.action}</span> },
    { id: 'target', header: 'Hedef', accessorFn: (row) => `${row.targetType} ${row.targetId}`, cell: ({ row }) => `${row.original.targetType} · ${row.original.targetId.slice(0, 8)}` },
    {
      id: 'actor',
      header: 'Operatör',
      accessorFn: (row) => `${row.actorId} ${row.actorRoles.join(' ')}`,
      cell: ({ row }) => (
        <span className="whitespace-nowrap">
          {row.original.actorId.slice(0, 8)} <span className="text-ink-faint">({row.original.actorRoles.join(', ')})</span>
        </span>
      ),
    },
    { id: 'reason', header: 'Gerekçe', accessorFn: (row) => row.reason, cell: ({ row }) => <span className="block max-w-md">{row.original.reason}</span> },
  ];

  return (
    <section>
      {notice && <p className="mb-4 rounded-card border border-success/30 bg-success-soft p-4 text-sm text-success">{notice}</p>}

      <Tabs defaultValue="groups">
        <TabsList className="mb-4">
          <TabsTrigger value="groups" count={groups.length}>Gruplar</TabsTrigger>
          <TabsTrigger value="restrictions" count={restrictions.length}>Kısıtlamalar</TabsTrigger>
          <TabsTrigger value="audit" count={audit.length}>Denetim kaydı</TabsTrigger>
        </TabsList>

        <TabsContent value="groups">
          <DataTable
            columns={groupColumns}
            rows={groups}
            rowKey={(row) => row.id}
            searchPlaceholder="Grup adı veya şehir ara"
            emptyLabel="Henüz grup yok."
            isRowUrgent={(row) => row.openReports > 0 && !row.removedAt}
          />
        </TabsContent>

        <TabsContent value="restrictions">
          <DataTable
            columns={restrictionColumns}
            rows={restrictions}
            rowKey={(row) => row.userId}
            searchPlaceholder="Kullanıcı veya gerekçe ara"
            emptyLabel="Etkin kısıtlama yok."
            isRowUrgent={(row) => row.restriction === 'suspended' && row.expiresAt === null}
          />
        </TabsContent>

        <TabsContent value="audit">
          <DataTable
            columns={auditColumns}
            rows={audit}
            rowKey={(row) => row.id}
            searchPlaceholder="İşlem, hedef veya gerekçe ara"
            emptyLabel="Henüz moderasyon işlemi yok."
          />
        </TabsContent>
      </Tabs>

      <ReasonDialog
        open={pending !== null}
        onOpenChange={(open) => { if (!open) setPending(null); }}
        title={pending?.kind === 'takedown' ? `"${pending.name}" grubu kapatılacak` : 'Kısıtlama kaldırılacak'}
        description={
          pending?.kind === 'takedown'
            ? 'Grup üyeler için görünmez olur ve mesajlaşma durur. Gerekçe, kapatma kaydının yanında kalır.'
            : `${pending?.name ?? 'Kullanıcı'} yeniden yazabilir hâle gelir. Kaldırma da bir moderasyon kararıdır ve denetim kaydına yazılır.`
        }
        confirmLabel={pending?.kind === 'takedown' ? 'Grubu kapat' : 'Kısıtlamayı kaldır'}
        variant={pending?.kind === 'takedown' ? 'danger' : 'primary'}
        onConfirm={confirm}
      />
    </section>
  );
}
