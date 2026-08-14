'use client';
import { useCallback, useMemo, useState } from 'react';
import { Braces, Check, Clock, Copy, RefreshCw, ShieldAlert, Users } from 'lucide-react';
import { api, errorText, formatDateTime } from '@/lib/api-client';
import { OUTCOME_LABELS, SERVICE_LABELS, actionLabel, actorLabel, type AuditRow } from '@/lib/audit-labels';
import { Badge, type BadgeTone } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { DataTable, type ColumnDef } from '@/components/ui/data-table';
import { Dialog, DialogBody, DialogClose, DialogContent, DialogFooter } from '@/components/ui/dialog';
import { Field, Input, Select } from '@/components/ui/field';
import { NotConnected } from '@/components/ui/page';
import { StatCard } from '@/components/ui/stat-card';

/**
 * Sistem ve Denetim.
 *
 * Read-only on purpose: there is no button on this screen that changes
 * anything, because a log an operator can edit proves nothing. The row detail
 * shows the stored record as JSON rather than as a sentence - when somebody is
 * asked "what exactly does the log say", a prettified paragraph is the wrong
 * answer and the raw row is the right one.
 *
 * Only the service filter runs in the browser: all three logs are already in
 * hand, so narrowing to one of them should not cost a round trip to the other
 * two. Outcome, action key, actor and limit change what the services return, so
 * those are a fetch.
 */
const SERVICE_TONE: Record<AuditRow['service'], BadgeTone> = {
  identity: 'brand',
  community: 'success',
  messaging: 'neutral',
};

const OUTCOME_TONE: Record<string, BadgeTone> = {
  succeeded: 'neutral',
  denied: 'danger',
  failed: 'warning',
};

const LIMITS = ['50', '100', '250'];

