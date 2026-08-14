'use client';
import { useCallback, useState } from 'react';
import { CircleSlash, Eraser, FileClock, RefreshCw, ShieldCheck, TriangleAlert } from 'lucide-react';
import { api, errorText, formatDateTime } from '@/lib/api-client';
import {
  VERIFICATION_STATUS_HINTS,
  VERIFICATION_STATUS_LABELS,
  type VerificationOverview,
  type VerificationSession,
} from '@/lib/verification-labels';
import { Badge, type BadgeTone } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { DataTable, type ColumnDef } from '@/components/ui/data-table';
import { Dialog, DialogBody, DialogClose, DialogContent, DialogFooter } from '@/components/ui/dialog';
import { Select } from '@/components/ui/field';
import { NotConnected } from '@/components/ui/page';
import { StatCard } from '@/components/ui/stat-card';

/**
 * Doğrulama (KYC).
 *
 * The row detail opens a modal, and the modal has no approve button. That is
 * not an omission: the decision belongs to Stripe and the record is written by
 * the webhook, so a button here that granted the badge would be a way to hand
 * out Onaylı Hesap without the check that the badge stands for. The modal is
 * the whole record the vault holds - status, policy version, timestamps - and
 * nothing else, because the vault stores no document, no photo and no name off
 * the ID.
 */
const ORDER = ['verified', 'requires_input', 'created', 'canceled', 'redacted'];

const STATUS_TONE: Record<string, BadgeTone> = {
  verified: 'success',
  requires_input: 'warning',
  created: 'brand',
  canceled: 'neutral',
  redacted: 'neutral',
};

const STATUS_ICON: Record<string, React.ComponentType<{ size?: number; className?: string }>> = {
  verified: ShieldCheck,
  requires_input: TriangleAlert,
  created: FileClock,
  canceled: CircleSlash,
  redacted: Eraser,
};

const memberLabel = (row: VerificationSession) => row.memberName ?? row.memberEmail ?? `${row.userId.slice(0, 8)}…`;

