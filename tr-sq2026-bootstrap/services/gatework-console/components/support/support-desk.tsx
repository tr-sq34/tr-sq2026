'use client';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlarmClock, Inbox, LifeBuoy, RefreshCw, Send } from 'lucide-react';
import { api, apiData, errorText } from '@/lib/api-client';
import {
  SUPPORT_STATUS_LABELS,
  SUPPORT_STATUS_TONE,
  SUPPORT_TOPIC_LABELS,
  clientLabel,
  supportMemberLabel,
  supportTime,
  waitingFor,
  type SupportRequest,
  type SupportThread,
} from '@/lib/support-labels';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Field, Select, Textarea } from '@/components/ui/field';
import { EmptyState } from '@/components/ui/page';
import { ReasonDialog } from '@/components/ui/reason-dialog';
import { StatCard } from '@/components/ui/stat-card';
import { cn } from '@/lib/cn';

/**
 * Destek Talepleri.
 *
 * Kuyruk kendi kendine yenileniyor. Yalnızca tıklandığında yenilenen bir destek
 * ekranı, kimse sayfayı açık tutmadığı sürece boş görünür ve üye cevap
 * beklediğini sanarak bekler.
 *
 * Üstteki sayılar yalnızca **görüntülenen listeyi** anlatıyor ve bunu yazıyor
 * da. "Yanıt bekleyen: 3" cümlesi, kapalı talepler filtrelenmişken bütün
 * sistemi anlatıyormuş gibi okunursa, ekranın söylemediği bir şeyi söylemiş
 * olur.
 */
type Props = { initialRequests: SupportRequest[]; initialFailure: string | null; canAnswer: boolean };

const REFRESH_MS = 60_000;

const STATE_LABELS: Record<string, string> = {
  waiting: 'Yanıt bekleyenler',
  open: 'Açık talepler (yanıtlananlar dahil)',
  closed: 'Kapanmış talepler',
  all: 'Tümü',
};

