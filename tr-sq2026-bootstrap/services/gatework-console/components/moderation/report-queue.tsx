'use client';
import { useCallback, useEffect, useState } from 'react';
import { AlertTriangle, Clock } from 'lucide-react';
import { apiData, errorText, formatDateTime } from '@/lib/api-client';
import { REPORT_CATEGORY_LABELS, REPORT_STATUS_LABELS } from '@/lib/moderation-labels';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Field, Input, Select, Textarea } from '@/components/ui/field';
import { EmptyState } from '@/components/ui/page';
import { cn } from '@/lib/cn';

/**
 * The split screen both moderation queues are.
 *
 * Messaging reports and content reports were two files that had drifted into
 * near-identical copies of each other: the same three status tabs, the same
 * scrolling list, the same detail column, the same decision form with two words
 * changed. A fix applied to one - the deadline countdown, the "claim before you
 * decide" button - reached the other only when somebody remembered.
 *
 * What genuinely differs is the evidence and the set of actions, so those are
 * the two things a caller passes in. Everything else is here, once.
 */
export type QueueSummary = {
  id: string;
  category: string;
  priority: 'urgent' | 'standard';
  status: string;
  dueAt: string;
  overdue: boolean;
  createdAt: string;
  reportedUserId: string | null;
  reportedUserName: string | null;
};

export type QueueDetail = {
  id: string;
  status: string;
  category: string;
  overdue: boolean;
  resolution: string | null;
  resolvedAt: string | null;
};

export type DecisionAction = { value: string; label: string; needsRestriction?: boolean };

const STATUS_FILTERS: [string, string][] = [
  ['unresolved', 'Kuyruk'],
  ['actioned', 'İşlem yapılan'],
  ['dismissed', 'Reddedilen'],
];

/**
 * The deadline, in words.
 *
 * Rendered from the timestamp the service stored rather than counted down in
 * the browser, so a console left open overnight reports the same remaining time
 * as every other reviewer's.
 */
export function Remaining({ dueAt, overdue }: { dueAt: string; overdue: boolean }) {
  const minutes = Math.round((new Date(dueAt).getTime() - Date.now()) / 60_000);
  if (overdue || minutes < 0) {
    const late = Math.abs(minutes);
    return <span className="font-medium text-danger">{late < 60 ? `${late} dk geçti` : `${Math.floor(late / 60)} sa geçti`}</span>;
  }
  return (
    <span className={minutes < 120 ? 'font-medium text-warning' : 'text-ink-faint'}>
      {minutes < 60 ? `${minutes} dk kaldı` : `${Math.floor(minutes / 60)} sa kaldı`}
    </span>
  );
}