export function VerificationDesk({
  initialOverview,
  initialSessions,
  initialFailure,
}: {
  initialOverview: VerificationOverview | null;
  initialSessions: VerificationSession[];
  initialFailure: string | null;
}) {
  const [overview, setOverview] = useState(initialOverview);
  const [sessions, setSessions] = useState(initialSessions);
  const [failure, setFailure] = useState(initialFailure);
  const [status, setStatus] = useState('');
  const [busy, setBusy] = useState(false);
  const [selected, setSelected] = useState<VerificationSession | null>(null);

  const load = useCallback(async (next: string) => {
    setBusy(true);
    try {
      const params = new URLSearchParams();
      if (next) params.set('status', next);
      const body = await api<{ overview: VerificationOverview | null; sessions: VerificationSession[] }>(`/api/verification?${params}`);
      setOverview(body.data.overview);
      setSessions(body.data.sessions);
      setFailure((body.meta?.failure as string | null) ?? null);
    } catch (error) {
      setFailure(errorText(error, 'Doğrulama kayıtları alınamadı.'));
    } finally {
      setBusy(false);
    }
  }, []);

  // A pending outbox means a member is verified here and not yet verified in the
  // app. Shown as a warning rather than a metric, because it is a fault someone
  // has to act on, not a number to watch go up.
  const backlog = overview?.outbox.pending ?? 0;
  const outboxBroken = overview !== null && (backlog > 0 || !overview.outbox.queueConfigured);

  const columns: ColumnDef<VerificationSession, unknown>[] = [
    {
      id: 'member',
      header: 'Üye',
      accessorFn: (row) => `${row.memberName ?? ''} ${row.memberEmail ?? ''} ${row.userId}`,
      cell: ({ row }) => (
        <div className="min-w-0">
          <p className="font-medium text-ink">{memberLabel(row.original)}</p>
          {row.original.memberEmail && row.original.memberName && (
            <p className="mt-0.5 text-xs text-ink-faint">{row.original.memberEmail}</p>
          )}
        </div>
      ),
    },
    {
      id: 'status',
      header: 'Durum',
      accessorFn: (row) => VERIFICATION_STATUS_LABELS[row.status] ?? row.status,
      cell: ({ row }) => (
        <Badge tone={STATUS_TONE[row.original.status] ?? 'neutral'} dot>
          {VERIFICATION_STATUS_LABELS[row.original.status] ?? row.original.status}
        </Badge>
      ),
    },
    {
      id: 'updatedAt',
      header: 'Son hareket',
      accessorFn: (row) => row.updatedAt,
      cell: ({ row }) => <span className="whitespace-nowrap">{formatDateTime(row.original.updatedAt)}</span>,
    },
    {
      id: 'createdAt',
      header: 'Başlangıç',
      accessorFn: (row) => row.createdAt,
      cell: ({ row }) => <span className="whitespace-nowrap text-ink-faint">{formatDateTime(row.original.createdAt)}</span>,
    },
    {
      id: 'policyVersion',
      header: 'Politika',
      accessorFn: (row) => row.policyVersion,
      cell: ({ row }) => <span className="text-xs text-ink-faint">{row.original.policyVersion}</span>,
    },
  ];

  return (
    <div className="grid gap-6">
      {failure && (
        <NotConnected
          what="Doğrulama kasası yanıt vermedi."
          why={`Servis şu hatayı döndü: ${failure}. Aşağıdaki sayılar ve liste eksik ya da eski olabilir.`}
        />
      )}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
        {ORDER.map((key) => (
          <StatCard
            key={key}
            label={VERIFICATION_STATUS_LABELS[key]}
            value={overview ? String(overview.counts[key] ?? 0) : 'Yanıt yok'}
            unavailable={!overview}
            icon={STATUS_ICON[key]}
            tone={STATUS_TONE[key] ?? 'neutral'}
          />
        ))}
      </div>

      {outboxBroken && overview && (
        <Card tone="urgent">
          <CardContent className="flex items-start gap-3">
            <TriangleAlert size={18} className="mt-0.5 shrink-0 text-danger" />
            <div className="text-sm text-ink-muted">
              <p className="font-medium text-ink">Rozet kuyruğu geride kalmış</p>
              <p className="mt-1">
                {overview.outbox.queueConfigured ? (
                  <>
                    Topluluk servisine iletilmemiş {backlog} yetki olayı var
                    {overview.outbox.oldestPendingAt ? `; en eskisi ${formatDateTime(overview.outbox.oldestPendingAt)}` : ''}. Bu kişiler burada
                    onaylı görünür ama uygulamada rozetleri çıkmaz.
                  </>
                ) : (
                  <>Yetki kuyruğu yapılandırılmamış: onaylanan üyelerin rozeti Topluluk servisine hiç iletilmiyor.</>
                )}
              </p>
            </div>
          </CardContent>
        </Card>
      )}

      <DataTable
        columns={columns}
        rows={sessions}
        rowKey={(row) => row.id}
        onRowClick={setSelected}
        searchPlaceholder="Üye adı, e-posta veya kimlik ara"
        emptyLabel="Bu filtreye uyan doğrulama kaydı yok."
        toolbar={
          <div className="flex items-center gap-2">
            <Select
              value={status}
              aria-label="Durum"
              onChange={(event) => {
                setStatus(event.target.value);
                void load(event.target.value);
              }}
              className="h-8 w-44 py-0 text-xs"
            >
              <option value="">Tüm durumlar</option>
              {ORDER.map((key) => (
                <option key={key} value={key}>
                  {VERIFICATION_STATUS_LABELS[key]}
                </option>
              ))}
            </Select>
            <Button variant="secondary" size="sm" disabled={busy} onClick={() => void load(status)}>
              <RefreshCw size={14} className={busy ? 'animate-spin' : undefined} />
              {busy ? 'Okunuyor…' : 'Yenile'}
            </Button>
          </div>
        }
      />

      <Dialog open={selected !== null} onOpenChange={(open) => !open && setSelected(null)}>
        {selected && (
          <DialogContent title={memberLabel(selected)} description="Doğrulama kaydı — yalnızca okunur.">
            <DialogBody className="grid gap-4">
              <div className="flex flex-wrap items-center gap-2">
                <Badge tone={STATUS_TONE[selected.status] ?? 'neutral'} dot>
                  {VERIFICATION_STATUS_LABELS[selected.status] ?? selected.status}
                </Badge>
                <span className="text-xs text-ink-faint">politika {selected.policyVersion}</span>
              </div>

              <p className="text-sm text-ink-muted">{VERIFICATION_STATUS_HINTS[selected.status] ?? 'Bu durum için açıklama tanımlı değil.'}</p>

              <dl className="grid gap-2 rounded-lg border border-hairline bg-canvas p-4 text-sm">
                {(
                  [
                    ['Üye kimliği', selected.userId],
                    ['E-posta', selected.memberEmail ?? '—'],
                    ['Oturum kimliği', selected.id],
                    ['Başlangıç', formatDateTime(selected.createdAt)],
                    ['Son hareket', formatDateTime(selected.updatedAt)],
                    ['Geçerlilik sonu', selected.expiresAt ? formatDateTime(selected.expiresAt) : 'yok'],
                    ['Stripe verisi silindi', selected.redactedAt ? formatDateTime(selected.redactedAt) : 'hayır'],
                  ] as [string, string][]
                ).map(([label, value]) => (
                  <div key={label} className="flex flex-wrap items-baseline justify-between gap-3">
                    <dt className="text-xs text-ink-faint">{label}</dt>
                    <dd className="font-mono text-xs break-all text-ink-muted">{value}</dd>
                  </div>
                ))}
              </dl>

              <p className="text-xs text-ink-faint">
                Bu ekrandan kimse onaylanamaz veya reddedilemez. Karar Stripe&apos;a aittir ve kayda webhook ile düşer; belge, fotoğraf ve kimlik
                bilgisi kasada hiç saklanmaz.
              </p>
            </DialogBody>
            <DialogFooter>
              <DialogClose asChild>
                <Button variant="secondary">Kapat</Button>
              </DialogClose>
            </DialogFooter>
          </DialogContent>
        )}
      </Dialog>
    </div>
  );
}
