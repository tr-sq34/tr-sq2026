'use client';
import { useCallback, useState } from 'react';
import { OUTCOME_LABELS, SERVICE_LABELS, actionLabel, actorLabel, type AuditRow } from '@/lib/audit-labels';

/**
 * Sistem ve Denetim. Read-only on purpose: there is no button on this screen
 * that changes anything, because a log an operator can edit proves nothing.
 */
const time = (value: string) => new Date(value).toLocaleString('tr-TR', { dateStyle: 'short', timeStyle: 'medium' });

const SERVICE_TONE: Record<AuditRow['service'], string> = {
  identity: 'bg-sky-500/10 text-sky-300',
  community: 'bg-emerald-500/10 text-emerald-300',
  messaging: 'bg-violet-500/10 text-violet-300',
};

export function AuditLog({ initialRows, initialFailures }: { initialRows: AuditRow[]; initialFailures: string[] }) {
  const [rows, setRows] = useState(initialRows);
  const [failures, setFailures] = useState(initialFailures);
  const [service, setService] = useState('');
  const [outcome, setOutcome] = useState('');
  const [action, setAction] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const load = useCallback(async (nextOutcome: string, nextAction: string) => {
    setBusy(true); setMessage(null);
    try {
      const params = new URLSearchParams({ limit: '100' });
      if (nextOutcome) params.set('outcome', nextOutcome);
      if (nextAction.trim().length >= 2) params.set('action', nextAction.trim());
      const response = await fetch(`/api/audit?${params}`, { headers: { 'content-type': 'application/json' } });
      const body = await response.json().catch(() => null);
      if (!response.ok) throw new Error(body?.error?.message ?? 'Denetim kaydı alınamadı.');
      setRows(body.data as AuditRow[]);
      setFailures((body.meta?.failures as string[]) ?? []);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Denetim kaydı alınamadı.');
    } finally {
      setBusy(false);
    }
  }, []);

  // The service filter is applied here rather than sent to the API: all three
  // logs are already in hand, and narrowing to one of them should not cost a
  // round trip to the other two.
  const visible = service ? rows.filter((row) => row.service === service) : rows;

  const field = 'rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-emerald-400';

  return (
    <div className="grid gap-6">
      {failures.length > 0 && (
        <p className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">
          Şu servisin kaydı okunamadı: {failures.join(', ')}. Aşağıdaki liste eksiktir.
        </p>
      )}
      {message && <p className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">{message}</p>}

      <div className="flex flex-wrap items-end gap-3">
        <label className="text-sm">Servis
          <select value={service} onChange={(event) => setService(event.target.value)} className={`mt-1 block ${field}`}>
            <option value="">Hepsi</option>
            {Object.entries(SERVICE_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </label>
        <label className="text-sm">Sonuç
          <select value={outcome} onChange={(event) => { setOutcome(event.target.value); void load(event.target.value, action); }} className={`mt-1 block ${field}`}>
            <option value="">Hepsi</option>
            {Object.entries(OUTCOME_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </label>
        <label className="text-sm">İşlem anahtarı
          <input value={action} onChange={(event) => setAction(event.target.value)} onKeyDown={(event) => { if (event.key === 'Enter') void load(outcome, action); }} placeholder="role. · forum_ · news_" className={`mt-1 block w-56 ${field}`} />
        </label>
        <button type="button" disabled={busy} onClick={() => void load(outcome, action)} className="rounded-lg bg-emerald-500 px-4 py-2 text-sm font-medium text-emerald-950 disabled:opacity-40">
          {busy ? 'Okunuyor…' : 'Yenile'}
        </button>
        <span className="pb-2 text-xs text-zinc-500">{visible.length} kayıt</span>
      </div>

      <div className="grid gap-2">
        {visible.length === 0 && <p className="rounded-xl border border-white/10 bg-zinc-900/40 p-6 text-sm text-zinc-500">Bu filtreye uyan kayıt yok.</p>}
        {visible.map((row) => (
          <article key={row.id} className="rounded-xl border border-white/10 bg-zinc-900/40 p-4">
            <div className="flex flex-wrap items-center gap-2 text-xs">
              <span className={`rounded px-2 py-0.5 ${SERVICE_TONE[row.service]}`}>{SERVICE_LABELS[row.service]}</span>
              {row.outcome !== 'succeeded' && <span className="rounded bg-rose-500/10 px-2 py-0.5 text-rose-300">{OUTCOME_LABELS[row.outcome] ?? row.outcome}</span>}
              <span className="text-zinc-500">{time(row.createdAt)}</span>
            </div>
            <p className="mt-2 text-sm text-zinc-100">
              <span className="font-medium">{actorLabel(row)}</span>
              {row.actorRoles.length > 0 && <span className="text-zinc-500"> ({row.actorRoles.join(', ')})</span>}
              {' — '}{actionLabel(row.action)}
            </p>
            <p className="mt-1 text-xs text-zinc-500">{row.targetType} · {row.targetId} · <span className="text-zinc-600">{row.action}</span></p>
            {row.reason && <p className="mt-2 max-w-3xl text-xs text-zinc-400">Gerekçe: {row.reason}</p>}
          </article>
        ))}
      </div>
    </div>
  );
}