export function SupportDesk({ initialRequests, initialFailure, canAnswer }: Props) {
  const [requests, setRequests] = useState(initialRequests);
  const [failure, setFailure] = useState(initialFailure);
  const [state, setState] = useState('waiting');
  const [topic, setTopic] = useState('');
  const [selectedId, setSelectedId] = useState<string | null>(initialRequests[0]?.id ?? null);
  const [thread, setThread] = useState<SupportThread | null>(null);
  const [threadError, setThreadError] = useState<string | null>(null);
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const [closing, setClosing] = useState(false);
  // Her yenilemede tazeleniyor; yoksa "12 dk bekliyor" sayfanın açıldığı andaki
  // değerde donup kalıyor.
  const [now, setNow] = useState(() => Date.now());

  const load = useCallback(async (nextState: string, nextTopic: string, keepSelection = true) => {
    try {
      const search = new URLSearchParams({ state: nextState });
      if (nextTopic) search.set('topic', nextTopic);
      const body = await api<{ requests: SupportRequest[] }>(`/api/support?${search}`);
      setRequests(body.data.requests);
      setFailure((body.meta?.failure as string | null) ?? null);
      setNow(Date.now());
      if (!keepSelection) setSelectedId(body.data.requests[0]?.id ?? null);
    } catch (error) {
      setFailure(errorText(error, 'Talepler alınamadı.'));
    }
  }, []);

  useEffect(() => {
    const timer = setInterval(() => void load(state, topic), REFRESH_MS);
    return () => clearInterval(timer);
  }, [load, state, topic]);

  // Yazışmayı seçilen talep için ayrıca getiriyoruz: listede yalnızca son mesaj
  // var ve son mesaja bakarak cevap yazmak, üyenin ilk anlattığını okumadan
  // cevap yazmak demek.
  useEffect(() => {
    if (!selectedId) { setThread(null); return; }
    let active = true;
    setThread(null);
    setThreadError(null);
    setDraft('');
    (async () => {
      try {
        const data = await apiData<SupportThread>(`/api/support/requests/${selectedId}`);
        if (active) setThread(data);
      } catch (error) {
        if (active) setThreadError(errorText(error, 'Yazışma okunamadı.'));
      }
    })();
    return () => { active = false; };
  }, [selectedId]);

  const reply = useCallback(async (close: boolean) => {
    if (!selectedId || draft.trim().length < 2) return;
    setBusy(true);
    try {
      await apiData(`/api/support/requests/${selectedId}/reply`, { method: 'POST', body: JSON.stringify({ body: draft.trim(), close }) });
      setDraft('');
      const [refreshed] = await Promise.all([
        apiData<SupportThread>(`/api/support/requests/${selectedId}`).catch(() => null),
        load(state, topic),
      ]);
      if (refreshed) setThread(refreshed);
    } catch (error) {
      setThreadError(errorText(error, 'Yanıt gönderilemedi.'));
    } finally {
      setBusy(false);
    }
  }, [draft, load, selectedId, state, topic]);

  async function confirmClose(reason: string) {
    if (!selectedId) return;
    await apiData(`/api/support/requests/${selectedId}/close`, { method: 'POST', body: JSON.stringify({ reason }) });
    const refreshed = await apiData<SupportThread>(`/api/support/requests/${selectedId}`).catch(() => null);
    if (refreshed) setThread(refreshed);
    await load(state, topic);
  }

  const waiting = useMemo(() => requests.filter((request) => request.status === 'open'), [requests]);
  const longestWait = waiting.reduce<SupportRequest | null>(
    (worst, request) => (worst === null || new Date(request.lastMemberAt) < new Date(worst.lastMemberAt) ? request : worst),
    null,
  );
  const selected = requests.find((request) => request.id === selectedId) ?? null;
  const answerable = thread !== null && thread.status !== 'closed' && canAnswer;

  return (
    <div className="grid gap-5">
      {failure && (
        <p className="rounded-card border border-warning/30 bg-warning-soft p-4 text-sm text-warning">
          Destek servisi yanıt vermedi: {failure}.
          <br />
          <span className="text-xs">Bu, bekleyen talep olmadığı anlamına gelmez — kuyruk sorulamadı.</span>
        </p>
      )}

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Yanıt bekleyen"
          value={String(waiting.length)}
          detail={`seçili görünümde · liste ${REFRESH_MS / 1000} saniyede bir yenilenir`}
          icon={Inbox}
          tone={waiting.length > 0 ? 'warning' : 'success'}
        />
        <StatCard
          label="En uzun bekleyen"
          value={longestWait ? waitingFor(longestWait.lastMemberAt, now) : '—'}
          detail={longestWait ? supportMemberLabel(longestWait) : 'bekleyen talep yok'}
          icon={AlarmClock}
          tone={longestWait ? 'warning' : 'neutral'}
          unavailable={!longestWait}
        />
        <StatCard
          label="Üyede bekleyen"
          value={String(requests.filter((request) => request.status === 'answered').length)}
          detail="yanıtlandı, üye henüz dönmedi"
          icon={LifeBuoy}
          tone="neutral"
        />
        <StatCard
          label="Listedeki toplam"
          value={String(requests.length)}
          detail={STATE_LABELS[state] ?? state}
          icon={Send}
          tone="neutral"
        />
      </div>

      <div className="flex flex-wrap items-end gap-3">
        <Field label="Görünüm" className="w-64">
          <Select
            value={state}
            onChange={(event) => { setState(event.target.value); void load(event.target.value, topic, false); }}
          >
            {Object.entries(STATE_LABELS).map(([value, label]) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </Select>
        </Field>
        <Field label="Konu" className="w-56">
          <Select
            value={topic}
            onChange={(event) => { setTopic(event.target.value); void load(state, event.target.value, false); }}
          >
            <option value="">Tüm konular</option>
            {Object.entries(SUPPORT_TOPIC_LABELS).map(([value, label]) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </Select>
        </Field>
        <Button type="button" variant="secondary" className="mb-[1px]" onClick={() => void load(state, topic)}>
          <RefreshCw size={15} /> Yenile
        </Button>
      </div>

      {requests.length === 0 ? (
        <EmptyState
          icon={Inbox}
          title={state === 'waiting' ? 'Cevap bekleyen talep yok.' : 'Bu görünümde talep yok.'}
          description="Bir üye uygulamadan destek yazdığında bu liste kendiliğinden dolar."
        />
      ) : (
        <section className="grid gap-4 xl:grid-cols-[360px_minmax(0,1fr)]">
          <ul className="max-h-[70vh] divide-y divide-hairline/60 overflow-y-auto rounded-card border border-hairline bg-surface">
            {requests.map((request) => (
              <li key={request.id}>
                <button
                  type="button"
                  onClick={() => setSelectedId(request.id)}
                  className={cn(
                    'w-full px-4 py-3 text-left transition',
                    selectedId === request.id ? 'bg-surface-raised' : 'hover:bg-surface-raised/60',
                    request.status === 'open' && 'border-l-2 border-warning',
                  )}
                >
                  <div className="flex items-center justify-between gap-2">
                    <Badge tone={SUPPORT_STATUS_TONE[request.status]} dot>{SUPPORT_STATUS_LABELS[request.status]}</Badge>
                    {request.status === 'open' && (
                      <span className="text-[11px] whitespace-nowrap text-ink-faint">{waitingFor(request.lastMemberAt, now)} bekliyor</span>
                    )}
                  </div>
                  <p className="mt-1.5 truncate text-sm font-medium text-ink">{request.subject}</p>
                  <p className="truncate text-xs text-ink-faint">
                    {supportMemberLabel(request)} · {SUPPORT_TOPIC_LABELS[request.topic] ?? request.topic} · {supportTime(request.createdAt)}
                  </p>
                </button>
              </li>
            ))}
          </ul>

          {!selected ? (
            <EmptyState title="Soldan bir talep seç." />
          ) : (
            <div className="grid gap-4">
              <div className="rounded-card border border-hairline bg-surface p-5">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge tone={SUPPORT_STATUS_TONE[selected.status]} dot>{SUPPORT_STATUS_LABELS[selected.status]}</Badge>
                  <Badge tone="neutral">{SUPPORT_TOPIC_LABELS[selected.topic] ?? selected.topic}</Badge>
                  <span className="text-xs text-ink-faint">{clientLabel(selected)}</span>
                </div>
                <h2 className="mt-3 text-base font-semibold text-ink">{selected.subject}</h2>
                <p className="mt-1 text-xs text-ink-faint">
                  {supportMemberLabel(selected)} · açılış {supportTime(selected.createdAt)}
                  {selected.lastStaffAt ? ` · son yanıt ${supportTime(selected.lastStaffAt)}` : ' · henüz yanıtlanmadı'}
                </p>
                {selected.closureReason && (
                  <p className="mt-3 text-xs text-ink-faint">Kapanış gerekçesi: {selected.closureReason}</p>
                )}
                <p className="mt-3 text-xs text-ink-faint">
                  Üyeyi panelde açmak için:{' '}
                  <a className="text-brand-300 hover:underline" href={`/members?query=${encodeURIComponent(selected.memberId)}`}>
                    üye kaydı
                  </a>
                </p>
              </div>

              <div className="rounded-card border border-hairline bg-surface p-5">
                <h3 className="text-xs font-medium tracking-wide text-ink-faint uppercase">Yazışma</h3>
                {threadError ? (
                  <p className="mt-3 rounded-lg border border-warning/30 bg-warning-soft p-3 text-sm text-warning">{threadError}</p>
                ) : thread === null ? (
                  <p className="mt-3 text-sm text-ink-faint">Yükleniyor…</p>
                ) : (
                  <ul className="mt-3 grid gap-3">
                    {thread.messages.map((message) => (
                      <li
                        key={message.id}
                        className={cn(
                          'rounded-lg border p-3',
                          message.authorKind === 'staff'
                            ? 'border-brand-400/30 bg-brand-500/5'
                            : 'border-hairline bg-surface-raised',
                        )}
                      >
                        <div className="flex flex-wrap items-center justify-between gap-2">
                          <span className="text-xs font-medium text-ink-muted">
                            {message.authorKind === 'staff' ? 'Destek ekibi' : supportMemberLabel(thread)}
                          </span>
                          <span className="text-[11px] text-ink-faint">{supportTime(message.createdAt)}</span>
                        </div>
                        <p className="mt-1.5 text-sm whitespace-pre-wrap text-ink">{message.body}</p>
                        {message.authorKind === 'staff' && message.authorRoles.length > 0 && (
                          <p className="mt-1 text-[11px] text-ink-faint">Yanıtlayan rol: {message.authorRoles.join(', ')}</p>
                        )}
                      </li>
                    ))}
                  </ul>
                )}

                {!canAnswer ? (
                  <p className="mt-4 text-sm text-ink-faint">Yanıt yazmak Sahip, Güvenlik Yöneticisi, Operasyon Yöneticisi ve Moderatör rollerine açıktır.</p>
                ) : thread?.status === 'closed' ? (
                  <p className="mt-4 text-sm text-ink-faint">
                    Bu talep kapandı. Üye aynı konuda tekrar yazarsa yeni bir talep açılır — kapanmış bir yazışmayı sessizce sürdürmek yerine.
                  </p>
                ) : (
                  <div className="mt-4 grid gap-2">
                    <Field label="Yanıtın" hint="Üye bu metni uygulamada okur ve bildirimi anında düşer. Yanıtın altında senin adın değil, “Destek ekibi” yazar.">
                      <Textarea
                        rows={4}
                        value={draft}
                        onChange={(event) => setDraft(event.target.value)}
                        placeholder="Üyeye ne söyleyeceksin?"
                        disabled={!answerable || busy}
                      />
                    </Field>
                    <div className="flex flex-wrap gap-2">
                      <Button type="button" variant="primary" size="sm" disabled={!answerable || busy || draft.trim().length < 2} onClick={() => void reply(false)}>
                        <Send size={14} /> Yanıtla
                      </Button>
                      <Button type="button" variant="success" size="sm" disabled={!answerable || busy || draft.trim().length < 2} onClick={() => void reply(true)}>
                        Yanıtla ve kapat
                      </Button>
                      <Button type="button" variant="outline" size="sm" disabled={!answerable || busy} onClick={() => setClosing(true)}>
                        Yanıtsız kapat
                      </Button>
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}
        </section>
      )}

      <ReasonDialog
        open={closing}
        onOpenChange={(next) => { if (!next) setClosing(false); }}
        title="Talep yanıtsız kapatılacak"
        description="Neden kapatıyorsun? Bu gerekçe üyeye gösterilir ve kayda geçer. Üyeye söylenecek bir şey varsa kapatmak yerine yanıt yaz."
        confirmLabel="Talebi kapat"
        variant="danger"
        onConfirm={confirmClose}
      />
    </div>
  );
}
