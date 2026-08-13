'use client';
import { useCallback, useState } from 'react';
import { VERIFICATION_STATUS_HINTS, VERIFICATION_STATUS_LABELS, type VerificationOverview, type VerificationSession } from '@/lib/verification-labels';

/**
 * Doğrulama. Read-only: the decision is Stripe's and the record is the webhook's.
 * A button here that granted the badge would be a way around the check itself.
 */
const time = (value: string) => new Date(value).toLocaleString('tr-TR', { dateStyle: 'short', timeStyle: 'short' });

const STATUS_TONE: Record<string, string> = {
  verified: 'bg-emerald-500/10 text-emerald-300',
  requires_input: 'bg-amber-500/10 text-amber-200',
  created: 'bg-sky-500/10 text-sky-300',
  canceled: 'bg-zinc-800 text-zinc-400',
  redacted: 'bg-zinc-800 text-zinc-500',
};

const ORDER = ['verified', 'requires_input', 'created', 'canceled', 'redacted'];

export function VerificationDesk({ initialOverview, initialSessions, initialFailure }: { initialOverview: VerificationOverview | null; initialSessions: VerificationSession[]; initialFailure: string | null }) {
  const [overview, setOverview] = useState(initialOverview);
  const [sessions, setSessions] = useState(initialSessions);
  const [failure, setFailure] = useState(initialFailure);
  const [status, setStatus] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async (next: string) => {
    setBusy(true);
    try {
      const params = new URLSearchParams();
      if (next) params.set('status', next);
      const response = await fetch(`/api/verification?${params}`, { headers: { 'content-type': 'application/json' } });
      const body = await response.json().catch(() => null);
      if (!response.ok) throw new Error(body?.error?.message ?? 'Doğrulama kayıtları alınamadı.');
      setOverview(body.data.overview as VerificationOverview | null);
      setSessions(body.data.sessions as VerificationSession[]);
      setFailure((body.meta?.failure as string | null) ?? null);
    } catch (error) {
      setFailure(error instanceof Error ? error.message : 'Doğrulama kayıtları alınamadı.');
    } finally {
      setBusy(false);
    }
  }, []);

  const field = 'rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-emerald-400';
  // A pending outbox means a member is verified here and not yet verified in the
  // app. Shown as a warning rather than a metric, because it is a fault someone
  // has to act on, not a number to watch go up.
  const backlog = overview?.outbox.pending ?? 0;

  return (
    <div className="grid gap-6">
      {failure && <p className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">Doğrulama servisi yanıt vermedi: {failure}.</p>}

      {overview && (
        <>
          <div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-5">
            {ORDER.map((key) => (
              <div key={key} className="rounded-xl border border-white/10 bg-zinc-900/40 p-4">
                <p className="text-2xl font-semibold">{overview.counts[key] ?? 0}</p>
                <p className="mt-1 text-xs text-zinc-400">{VERIFICATION_STATUS_LABELS[key]}</p>
              </div>
            ))}
          </div>

          {(backlog > 0 || !overview.outbox.queueConfigured) && (
            <p className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">
              {overview.outbox.queueConfigured
                ? <>Topluluk servisine iletilmemiş {backlog} yetki olayı var{overview.outbox.oldestPendingAt ? `; en eskisi ${time(overview.outbox.oldestPendingAt)}` : ''}. Bu kişiler burada onaylı görünür ama uygulamada rozetleri çıkmaz.</>
                : <>Yetki kuyruğu yapılandırılmamış: onaylanan üyelerin rozeti Topluluk servisine hiç iletilmiyor.</>}
            </p>
          )}
        </>
      )}

      <div className="flex flex-wrap items-end gap-3">
        <label className="text-sm">Durum
          <select value={status} onChange={(event) => { setStatus(event.target.value); void load(event.target.value); }} className={`mt-1 block ${field}`}>
            <option value="">Hepsi</option>
            {ORDER.map((key) => <option key={key} value={key}>{VERIFICATION_STATUS_LABELS[key]}</option>)}
          </select>
        </label>
        <button type="button" disabled={busy} onClick={() => void load(status)} className="rounded-lg bg-emerald-500 px-4 py-2 text-sm font-medium text-emerald-950 disabled:opacity-40">
          {busy ? 'Okunuyor…' : 'Yenile'}
        </button>
        <span className="pb-2 text-xs text-zinc-500">{sessions.length} kayıt</span>
      </div>

      <div className="grid gap-2">
        {sessions.length === 0 && <p className="rounded-xl border border-white/10 bg-zinc-900/40 p-6 text-sm text-zinc-500">Bu filtreye uyan doğrulama kaydı yok.</p>}
        {sessions.map((row) => (
          <article key={row.id} className="rounded-xl border border-white/10 bg-zinc-900/40 p-4">
            <div className="flex flex-wrap items-center gap-2 text-xs">
              <span className={`rounded px-2 py-0.5 ${STATUS_TONE[row.status] ?? 'bg-zinc-800 text-zinc-300'}`}>{VERIFICATION_STATUS_LABELS[row.status] ?? row.status}</span>
              <span className="text-zinc-500">son hareket {time(row.updatedAt)}</span>
              <span className="text-zinc-600">başlangıç {time(row.createdAt)}</span>
            </div>
            <p className="mt-2 text-sm text-zinc-100">
              {row.memberName ?? `${row.userId.slice(0, 8)}…`}
              {row.memberEmail && <span className="text-zinc-500"> · {row.memberEmail}</span>}
            </p>
            <p className="mt-1 text-xs text-zinc-400">{VERIFICATION_STATUS_HINTS[row.status] ?? ''}</p>
            <p className="mt-1 text-xs text-zinc-600">politika {row.policyVersion}{row.redactedAt ? ` · Stripe verisi silindi ${time(row.redactedAt)}` : ''}</p>
          </article>
        ))}
      </div>
    </div>
  );
}