export function AuditLog({ initialRows, initialFailures }: { initialRows: AuditRow[]; initialFailures: string[] }) {
  const [rows, setRows] = useState(initialRows);
  const [failures, setFailures] = useState(initialFailures);
  const [service, setService] = useState('');
  const [outcome, setOutcome] = useState('');
  const [action, setAction] = useState('');
  const [actorId, setActorId] = useState('');
  const [limit, setLimit] = useState('100');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [selected, setSelected] = useState<AuditRow | null>(null);
  const [copied, setCopied] = useState(false);

  const load = useCallback(async () => {
    setBusy(true);
    setMessage(null);
    try {
      const params = new URLSearchParams({ limit });
      if (outcome) params.set('outcome', outcome);
      // Two characters is the shortest prefix the services accept; anything
      // shorter is dropped there anyway, so it is dropped here too rather than
      // sent and silently ignored.
      if (action.trim().length >= 2) params.set('action', action.trim());
      if (actorId.trim()) params.set('actorId', actorId.trim());
      const body = await api<AuditRow[]>(`/api/audit?${params}`);
      setRows(body.data);
      setFailures((body.meta?.failures as string[]) ?? []);
    } catch (error) {
      setMessage(errorText(error, 'Denetim kaydı alınamadı.'));
    } finally {
      setBusy(false);
    }
  }, [action, actorId, limit, outcome]);

  const visible = useMemo(() => (service ? rows.filter((row) => row.service === service) : rows), [rows, service]);

  // Every number here describes the page in hand, not the whole log, and says
  // so - a "3 reddedilen" that quietly meant "3 in the last 100 rows" would be
  // read as "3 ever".
  const refused = visible.filter((row) => row.outcome !== 'succeeded').length;
  const operators = new Set(visible.map((row) => row.actorId)).size;
  const newest = visible[0]?.createdAt ?? null;

  const copy = async () => {
    if (!selected) return;
    try {
      await navigator.clipboard.writeText(JSON.stringify(selected, null, 2));
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  };

  const columns: ColumnDef<AuditRow, unknown>[] = [
    {
      id: 'createdAt',
      header: 'Zaman',
      accessorFn: (row) => row.createdAt,
      cell: ({ row }) => <span className="whitespace-nowrap text-xs">{formatDateTime(row.original.createdAt)}</span>,
    },
    {
      id: 'service',
      header: 'Servis',
      accessorFn: (row) => SERVICE_LABELS[row.service],
      cell: ({ row }) => <Badge tone={SERVICE_TONE[row.original.service]}>{SERVICE_LABELS[row.original.service]}</Badge>,
    },
    {
      id: 'actor',
      header: 'İşlemi yapan',
      accessorFn: (row) => `${row.actorName ?? ''} ${row.actorEmail ?? ''} ${row.actorId}`,
      cell: ({ row }) => (
        <div className="min-w-0">
          <p className="font-medium text-ink">{actorLabel(row.original)}</p>
          {row.original.actorRoles.length > 0 && <p className="mt-0.5 text-xs text-ink-faint">{row.original.actorRoles.join(', ')}</p>}
        </div>
      ),
    },
    {
      id: 'action',
      header: 'İşlem',
      accessorFn: (row) => `${actionLabel(row.action)} ${row.action}`,
      cell: ({ row }) => (
        <div className="min-w-0">
          <p className="text-ink">{actionLabel(row.original.action)}</p>
          <p className="mt-0.5 font-mono text-[11px] text-ink-faint">{row.original.action}</p>
        </div>
      ),
    },
    {
      id: 'target',
      header: 'Hedef',
      accessorFn: (row) => `${row.targetType} ${row.targetId}`,
      cell: ({ row }) => (
        <div className="min-w-0">
          <p className="text-xs text-ink-muted">{row.original.targetType || '—'}</p>
          <p className="mt-0.5 max-w-56 truncate font-mono text-[11px] text-ink-faint">{row.original.targetId || '—'}</p>
        </div>
      ),
    },
    {
      id: 'outcome',
      header: 'Sonuç',
      accessorFn: (row) => OUTCOME_LABELS[row.outcome] ?? row.outcome,
      cell: ({ row }) =>
        row.original.outcome === 'succeeded' ? (
          <span className="text-xs text-ink-faint">{OUTCOME_LABELS.succeeded}</span>
        ) : (
          <Badge tone={OUTCOME_TONE[row.original.outcome] ?? 'warning'} dot>
            {OUTCOME_LABELS[row.original.outcome] ?? row.original.outcome}
          </Badge>
        ),
    },
  ];

  return (
    <div className="grid gap-6">
      {failures.length > 0 && (
        <NotConnected
          what={`Şu servisin kaydı okunamadı: ${failures.join(', ')}.`}
          why="Aşağıdaki liste eksiktir: okunamayan servisin işlemleri hiç görünmez. Bu, o serviste işlem yapılmadığı anlamına gelmez."
        />
      )}
      {message && (
        <Card tone="urgent">
          <CardContent className="text-sm text-ink-muted">{message}</CardContent>
        </Card>
      )}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label="Bu sayfadaki kayıt" value={String(visible.length)} detail={`en fazla ${limit} kayıt okunur`} icon={Braces} />
        <StatCard
          label="Reddedilen veya başarısız"
          value={String(refused)}
          detail="bu sayfada"
          icon={ShieldAlert}
          tone={refused > 0 ? 'danger' : 'neutral'}
        />
        <StatCard label="Farklı operatör" value={String(operators)} detail="bu sayfada" icon={Users} />
        <StatCard
          label="En son kayıt"
          value={newest ? formatDateTime(newest) : 'Kayıt yok'}
          unavailable={!newest}
          detail="filtreye uyan en yeni işlem"
          icon={Clock}
        />
      </div>

      <Card>
        <CardContent className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          <Field label="Servis" hint="Elde olan kayıtlarda süzer">
            <Select value={service} onChange={(event) => setService(event.target.value)}>
              <option value="">Hepsi</option>
              {Object.entries(SERVICE_LABELS).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Sonuç" hint="Servislere sorar">
            <Select value={outcome} onChange={(event) => setOutcome(event.target.value)}>
              <option value="">Hepsi</option>
              {Object.entries(OUTCOME_LABELS).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="İşlem anahtarı" hint="En az 2 karakter, baştan eşleşir">
            <Input
              value={action}
              onChange={(event) => setAction(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === 'Enter') void load();
              }}
              placeholder="role. · forum_ · news_"
            />
          </Field>
          <Field label="Operatör kimliği" hint="Tam kimlik, kısmi arama değil">
            <Input
              value={actorId}
              onChange={(event) => setActorId(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === 'Enter') void load();
              }}
              placeholder="uuid"
            />
          </Field>
          <div className="flex items-end gap-2">
            <Field label="Kayıt" className="w-24">
              <Select value={limit} onChange={(event) => setLimit(event.target.value)}>
                {LIMITS.map((value) => (
                  <option key={value} value={value}>
                    {value}
                  </option>
                ))}
              </Select>
            </Field>
            <Button variant="primary" disabled={busy} onClick={() => void load()}>
              <RefreshCw size={15} className={busy ? 'animate-spin' : undefined} />
              {busy ? 'Okunuyor…' : 'Uygula'}
            </Button>
          </div>
        </CardContent>
      </Card>

      <DataTable
        columns={columns}
        rows={visible}
        rowKey={(row) => row.id}
        onRowClick={(row) => {
          setCopied(false);
          setSelected(row);
        }}
        isRowUrgent={(row) => row.outcome !== 'succeeded'}
        searchPlaceholder="Operatör, işlem veya hedef ara"
        emptyLabel="Bu filtreye uyan kayıt yok."
      />

      <Dialog open={selected !== null} onOpenChange={(open) => !open && setSelected(null)}>
        {selected && (
          <DialogContent className="max-w-2xl" title={actionLabel(selected.action)} description={`${actorLabel(selected)} · ${formatDateTime(selected.createdAt)}`}>
            <DialogBody className="grid gap-4">
              <div className="flex flex-wrap items-center gap-2">
                <Badge tone={SERVICE_TONE[selected.service]}>{SERVICE_LABELS[selected.service]}</Badge>
                <Badge tone={OUTCOME_TONE[selected.outcome] ?? 'warning'} dot>
                  {OUTCOME_LABELS[selected.outcome] ?? selected.outcome}
                </Badge>
                <span className="text-xs text-ink-faint">akış: {selected.stream}</span>
              </div>

              {selected.reason && (
                <div className="rounded-lg border border-hairline bg-canvas p-4">
                  <p className="text-xs text-ink-faint">Gerekçe</p>
                  <p className="mt-1 text-sm text-ink-muted">{selected.reason}</p>
                </div>
              )}

              <div>
                <p className="mb-1.5 text-xs text-ink-faint">Kaydın tamamı</p>
                <pre className="max-h-80 overflow-auto rounded-lg border border-hairline bg-canvas p-4 font-mono text-xs leading-relaxed whitespace-pre text-ink-muted">
                  {JSON.stringify(selected, null, 2)}
                </pre>
              </div>

              <p className="text-xs text-ink-faint">
                Bu kayıt değiştirilemez ve silinemez; panel yalnızca okur. Alanlar servisten geldiği gibidir, ekranda çevrilmeden gösterilir.
              </p>
            </DialogBody>
            <DialogFooter>
              <Button variant="secondary" onClick={() => void copy()}>
                {copied ? <Check size={15} /> : <Copy size={15} />}
                {copied ? 'Kopyalandı' : 'JSON kopyala'}
              </Button>
              <DialogClose asChild>
                <Button variant="outline">Kapat</Button>
              </DialogClose>
            </DialogFooter>
          </DialogContent>
        )}
      </Dialog>
    </div>
  );
}
