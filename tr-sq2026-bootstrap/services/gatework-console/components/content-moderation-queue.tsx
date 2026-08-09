'use client';
import { useCallback, useEffect, useState } from 'react';
import { REPORT_CATEGORY_LABELS, REPORT_STATUS_LABELS } from '@/lib/moderation-labels';
import { CONTENT_ACTION_LABELS, CONTENT_STATE_LABELS, CONTENT_TARGET_LABELS, type ContentReportDetail, type ContentReportSummary } from '@/lib/content-moderation-labels';

async function call<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, { ...init, headers: { 'content-type': 'application/json', ...(init?.headers ?? {}) } });
  const body = await response.json().catch(() => null);
  if (!response.ok) throw new Error(body?.error?.message ?? 'İşlem tamamlanamadı.');
  return body.data as T;
}

const time = (value: string) => new Date(value).toLocaleString('tr-TR', { dateStyle: 'short', timeStyle: 'short' });

// Rendered from the deadline community stored, so a console left open overnight
// still reports the same remaining time as any other reviewer's.
function Remaining({ dueAt, overdue }: { dueAt: string; overdue: boolean }) {
  const minutes = Math.round((new Date(dueAt).getTime() - Date.now()) / 60_000);
  if (overdue || minutes < 0) return <span className="text-rose-400">{Math.abs(minutes) < 60 ? `${Math.abs(minutes)} dk geçti` : `${Math.floor(Math.abs(minutes) / 60)} sa geçti`}</span>;
  return <span className={minutes < 120 ? 'text-amber-300' : 'text-zinc-400'}>{minutes < 60 ? `${minutes} dk kaldı` : `${Math.floor(minutes / 60)} sa kaldı`}</span>;
}

