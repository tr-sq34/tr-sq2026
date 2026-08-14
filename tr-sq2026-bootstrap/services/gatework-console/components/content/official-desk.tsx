'use client';
import { useState } from 'react';
import { BadgeCheck, Plus, Send } from 'lucide-react';
import { apiData, errorText, formatDate } from '@/lib/api-client';
import { VISIBILITY_LABELS, type SystemAccount } from '@/lib/content-labels';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogBody, DialogContent, DialogFooter } from '@/components/ui/dialog';
import { Field, Input, Select, Textarea } from '@/components/ui/field';
import { EmptyState } from '@/components/ui/page';
import { PhonePreview, previewParagraphs } from '@/components/ui/phone-preview';

/**
 * İçerik Stüdyosu: the official accounts, and the composer that publishes as
 * one of them.
 *
 * The screen this replaces asked the editor to paste a UUID into a text box
 * labelled "Resmî hesap ID". That id was returned once, when the account was
 * created, and nothing ever listed it again - so it lived in someone's notes,
 * and a wrong paste was caught by the publish endpoint rather than the form.
 * The picker is the fix; the list endpoint behind it is new.
 */
const BODY_LIMIT = 2200;

export function OfficialDesk({
  initialAccounts,
  loadFailure,
  canPublish,
}: {
  initialAccounts: SystemAccount[];
  loadFailure: string | null;
  canPublish: boolean;
}) {
  const [accounts, setAccounts] = useState(initialAccounts);
  const [accountId, setAccountId] = useState(initialAccounts.find((row) => row.active)?.id ?? '');
  const [body, setBody] = useState('');
  const [visibility, setVisibility] = useState('public');
  const [regionCode, setRegionCode] = useState('');
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(loadFailure);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [creating, setCreating] = useState(false);

  const active = accounts.filter((row) => row.active);
  const author = accounts.find((row) => row.id === accountId) ?? null;

  async function reloadAccounts() {
    const rows = await apiData<SystemAccount[]>('/api/content/system-accounts').catch(() => null);
    if (rows) setAccounts(rows);
  }

  async function publish(event: React.FormEvent) {
    event.preventDefault();
    setError(null); setNotice(null);
    if (!accountId) { setError('Önce yayınlanacak resmî hesabı seç.'); return; }
    if (reason.trim().length < 5) { setError('İşlem nedeni en az 5 karakter olmalı.'); return; }
    setBusy(true);
    try {
      const post = await apiData<{ id: string }>('/api/content/posts', {
        method: 'POST',
        body: JSON.stringify({
          authorId: accountId,
          body: body.trim(),
          visibility,
          regionCode: regionCode.trim() || undefined,
          reason: reason.trim(),
        }),
      });
      setBody(''); setReason('');
      setNotice(`Paylaşım yayınlandı (${post.id.slice(0, 8)}…). Akışta resmî hesap adına görünüyor.`);
      void reloadAccounts();
    } catch (caught) {
      setError(errorText(caught, 'Paylaşım yayınlanamadı.'));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="grid gap-6">
      {error && <div className="rounded-card border border-warning/30 bg-warning-soft p-4 text-sm text-warning">{error}</div>}
      {notice && <div className="rounded-card border border-success/30 bg-success-soft p-4 text-sm text-success">{notice}</div>}

      <Card>
        <CardHeader>
          <div>
            <CardTitle>Resmî hesaplar</CardTitle>
            <CardDescription>
              Bu hesaplar giriş yapamaz; yalnızca panel üzerinden yayın yapar. Haberler ve resmî paylaşımlar bir kişinin değil, bunlardan birinin adına çıkar.
            </CardDescription>
          </div>
          {canPublish && (
            <Button size="sm" onClick={() => setCreating(true)}><Plus size={15} />Yeni hesap</Button>
          )}
        </CardHeader>
        <CardContent>
          {accounts.length === 0 ? (
            <EmptyState
              icon={BadgeCheck}
              title="Henüz resmî hesap yok"
              description="Haber ve resmî paylaşım yayınlayabilmek için önce en az bir resmî hesap açılmalı."
            />
          ) : (
            <ul className="grid gap-2 sm:grid-cols-2">
              {accounts.map((row) => (
                <li key={row.id} className="rounded-lg border border-hairline bg-surface-raised p-3.5">
                  <div className="flex items-start justify-between gap-3">
                    <p className="min-w-0 truncate text-sm font-medium text-ink">{row.displayName ?? 'Adsız hesap'}</p>
                    {row.active ? <Badge tone="success" dot>Aktif</Badge> : <Badge tone="neutral">Kapalı</Badge>}
                  </div>
                  <p className="mt-1.5 text-xs text-ink-faint">
                    {row.newsCount} haber · {row.postCount} paylaşım · {formatDate(row.createdAt)}
                  </p>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_auto]">
        <Card>
          <CardHeader>
            <div>
              <CardTitle>Akış paylaşımı</CardTitle>
              <CardDescription>Uygulamanın ana akışına resmî hesap adına düşer. Sağdaki önizleme yazdıkça güncellenir.</CardDescription>
            </div>
            <Send size={16} className="shrink-0 text-ink-faint" />
          </CardHeader>
          <CardContent>
            {!canPublish ? (
              <p className="text-sm text-ink-faint">Yayın yapmak Sahip, Operasyon Yöneticisi ve İçerik Editörü rollerine açıktır.</p>
            ) : (
              <form onSubmit={publish} className="grid gap-4">
                <Field label="Yayınlayan hesap" hint={active.length === 0 ? 'Aktif resmî hesap yok; önce bir tane aç.' : undefined}>
                  <Select value={accountId} onChange={(event) => setAccountId(event.target.value)} disabled={active.length === 0}>
                    <option value="">Hesap seç</option>
                    {active.map((row) => <option key={row.id} value={row.id}>{row.displayName ?? row.id}</option>)}
                  </Select>
                </Field>

                <Field label="Metin" hint={`${body.length} / ${BODY_LIMIT} karakter · boş satır bırakarak paragraf ayır`}>
                  <Textarea rows={8} maxLength={BODY_LIMIT} value={body} onChange={(event) => setBody(event.target.value)} />
                </Field>

                <div className="grid gap-4 sm:grid-cols-2">
                  <Field label="Görünürlük">
                    <Select value={visibility} onChange={(event) => setVisibility(event.target.value)}>
                      {Object.entries(VISIBILITY_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                    </Select>
                  </Field>
                  <Field label="Eyalet kodu" hint="Boş bırakırsan ülke genelinde görünür.">
                    <Input maxLength={2} placeholder="NY" value={regionCode} onChange={(event) => setRegionCode(event.target.value.toUpperCase())} />
                  </Field>
                </div>

                <Field label="İşlem nedeni" hint="Denetim kaydına aynen yazılır.">
                  <Textarea rows={2} maxLength={500} value={reason} onChange={(event) => setReason(event.target.value)} />
                </Field>

                <div>
                  <Button type="submit" variant="primary" disabled={busy || !accountId || body.trim().length === 0}>
                    {busy ? 'Yayınlanıyor…' : 'Paylaşımı yayınla'}
                  </Button>
                </div>
              </form>
            )}
          </CardContent>
        </Card>

        <PhonePreview label="Akıştaki görünümü">
          <PostPreview authorName={author?.displayName ?? 'Resmî hesap'} body={body} regionCode={regionCode} />
        </PhonePreview>
      </div>

      <CreateAccountDialog
        open={creating}
        onOpenChange={setCreating}
        onCreated={async (created) => {
          await reloadAccounts();
          setAccountId(created.id);
          setNotice(`${created.displayName} resmî hesabı hazır ve yayınlayan hesap olarak seçildi.`);
        }}
      />
    </div>
  );
}

function PostPreview({ authorName, body, regionCode }: { authorName: string; body: string; regionCode: string }) {
  const paragraphs = previewParagraphs(body);
  return (
    <div className="px-4">
      <div className="rounded-2xl bg-[#131120] p-4">
        <div className="flex items-center gap-2.5">
          <div className="flex size-9 shrink-0 items-center justify-center rounded-full bg-brand-500 text-sm font-semibold text-white">
            {authorName.slice(0, 1).toUpperCase()}
          </div>
          <div className="min-w-0">
            <p className="flex items-center gap-1 truncate text-[13px] font-semibold text-white">
              {authorName}
              <BadgeCheck size={13} className="shrink-0 text-brand-400" />
            </p>
            <p className="text-[11px] text-ink-faint">{regionCode ? `${regionCode} · şimdi` : 'şimdi'}</p>
          </div>
        </div>
        {paragraphs.length === 0 ? (
          <p className="mt-3 text-[13px] text-ink-faint italic">Metin yazdıkça burada görünecek.</p>
        ) : (
          <div className="mt-3 grid gap-2.5">
            {paragraphs.map((paragraph, index) => (
              <p key={index} className="text-[13px] leading-relaxed break-words text-[#e8e6f0]">{paragraph}</p>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function CreateAccountDialog({
  open, onOpenChange, onCreated,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onCreated: (account: { id: string; displayName: string }) => Promise<void>;
}) {
  const [displayName, setDisplayName] = useState('');
  const [handle, setHandle] = useState('');
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  function change(next: boolean) {
    if (busy) return;
    if (!next) { setDisplayName(''); setHandle(''); setReason(''); setError(null); }
    onOpenChange(next);
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    // The handle rule is the service's, restated here so a rejection costs a
    // keystroke rather than a round trip and a generic 400.
    if (!/^[a-z0-9][a-z0-9_-]{2,39}$/.test(handle)) {
      setError('Kullanıcı adı küçük harf ve rakamla başlamalı, 3-40 karakter olmalı.');
      return;
    }
    if (reason.trim().length < 5) { setError('İşlem nedeni en az 5 karakter olmalı.'); return; }
    setBusy(true);
    try {
      const account = await apiData<{ id: string; displayName: string }>('/api/content/system-accounts', {
        method: 'POST',
        body: JSON.stringify({ displayName: displayName.trim(), handle, reason: reason.trim() }),
      });
      await onCreated(account);
      change(false);
    } catch (caught) {
      setError(errorText(caught, 'Resmî hesap oluşturulamadı.'));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={change}>
      <DialogContent title="Yeni resmî hesap" description="Bu hesap giriş yapamaz. Yalnızca panel üzerinden, gerekçesi kayda geçerek yayın yapar.">
        <form onSubmit={submit}>
          <DialogBody className="grid gap-4">
            <Field label="Görünen ad">
              <Input required minLength={2} maxLength={100} placeholder="TurkSquare" value={displayName} onChange={(event) => setDisplayName(event.target.value)} />
            </Field>
            <Field label="Kullanıcı adı" hint="Küçük harf, rakam, alt çizgi ve tire.">
              <Input required placeholder="turksquare" value={handle} onChange={(event) => setHandle(event.target.value.toLowerCase())} />
            </Field>
            <Field label="İşlem nedeni" error={error ?? undefined} hint="Denetim kaydına aynen yazılır.">
              <Textarea rows={2} maxLength={500} placeholder="Resmî topluluk duyuruları" value={reason} onChange={(event) => setReason(event.target.value)} />
            </Field>
          </DialogBody>
          <DialogFooter>
            <Button type="button" variant="ghost" disabled={busy} onClick={() => change(false)}>Vazgeç</Button>
            <Button type="submit" variant="primary" disabled={busy}>{busy ? 'Açılıyor…' : 'Hesabı aç'}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
