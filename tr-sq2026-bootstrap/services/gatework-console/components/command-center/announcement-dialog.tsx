'use client';
import { useCallback, useEffect, useState } from 'react';
import { Ban, CheckCircle2, Megaphone } from 'lucide-react';
import { api, apiData, errorText, formatDateTime } from '@/lib/api-client';
import type { AnnouncementRow } from '@/lib/announcements';
import { Button } from '@/components/ui/button';
import { Dialog, DialogBody, DialogContent, DialogFooter, DialogTrigger } from '@/components/ui/dialog';
import { Field, Input, Textarea } from '@/components/ui/field';

/**
 * "Global duyuru geç".
 *
 * There is no audience picker and there will not be one until somebody asks for
 * it: this action means everybody, and a half-built segment control would be a
 * promise the service does not keep.
 *
 * Two things this screen does that an ordinary composer does not. It asks twice,
 * because a duyuru cannot be recalled - the rows are already in every member's
 * bell by the time the request returns. And it lists what was sent before,
 * because the most likely mistake here is not a typo, it is sending the same
 * notice again an hour later when nobody remembers whether the first one went.
 */
type Notice = { tone: 'ok' | 'bad'; text: string };

const LIMITS = { title: 120, body: 2000 };

export function AnnouncementDialog({ canSend }: { canSend: boolean }) {
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<Notice | null>(null);
  const [history, setHistory] = useState<AnnouncementRow[] | null>(null);
  const [historyFailure, setHistoryFailure] = useState<string | null>(null);

  const loadHistory = useCallback(async () => {
    try {
      setHistory(await apiData<AnnouncementRow[]>('/api/announcements'));
      setHistoryFailure(null);
    } catch (error) {
      // The list failing must not stop a send: the composer below still works,
      // and pretending there were no earlier duyuru would be the worse answer.
      setHistory(null);
      setHistoryFailure(errorText(error, 'Geçmiş duyurular okunamadı.'));
    }
  }, []);

  useEffect(() => {
    if (open) void loadHistory();
  }, [open, loadHistory]);

  const ready = title.trim().length >= 3 && body.trim().length >= 3;

  async function send() {
    setBusy(true);
    try {
      const result = await api<{ id: string; recipientCount: number; duplicate: boolean }>('/api/announcements', {
        method: 'POST',
        body: JSON.stringify({ title: title.trim(), body: body.trim() }),
      });
      setNotice({
        tone: 'ok',
        text: `Duyuru ${result.data.recipientCount} üyenin bildirim kutusuna düştü.`,
      });
      setTitle('');
      setBody('');
      setConfirming(false);
      await loadHistory();
    } catch (error) {
      setNotice({ tone: 'bad', text: errorText(error, 'Duyuru gönderilemedi.') });
      setConfirming(false);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        // Closing mid-confirmation and reopening should not land on a primed
        // "evet, gönder" button over text the operator has forgotten writing.
        if (!next) {
          setConfirming(false);
          setNotice(null);
        }
      }}
    >
      <DialogTrigger asChild>
        <Button
          variant="outline"
          size="sm"
          disabled={!canSend}
          title={canSend ? undefined : 'Duyuru göndermek yalnızca sahip ve operasyon yöneticisinde'}
        >
          <Megaphone size={15} /> Global duyuru geç
        </Button>
      </DialogTrigger>

      <DialogContent
        title="Global duyuru"
        description="Bu metin bütün üyelerin bildirim kutusuna düşer. Kime gideceğini seçmek yok: ya herkes, ya kimse."
        className="max-w-2xl"
      >
        <DialogBody className="grid gap-4">
          {notice && (
            <p
              className={`flex items-start gap-2.5 rounded-lg border px-3.5 py-3 text-sm ${
                notice.tone === 'bad' ? 'border-danger/40 bg-danger-soft text-ink-muted' : 'border-hairline bg-surface-raised text-ink-muted'
              }`}
            >
              {notice.tone === 'bad'
                ? <Ban size={16} className="mt-0.5 shrink-0 text-danger" />
                : <CheckCircle2 size={16} className="mt-0.5 shrink-0 text-success" />}
              {notice.text}
            </p>
          )}

          <Field label="Başlık" hint={`${title.trim().length}/${LIMITS.title} · bildirim listesinde görünen satır`}>
            <Input
              value={title}
              maxLength={LIMITS.title}
              onChange={(event) => setTitle(event.target.value)}
              placeholder="Bakım çalışması: Cumartesi 02:00–04:00"
            />
          </Field>

          <Field label="Duyuru metni" hint={`${body.trim().length}/${LIMITS.body} · üye bildirime dokununca bu metni okur`}>
            <Textarea
              value={body}
              maxLength={LIMITS.body}
              rows={6}
              onChange={(event) => setBody(event.target.value)}
              placeholder="Ne olacağını, ne zaman olacağını ve üyenin ne yapması gerektiğini yaz."
            />
          </Field>

          <section className="grid gap-2">
            <p className="text-xs text-ink-faint">Daha önce gönderilenler</p>
            {historyFailure ? (
              <p className="text-sm text-warning">{historyFailure}</p>
            ) : history === null ? (
              <p className="text-sm text-ink-faint">Yükleniyor…</p>
            ) : history.length === 0 ? (
              <p className="text-sm text-ink-faint">Henüz hiç global duyuru gönderilmedi.</p>
            ) : (
              <ul className="grid max-h-44 gap-1.5 overflow-y-auto">
                {history.map((row) => (
                  <li key={row.id} className="rounded-lg border border-hairline bg-canvas px-3 py-2">
                    <p className="truncate text-sm text-ink">{row.title}</p>
                    <p className="mt-0.5 text-xs text-ink-faint">
                      {formatDateTime(row.createdAt)} · {row.authorName} · {row.recipientCount} üye · {row.readCount} okundu
                    </p>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </DialogBody>

        <DialogFooter>
          {confirming ? (
            <>
              <p className="mr-auto self-center text-sm text-ink-muted">
                Gönderildikten sonra geri alınamaz. Yine de gönderilsin mi?
              </p>
              <Button variant="outline" disabled={busy} onClick={() => setConfirming(false)}>
                Vazgeç
              </Button>
              <Button variant="danger" disabled={busy} onClick={() => void send()}>
                {busy ? 'Gönderiliyor…' : 'Evet, herkese gönder'}
              </Button>
            </>
          ) : (
            <Button variant="primary" disabled={!ready} onClick={() => setConfirming(true)}>
              Duyuruyu gönder
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