export function ReportQueue<S extends QueueSummary, D extends QueueDetail>({
  initialReports,
  canAct,
  endpoint,
  emptyLabel,
  rowSubtitle,
  renderDetail,
  actions,
  restrictionLabel,
  removeWithRestriction,
}: {
  initialReports: S[];
  canAct: boolean;
  /** Base path of the queue, e.g. `/api/moderation/reports`. */
  endpoint: string;
  emptyLabel: string;
  rowSubtitle: (report: S) => string;
  renderDetail: (detail: D) => React.ReactNode;
  actions: DecisionAction[];
  /** Names differ per queue: `restriction` applies to a sender or to an author. */
  restrictionLabel: string;
  /** The decision body's boolean field and the sentence next to its switch. */
  removeWithRestriction: { field: string; label: string };
}) {
  const [reports, setReports] = useState(initialReports);
  const [status, setStatus] = useState('unresolved');
  const [selectedId, setSelectedId] = useState<string | null>(initialReports[0]?.id ?? null);
  const [detail, setDetail] = useState<D | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async (next: string) => {
    setStatus(next);
    try {
      const rows = await apiData<S[]>(`${endpoint}?status=${next}`);
      setReports(rows);
      setSelectedId(rows[0]?.id ?? null);
      setError(null);
    } catch (caught) {
      setError(errorText(caught, 'Liste yenilenemedi.'));
    }
  }, [endpoint]);

  useEffect(() => {
    if (!selectedId) { setDetail(null); return; }
    let active = true;
    setDetail(null);
    apiData<D>(`${endpoint}/${selectedId}`)
      .then((row) => { if (active) setDetail(row); })
      .catch((caught: unknown) => { if (active) setError(errorText(caught, 'Şikâyet açılamadı.')); });
    return () => { active = false; };
  }, [selectedId, endpoint]);

  async function claim() {
    if (!detail) return;
    setBusy(true); setError(null);
    try {
      await apiData(`${endpoint}/${detail.id}/claim`, { method: 'POST', body: '{}' });
      setDetail({ ...detail, status: 'in_review' } as D);
      setNotice('Şikâyet üstlenildi; artık senin adına açık.');
    } catch (caught) {
      setError(errorText(caught, 'Şikâyet üstlenilemedi.'));
    } finally {
      setBusy(false);
    }
  }

  async function decide(form: FormData) {
    if (!detail) return;
    setBusy(true); setError(null); setNotice(null);
    try {
      const action = String(form.get('action'));
      const needsRestriction = actions.find((item) => item.value === action)?.needsRestriction === true;
      const durationRaw = String(form.get('durationHours') ?? '');
      await apiData(`${endpoint}/${detail.id}/decision`, {
        method: 'POST',
        body: JSON.stringify({
          action,
          reason: form.get('reason'),
          restriction: needsRestriction ? form.get('restriction') : undefined,
          // Empty means indefinite, which is a different decision from "one
          // hour" and must not silently become a number.
          durationHours: needsRestriction && durationRaw ? Number(durationRaw) : undefined,
          [removeWithRestriction.field]: form.get(removeWithRestriction.field) === 'on',
        }),
      });
      setNotice('Karar kaydedildi ve denetim kaydına yazıldı.');
      await refresh(status);
    } catch (caught) {
      setError(errorText(caught, 'Karar kaydedilemedi.'));
    } finally {
      setBusy(false);
    }
  }

  const resolved = detail?.status === 'actioned' || detail?.status === 'dismissed';

  return (
    <section className="grid gap-4 xl:grid-cols-[360px_minmax(0,1fr)]">
      <div className="rounded-card border border-hairline bg-surface">
        <div className="flex flex-wrap gap-1 border-b border-hairline p-2">
          {STATUS_FILTERS.map(([value, label]) => (
            <button
              key={value}
              type="button"
              onClick={() => void refresh(value)}
              className={cn(
                'rounded-lg px-3 py-1.5 text-xs font-medium transition',
                status === value ? 'bg-brand-500 text-white' : 'text-ink-muted hover:bg-surface-overlay hover:text-ink',
              )}
            >
              {label}
            </button>
          ))}
        </div>
        <ul className="max-h-[70vh] divide-y divide-hairline/60 overflow-y-auto">
          {reports.length === 0 && <li className="p-6 text-sm text-ink-faint">{emptyLabel}</li>}
          {reports.map((report) => (
            <li key={report.id}>
              <button
                type="button"
                onClick={() => setSelectedId(report.id)}
                className={cn(
                  'w-full px-4 py-3 text-left transition',
                  selectedId === report.id ? 'bg-surface-raised' : 'hover:bg-surface-raised/60',
                  report.overdue && 'border-l-2 border-danger',
                )}
              >
                <div className="flex items-center justify-between gap-2">
                  <Badge tone={report.priority === 'urgent' ? 'danger' : 'neutral'}>
                    {REPORT_CATEGORY_LABELS[report.category] ?? report.category}
                  </Badge>
                  <span className="text-[11px] whitespace-nowrap"><Remaining dueAt={report.dueAt} overdue={report.overdue} /></span>
                </div>
                <p className="mt-1.5 truncate text-sm text-ink">
                  {report.reportedUserName ?? report.reportedUserId?.slice(0, 8) ?? 'Kullanıcı belirsiz'}
                </p>
                <p className="truncate text-xs text-ink-faint">{rowSubtitle(report)}</p>
              </button>
            </li>
          ))}
        </ul>
      </div>

      <div className="grid gap-4">
        {error && <div className="rounded-card border border-danger/30 bg-danger-soft p-4 text-sm text-danger">{error}</div>}
        {notice && <div className="rounded-card border border-success/30 bg-success-soft p-4 text-sm text-success">{notice}</div>}

        {!detail ? (
          <EmptyState
            icon={Clock}
            title="Soldan bir şikâyet seç."
            description="Liste, son işlem tarihi en yakın olan şikâyetten başlar."
          />
        ) : (
          <>
            <div className="rounded-card border border-hairline bg-surface p-5">
              <div className="flex flex-wrap items-center gap-2">
                <h2 className="mr-1 text-base font-semibold text-ink">{REPORT_CATEGORY_LABELS[detail.category] ?? detail.category}</h2>
                <Badge tone={detail.status === 'open' ? 'warning' : detail.status === 'in_review' ? 'brand' : 'neutral'} dot>
                  {REPORT_STATUS_LABELS[detail.status] ?? detail.status}
                </Badge>
                {detail.overdue && <Badge tone="danger"><AlertTriangle size={12} /> Süre aşıldı</Badge>}
              </div>
              {renderDetail(detail)}
            </div>

            {resolved && (
              <div className="rounded-card border border-hairline bg-surface-raised p-4 text-sm text-ink-muted">
                Sonuç: {detail.resolution}
                {detail.resolvedAt && ` · ${formatDateTime(detail.resolvedAt)}`}
              </div>
            )}

            {canAct && !resolved && (
              <form
                action={decide}
                className="rounded-card border border-hairline bg-surface p-5"
              >
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <h3 className="text-sm font-semibold text-ink">Karar</h3>
                    <p className="mt-1 text-xs text-ink-faint">Reddetme dahil her karar gerekçesiyle denetim kaydına yazılır.</p>
                  </div>
                  {detail.status === 'open' && (
                    <Button type="button" size="sm" variant="secondary" disabled={busy} onClick={() => void claim()}>
                      İncelemeyi üstlen
                    </Button>
                  )}
                </div>

                <div className="mt-4 grid gap-4 sm:grid-cols-2">
                  <Field label="İşlem" className="sm:col-span-2">
                    <Select name="action" defaultValue={actions[0]?.value}>
                      {actions.map((item) => <option key={item.value} value={item.value}>{item.label}</option>)}
                    </Select>
                  </Field>
                  <Field label={restrictionLabel} hint="Yalnızca kısıtlama işlemlerinde kullanılır.">
                    <Select name="restriction" defaultValue="muted">
                      <option value="muted">Susturma (okuyabilir, yazamaz)</option>
                      <option value="suspended">Askıya alma</option>
                    </Select>
                  </Field>
                  <Field label="Süre (saat)" hint="Boş bırakılırsa süresiz. Süresiz, “bir saat” kadar açık bir karardır.">
                    <Input name="durationHours" type="number" min={1} max={8760} placeholder="24" />
                  </Field>
                </div>

                <label className="mt-4 flex items-center gap-2 text-sm text-ink-muted">
                  <input type="checkbox" name={removeWithRestriction.field} className="size-4 rounded border-hairline bg-canvas" />
                  {removeWithRestriction.label}
                </label>

                <Field label="Gerekçe" hint="Denetim kaydına aynen yazılır ve silinemez." className="mt-4">
                  <Textarea name="reason" required minLength={5} maxLength={500} rows={3} placeholder="Bu kararın nedenini bir cümleyle yaz." />
                </Field>

                <Button type="submit" variant="primary" className="mt-4" disabled={busy}>
                  {busy ? 'Uygulanıyor…' : 'Kararı uygula'}
                </Button>
              </form>
            )}
            {!canAct && !resolved && (
              <p className="text-sm text-ink-faint">Rolün yalnızca görüntülemeye izin veriyor; karar veremezsin.</p>
            )}
          </>
        )}
      </div>
    </section>
  );
}

/// Shared by both detail panels: the pairs above the evidence.
export function DetailFacts({ rows }: { rows: [string, string][] }) {
  return (
    <dl className="mt-4 grid gap-x-8 gap-y-3 text-sm sm:grid-cols-2">
      {rows.map(([label, value]) => (
        <div key={label}>
          <dt className="text-xs text-ink-faint">{label}</dt>
          <dd className="truncate text-ink">{value}</dd>
        </div>
      ))}
    </dl>
  );
}

/// Shared by both detail panels: prior reports and the action trail.
export function DetailHistory({ title, items }: { title: string; items: { key: string; text: string }[] }) {
  if (items.length === 0) return null;
  return (
    <div className="mt-5">
      <h3 className="text-xs font-medium tracking-wide text-ink-faint uppercase">{title}</h3>
      <ul className="mt-2 grid gap-1 text-sm text-ink-muted">
        {items.map((item) => <li key={item.key}>{item.text}</li>)}
      </ul>
    </div>
  );
}
