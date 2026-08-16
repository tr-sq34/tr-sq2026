'use client';
import { useCallback, useMemo, useState } from 'react';
import { CheckCircle2, History, RefreshCw, Send, Save, TriangleAlert } from 'lucide-react';
import { api, errorText, formatDateTime } from '@/lib/api-client';
import { LEGAL_KIND_LABELS, type LegalDocument } from '@/lib/legal-labels';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogBody, DialogContent, DialogFooter } from '@/components/ui/dialog';
import { Field, Input, Textarea } from '@/components/ui/field';
import { NotConnected } from '@/components/ui/page';
import { PhonePreview, previewParagraphs } from '@/components/ui/phone-preview';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';

/**
 * Kullanım Koşulları ve Gizlilik Politikası masası.
 *
 * Ekranın en önemli tek göstergesi "yayımlandı mı" sorusu. Yayımlanmamış bir
 * metin panelde kusursuz görünebilir ve uygulamada hiç yoktur; üye giriş
 * ekranında bağlantıya dokunur ve boş bir sayfa bulur. O yüzden yayımlanmamış
 * her metnin üstünde bunu söyleyen bir uyarı duruyor, ve uyarı taslak dolu diye
 * kaybolmuyor.
 *
 * Yayımlanmış sürüm burada da düzenlenemiyor — düzenleme her zaman taslağa
 * gidiyor. "Mart'ta kabul ettiğim metin" cümlesinin bir karşılığı olması buna
 * bağlı.
 */
type Props = { initial: LegalDocument[] | null; initialFailure: string | null; canDraft: boolean; canPublish: boolean };

export function LegalDesk({ initial, initialFailure, canDraft, canPublish }: Props) {
  const [documents, setDocuments] = useState(initial);
  const [failure, setFailure] = useState(initialFailure);

  const reload = useCallback(async () => {
    try {
      const body = await api<{ documents: LegalDocument[] | null }>('/api/legal');
      setDocuments(body.data.documents);
      setFailure((body.meta?.failure as string | null) ?? null);
    } catch (error) {
      setFailure(errorText(error, 'Yasal metinler alınamadı.'));
    }
  }, []);

  if (!documents) {
    return (
      <NotConnected
        what="Yasal metinler okunamadı."
        why={failure ?? 'Topluluk servisi yanıt vermedi. Metin yazılmamış olduğu anlamına gelmez — liste hiç gelmedi.'}
      />
    );
  }

  return (
    <Tabs defaultValue="terms" className="space-y-5">
      <TabsList>
        {documents.map((document) => (
          <TabsTrigger key={document.kind} value={document.kind}>
            {LEGAL_KIND_LABELS[document.kind]}
            {!document.published && <span className="ml-2 text-danger">•</span>}
          </TabsTrigger>
        ))}
      </TabsList>
      {documents.map((document) => (
        <TabsContent key={document.kind} value={document.kind}>
          <LegalEditor document={document} canDraft={canDraft} canPublish={canPublish} onChanged={reload} />
        </TabsContent>
      ))}
    </Tabs>
  );
}