export function ContentModerationQueue({ initialReports, canAct }: { initialReports: ContentReportSummary[]; canAct: boolean }) {
  const [reports, setReports] = useState(initialReports);
  const [status, setStatus] = useState('unresolved');
  const [selectedId, setSelectedId] = useState<string | null>(initialReports[0]?.id ?? null);
  const [detail, setDetail] = useState<ContentReportDetail | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async (next: string) => {
    setStatus(next);
    try {
      const rows = await call<ContentReportSummary[]>(`/api/moderation/content/reports?status=${next}`);
      setReports(rows);
      setSelectedId(rows[0]?.id ?? null);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Liste yenilenemedi.');
    }
  }, []);

  useEffect(() => {
    if (!selectedId) { setDetail(null); return; }
    let active = true;
    setDetail(null);
    call<ContentReportDetail>(`/api/moderation/content/reports/${selectedId}`)
      .then((row) => { if (active) setDetail(row); })
      .catch((error: unknown) => { if (active) setMessage(error instanceof Error ? error.message : 'Şikâyet açılamadı.'); });
    return () => { active = false; };
  }, [selectedId]);

  async function decide(form: FormData) {
    if (!detail) return;
    setBusy(true); setMessage(null);
    try {
      const action = String(form.get('action'));
      const durationRaw = String(form.get('durationHours') ?? '');
      await call(`/api/moderation/content/reports/${detail.id}/decision`, {
        method: 'POST',
        body: JSON.stringify({
          action,
          reason: form.get('reason'),
          restriction: action === 'restrict_author' ? form.get('restriction') : undefined,
          // Empty means indefinite, which is a different decision from "one
          // hour" and must not silently become a number.
          durationHours: action === 'restrict_author' && durationRaw ? Number(durationRaw) : undefined,
          removeContent: form.get('removeContent') === 'on',
        }),
      });
      setMessage('Karar kaydedildi.');
      await refresh(status);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Karar kaydedilemedi.');
    } finally {
      setBusy(false);
    }
  }

  async function claim() {
    if (!detail) return;
    setBusy(true); setMessage(null);
    try {
      await call(`/api/moderation/content/reports/${detail.id}/claim`, { method: 'POST', body: '{}' });
      setDetail({ ...detail, status: 'in_review' });
      setMessage('Şikâyet üstlenildi.');
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Şikâyet üstlenilemedi.');
    } finally {
      setBusy(false);
    }
  }

  const field = 'mt-1 w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-emerald-400';
  const resolved = detail?.status === 'actioned' || detail?.status === 'dismissed';
  const gone = detail ? ['removed', 'deleted', 'expired'].includes(detail.targetState) : false;

  return (
    <section className="grid gap-6 xl:grid-cols-[380px_1fr]">
      <div className="rounded-xl border border-white/10 bg-zinc-900/40">
        <div className="flex gap-2 border-b border-white/10 p-3">
          {[['unresolved', 'Kuyruk'], ['actioned', 'İşlem yapılan'], ['dismissed', 'Reddedilen']].map(([value, label]) => (
            <button key={value} type="button" onClick={() => void refresh(value)} className={`rounded-lg px-3 py-1.5 text-xs font-medium ${status === value ? 'bg-emerald-400 text-zinc-950' : 'bg-zinc-800 text-zinc-300'}`}>{label}</button>
          ))}
        </div>
        <ul className="max-h-[70vh] divide-y divide-white/5 overflow-y-auto">
          {reports.length === 0 && <li className="p-6 text-sm text-zinc-500">Bu filtrede içerik şikâyeti yok.</li>}
          {reports.map((report) => (
            <li key={report.id}>
              <button type="button" onClick={() => setSelectedId(report.id)} className={`w-full px-4 py-3 text-left transition ${selectedId === report.id ? 'bg-zinc-800' : 'hover:bg-zinc-800/50'}`}>
                <div className="flex items-center justify-between gap-2">
                  <span className={`rounded px-1.5 py-0.5 text-[11px] font-semibold ${report.priority === 'urgent' ? 'bg-rose-500/20 text-rose-300' : 'bg-zinc-700 text-zinc-300'}`}>{REPORT_CATEGORY_LABELS[report.category] ?? report.category}</span>
                  <span className="text-[11px]"><Remaining dueAt={report.dueAt} overdue={report.overdue} /></span>
                </div>
                <p className="mt-1.5 truncate text-sm text-zinc-200">{report.reportedUserName ?? report.reportedUserId.slice(0, 8)}</p>
                <p className="truncate text-xs text-zinc-500">{CONTENT_TARGET_LABELS[report.targetType] ?? report.targetType} · {time(report.createdAt)}</p>
              </button>
            </li>
          ))}
        </ul>
      </div>

      <div className="rounded-xl border border-white/10 bg-zinc-900/40 p-6">
        {!detail && <p className="text-sm text-zinc-500">Soldan bir şikâyet seç.</p>}
        {detail && (
          <>
            <div className="flex flex-wrap items-center gap-3">
              <h2 className="text-xl font-semibold">{REPORT_CATEGORY_LABELS[detail.category] ?? detail.category}</h2>
              <span className="rounded bg-zinc-800 px-2 py-0.5 text-xs text-zinc-300">{REPORT_STATUS_LABELS[detail.status] ?? detail.status}</span>
              <span className="rounded bg-zinc-800 px-2 py-0.5 text-xs text-zinc-300">{CONTENT_TARGET_LABELS[detail.targetType] ?? detail.targetType}</span>
              {detail.overdue && <span className="rounded bg-rose-500/20 px-2 py-0.5 text-xs text-rose-300">Süre aşıldı</span>}
            </div>
            <dl className="mt-4 grid gap-x-8 gap-y-2 text-sm sm:grid-cols-2">
              <div><dt className="text-zinc-500">Şikâyet eden</dt><dd className="text-zinc-200">{detail.reporterName ?? detail.reporterId.slice(0, 8)}</dd></div>
              <div><dt className="text-zinc-500">İçeriğin sahibi</dt><dd className="text-zinc-200">{detail.reportedUserName ?? detail.reportedUserId.slice(0, 8)}</dd></div>
              <div><dt className="text-zinc-500">İçeriğin şu anki durumu</dt><dd className="text-zinc-200">{CONTENT_STATE_LABELS[detail.targetState] ?? detail.targetState}</dd></div>
              <div><dt className="text-zinc-500">Son işlem tarihi</dt><dd className="text-zinc-200">{time(detail.dueAt)}</dd></div>
            </dl>
            {detail.note && <p className="mt-4 rounded-lg border border-white/10 bg-zinc-950/60 p-3 text-sm text-zinc-300"><span className="text-zinc-500">Kullanıcının açıklaması: </span>{detail.note}</p>}
            {detail.activeRestriction && <p className="mt-4 rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-sm text-amber-200">Bu kullanıcıda etkin kısıtlama var: {detail.activeRestriction === 'suspended' ? 'askıya alınmış' : 'susturulmuş'}</p>}

            <h3 className="mt-6 text-sm font-semibold text-zinc-300">
              Kanıt <span className="font-normal text-zinc-500">({detail.evidence.createdAt ? `içerik ${time(detail.evidence.createdAt)} tarihinde paylaşılmış` : 'zaman bilgisi yok'})</span>
            </h3>
            {/* The snapshot, not the live row. An author deleting the post a
                second after the report was filed must not empty the case file. */}
            <div className="mt-2 rounded-lg border border-rose-500/40 bg-rose-500/10 p-3">
              {detail.evidence.body
                ? <p className="whitespace-pre-wrap break-words text-sm text-zinc-100">{detail.evidence.body}</p>
                : <p className="text-sm text-zinc-400">Bu içerik metin taşımıyor.</p>}
              {(detail.evidence.mediaIds?.length ?? 0) > 0 && <p className="mt-2 text-xs text-zinc-400">Ekli medya: {detail.evidence.mediaIds!.join(', ')}</p>}
              {detail.evidence.mediaId && <p className="mt-2 text-xs text-zinc-400">Medya: {detail.evidence.mediaId}</p>}
              {detail.evidence.postId && <p className="mt-2 text-xs text-zinc-400">Bağlı paylaşım: {detail.evidence.postId}</p>}
            </div>
            {gone && <p className="mt-2 text-xs text-zinc-500">İçerik artık yayında değil ({CONTENT_STATE_LABELS[detail.targetState] ?? detail.targetState}); yukarıdaki metin şikâyet anında alınan kopyadır.</p>}

            {detail.authorHistory.length > 0 && (
              <>
                <h3 className="mt-6 text-sm font-semibold text-zinc-300">Aynı kullanıcı hakkındaki diğer şikâyetler</h3>
                <ul className="mt-2 grid gap-1 text-sm text-zinc-400">
                  {detail.authorHistory.map((prior) => <li key={prior.id}>{time(prior.createdAt)} · {REPORT_CATEGORY_LABELS[prior.category] ?? prior.category} · {REPORT_STATUS_LABELS[prior.status] ?? prior.status}</li>)}
                </ul>
              </>
            )}

            {detail.actions.length > 0 && (
              <>
                <h3 className="mt-6 text-sm font-semibold text-zinc-300">Denetim kaydı</h3>
                <ul className="mt-2 grid gap-1 text-sm text-zinc-400">
                  {detail.actions.map((action, index) => <li key={`${action.action}-${index}`}>{time(action.createdAt)} · {CONTENT_ACTION_LABELS[action.action] ?? action.action} · {action.reason}</li>)}
                </ul>
              </>
            )}

            {resolved && <p className="mt-6 rounded-lg border border-white/10 bg-zinc-950/60 p-3 text-sm text-zinc-300">Sonuç: {detail.resolution} {detail.resolvedAt && `· ${time(detail.resolvedAt)}`}</p>}

            {canAct && !resolved && (
              <form action={decide} className="mt-6 rounded-xl border border-white/10 bg-zinc-950/40 p-5">
                <div className="flex items-center justify-between">
                  <h3 className="font-semibold">Karar</h3>
                  {detail.status === 'open' && <button type="button" onClick={() => void claim()} disabled={busy} className="rounded-lg bg-zinc-800 px-3 py-1.5 text-xs text-zinc-200 disabled:opacity-40">İncelemeyi üstlen</button>}
                </div>
                <label className="mt-4 block text-sm">İşlem
                  <select name="action" className={field} defaultValue="dismiss">
                    <option value="dismiss">Kural ihlali yok — reddet</option>
                    <option value="remove_content">İçeriği kaldır</option>
                    <option value="restrict_author">Yazarı kısıtla</option>
                  </select>
                </label>
                <div className="mt-4 grid gap-4 sm:grid-cols-2">
                  <label className="block text-sm">Kısıtlama türü
                    <select name="restriction" className={field} defaultValue="muted">
                      <option value="muted">Susturma (paylaşamaz, okuyabilir)</option>
                      <option value="suspended">Askıya alma</option>
                    </select>
                  </label>
                  <label className="block text-sm">Süre (saat) <span className="text-zinc-600">boş = süresiz</span>
                    <input name="durationHours" type="number" min={1} max={8760} className={field} placeholder="24" />
                  </label>
                </div>
                <label className="mt-4 flex items-center gap-2 text-sm text-zinc-300">
                  <input type="checkbox" name="removeContent" className="size-4 rounded border-zinc-700 bg-zinc-950" />
                  Kısıtlamayla birlikte şikâyet edilen içeriği de kaldır
                </label>
                <label className="mt-4 block text-sm">Gerekçe <span className="text-zinc-600">(denetim kaydına yazılır)</span>
                  <textarea name="reason" required minLength={5} maxLength={500} rows={3} className={field} />
                </label>
                <button disabled={busy} className="mt-4 rounded-lg bg-emerald-400 px-4 py-2 text-sm font-semibold text-zinc-950 disabled:opacity-40">Kararı uygula</button>
              </form>
            )}
            {!canAct && !resolved && <p className="mt-6 text-sm text-zinc-500">Rolün yalnızca görüntülemeye izin veriyor.</p>}
          </>
        )}
        {message && <p className="mt-4 rounded-lg border border-white/10 bg-zinc-900 p-3 text-sm text-zinc-300">{message}</p>}
      </div>
    </section>
  );
}