function LegalEditor({
  document,
  canDraft,
  canPublish,
  onChanged,
}: {
  document: LegalDocument;
  canDraft: boolean;
  canPublish: boolean;
  onChanged: () => Promise<void>;
}) {
  // Taslak yoksa yayımlanmış metinden başlanıyor: sıfırdan yazmak, tek bir
  // cümleyi düzeltmek isteyen operatörün metnin tamamını yeniden yazması demek.
  const source = document.draft ?? document.published;
  const [title, setTitle] = useState(source?.title ?? LEGAL_KIND_LABELS[document.kind]);
  const [body, setBody] = useState(source?.body ?? '');
  const [changeNote, setChangeNote] = useState(document.draft?.changeNote ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);

  const dirty = title !== (source?.title ?? '') || body !== (source?.body ?? '') || changeNote !== (document.draft?.changeNote ?? '');
  const paragraphs = useMemo(() => previewParagraphs(body), [body]);

  async function save() {
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      await api(`/api/legal/${document.kind}/draft`, {
        method: 'PUT',
        body: JSON.stringify({ title, body, changeNote: changeNote.trim() || undefined }),
      });
      setNotice('Taslak kaydedildi. Uygulamada hâlâ görünmüyor — görünmesi için yayımlanması gerekiyor.');
      await onChanged();
    } catch (caught) {
      setError(errorText(caught, 'Taslak kaydedilemedi.'));
    } finally {
      setBusy(false);
    }
  }

  async function publish() {
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      const result = await api<{ version: number }>(`/api/legal/${document.kind}/publish`, { method: 'POST' });
      setConfirming(false);
      setNotice(`v${result.data.version} yayımlandı. Uygulamadaki bağlantı artık bu metni gösteriyor.`);
      await onChanged();
    } catch (caught) {
      setError(errorText(caught, 'Metin yayımlanamadı.'));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-4">
      {/* Ekranın en önemli satırı. Yayımlanmamış metin, üyenin giriş ekranında
          dokunduğu bağlantının boş çıkması demek. */}
      {document.published ? (
        <Card tone="raised">
          <CardHeader className="flex-row items-center gap-3">
            <CheckCircle2 className="size-5 text-success" />
            <div>
              <CardTitle className="text-sm">
                Uygulamada v{document.published.version} yayında
              </CardTitle>
              <CardDescription>
                {formatDateTime(document.published.publishedAt)} tarihinde yayımlandı.
                {document.draft ? ' Aşağıdaki taslak henüz üyeye gitmiyor.' : ''}
              </CardDescription>
            </div>
          </CardHeader>
        </Card>
      ) : (
        <Card tone="urgent">
          <CardHeader className="flex-row items-center gap-3">
            <TriangleAlert className="size-5 text-danger" />
            <div>
              <CardTitle className="text-sm">Bu metin uygulamada görünmüyor.</CardTitle>
              <CardDescription>
                Giriş ekranının altındaki bağlantı bu metni açıyor ve şu an “henüz yayımlanmadı” diyor. Aşağıdaki taslak
                ne kadar dolu olursa olsun, yayımlanana kadar üyeye gitmez. Yayımlamadan önce hukuki inceleme gerekiyor.
              </CardDescription>
            </div>
          </CardHeader>
        </Card>
      )}

      <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_auto]">
        <Card>
          <CardHeader>
            <CardTitle>
              Taslak
              {document.draft && (
                <Badge tone="neutral" className="ml-2">
                  v{document.draft.version} olarak yayımlanacak
                </Badge>
              )}
            </CardTitle>
            <CardDescription>
              Boş satır bırakılan yerler uygulamada ayrı paragraf oluyor. Satır başına yazılan “## ” bir ara başlık
              yapıyor — sağdaki önizleme ikisini de gösteriyor.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <Field label="Başlık">
              <Input value={title} onChange={(event) => setTitle(event.target.value)} disabled={!canDraft || busy} maxLength={160} />
            </Field>
            <Field label="Metin">
              <Textarea
                value={body}
                onChange={(event) => setBody(event.target.value)}
                disabled={!canDraft || busy}
                rows={24}
                className="font-mono text-xs leading-relaxed"
              />
            </Field>
            <Field label="Ne değişti?" hint="Üyeye de gösterilebilir. “Metin güncellendi” demek, hiçbir şey dememekle aynı şey.">
              <Input
                value={changeNote}
                onChange={(event) => setChangeNote(event.target.value)}
                disabled={!canDraft || busy}
                maxLength={500}
                placeholder="Örn. Yardım Çağrısı'nın acil servis olmadığı açıkça yazıldı."
              />
            </Field>

            {error && <p className="text-sm text-danger">{error}</p>}
            {notice && <p className="text-sm text-success">{notice}</p>}

            <div className="flex flex-wrap items-center gap-2">
              <Button onClick={save} disabled={!canDraft || busy || !dirty}>
                <Save className="size-4" />
                Taslağı kaydet
              </Button>
              <Button
                variant="secondary"
                onClick={() => setConfirming(true)}
                disabled={!canPublish || busy || !document.draft || dirty}
              >
                <Send className="size-4" />
                Yayımla
              </Button>
              <Button variant="ghost" onClick={() => void onChanged()} disabled={busy}>
                <RefreshCw className="size-4" />
                Yenile
              </Button>
              {!canDraft && <span className="text-xs text-ink-faint">Yazma yetkin yok; metni yalnızca okuyabilirsin.</span>}
              {canDraft && !canPublish && (
                <span className="text-xs text-ink-faint">Yayımlama yetkisi sahibi ve güvenlik yöneticisinde.</span>
              )}
              {dirty && document.draft && (
                <span className="text-xs text-ink-faint">Yayımlamadan önce kaydedilmemiş değişiklikleri kaydet.</span>
              )}
            </div>
          </CardContent>
        </Card>

        <PhonePreview label="Üyenin göreceği">
          <div className="px-5 text-[13px] leading-relaxed text-white/85">
            <h1 className="mb-4 text-lg font-semibold text-white">{title}</h1>
            {paragraphs.length === 0 ? (
              <p className="text-white/40">Metin boş.</p>
            ) : (
              paragraphs.map((paragraph, index) =>
                paragraph.startsWith('## ') ? (
                  <h2 key={index} className="mt-5 mb-2 text-sm font-semibold text-white">
                    {paragraph.slice(3)}
                  </h2>
                ) : (
                  <p key={index} className="mb-3 whitespace-pre-line">
                    {paragraph}
                  </p>
                ),
              )
            )}
          </div>
        </PhonePreview>
      </div>

      {document.history.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-sm">
              <History className="size-4" />
              Yayımlanmış sürümler
            </CardTitle>
            <CardDescription>
              Yayımlanan sürüm bir daha değiştirilmiyor. “O tarihte hangi metni kabul ettim” sorusunun cevabı bu listede.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            {document.history.map((entry) => (
              <div key={entry.version} className="flex flex-wrap items-baseline gap-x-3 gap-y-1 border-b border-hairline pb-2 last:border-0">
                <Badge tone="neutral">v{entry.version}</Badge>
                <span className="text-sm">{formatDateTime(entry.publishedAt)}</span>
                <span className="text-xs text-ink-faint">{entry.changeNote ?? 'Değişiklik notu yazılmamış.'}</span>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      <Dialog open={confirming} onOpenChange={(open) => !busy && setConfirming(open)}>
        <DialogContent
          title={`${LEGAL_KIND_LABELS[document.kind]} v${document.draft?.version} yayımlansın mı?`}
          description="Yayımlandığı anda uygulamadaki bağlantı bu metni gösterir ve bu sürüm bir daha değiştirilemez. Sonraki düzenleme yeni bir taslak açar."
        >
          <DialogBody className="space-y-3">
            {document.published && (
              <p className="text-sm text-ink-faint">
                Şu an yayında olan v{document.published.version} arşive geçer; silinmez.
              </p>
            )}
            {error && <p className="text-sm text-danger">{error}</p>}
          </DialogBody>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setConfirming(false)} disabled={busy}>
              Vazgeç
            </Button>
            <Button onClick={publish} disabled={busy}>
              Yayımla
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
