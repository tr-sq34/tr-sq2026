'use client';
import { useCallback, useMemo, useState } from 'react';
import { BadgeCheck, Clock, ImageOff, Newspaper } from 'lucide-react';
import { apiData, errorText, formatDateTime } from '@/lib/api-client';
import { NEWS_CATEGORIES, NEWS_CATEGORY_LABELS, type NewsSummary, type SystemAccount } from '@/lib/content-labels';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { DataTable, type ColumnDef } from '@/components/ui/data-table';
import { Field, Input, Select, Textarea } from '@/components/ui/field';
import { PhonePreview, previewParagraphs } from '@/components/ui/phone-preview';
import { ReasonDialog } from '@/components/ui/reason-dialog';
import { Switch } from '@/components/ui/switch';
import { ImageUpload, type UploadedImage } from './image-upload';

/**
 * Haber Merkezi: write on the left, see the article on the right, and below it
 * everything that is already out.
 *
 * Two things the old form could not do. It could not show what it was about to
 * produce - the app breaks a body into paragraphs on blank lines, so an editor
 * who pressed Enter once shipped a wall of text and only found out by opening
 * the app. And it could not show what had already been published, so a piece
 * with the wrong headline rank or a date set in the future was invisible until
 * a reader complained.
 *
 * There is no bold/italic toolbar on purpose. `news_article_screen.dart`
 * renders each paragraph as plain text; a rich text editor here would ship
 * literal asterisks or tags into the app. What the editor needs is the
 * paragraph rule made visible, which is what the preview does.
 */
const BODY_LIMIT = 20000;

export function NewsDesk({
  initialArticles,
  accounts,
  loadFailure,
  canPublish,
}: {
  initialArticles: NewsSummary[];
  accounts: SystemAccount[];
  loadFailure: string | null;
  canPublish: boolean;
}) {
  const [articles, setArticles] = useState(initialArticles);
  const [error, setError] = useState<string | null>(loadFailure);
  const [notice, setNotice] = useState<string | null>(null);
  const [retracting, setRetracting] = useState<NewsSummary | null>(null);

  const active = accounts.filter((row) => row.active);
  const [authorId, setAuthorId] = useState(active[0]?.id ?? '');
  const [title, setTitle] = useState('');
  const [summary, setSummary] = useState('');
  const [body, setBody] = useState('');
  const [category, setCategory] = useState('gundem');
  // Manşet sırası artık boş başlamıyor. Boş bırakıldığında haber ana sayfadaki
  // şeride hiç girmiyordu; editör alanı görmeden yayınlıyor, sonra "haberi
  // ekledim ama ana sayfada yok" diye geri geliyordu. Varsayılan 1: yeni haber
  // şeridin başına geçer, istemeyen alanı boşaltır.
  const [headlineRank, setHeadlineRank] = useState('1');
  const [hero, setHero] = useState<UploadedImage | null>(null);
  const [regionCode, setRegionCode] = useState('');
  const [commentsEnabled, setCommentsEnabled] = useState(true);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);

  const reload = useCallback(async () => {
    const rows = await apiData<NewsSummary[]>('/api/content/news').catch(() => null);
    if (rows) setArticles(rows);
  }, []);

  async function publish(event: React.FormEvent) {
    event.preventDefault();
    setError(null); setNotice(null);
    if (!authorId) { setError('Önce yayınlayacak resmî hesabı seç.'); return; }
    if (reason.trim().length < 5) { setError('İşlem nedeni en az 5 karakter olmalı.'); return; }
    setBusy(true);
    try {
      await apiData<{ id: string }>('/api/content/news', {
        method: 'POST',
        body: JSON.stringify({
          authorId,
          title: title.trim(),
          summary: summary.trim(),
          body: body.trim(),
          category,
          heroMediaId: hero?.mediaId,
          regionCode: regionCode.trim() || undefined,
          // Empty means "not on the home screen". The strip is short on
          // purpose, so a rank is a decision rather than a default.
          headlineRank: headlineRank ? Number(headlineRank) : undefined,
          commentsEnabled,
          reason: reason.trim(),
        }),
      });
      setTitle(''); setSummary(''); setBody(''); setHeadlineRank('1'); setHero(null); setReason('');
      setNotice('Haber yayınlandı ve aşağıdaki listeye düştü.');
      await reload();
    } catch (caught) {
      setError(errorText(caught, 'Haber yayınlanamadı.'));
    } finally {
      setBusy(false);
    }
  }

  const columns = useMemo<ColumnDef<NewsSummary, unknown>[]>(
    () => [
      {
        id: 'title',
        header: 'Haber',
        accessorFn: (row) => `${row.title} ${row.summary} ${row.authorName}`,
        cell: ({ row }) => (
          <div className="max-w-md min-w-0">
            <p className="truncate font-medium text-ink">{row.original.title}</p>
            <p className="truncate text-xs text-ink-faint">{row.original.authorName} · {row.original.summary}</p>
          </div>
        ),
      },
      {
        id: 'category',
        header: 'Kategori',
        accessorFn: (row) => row.category,
        cell: ({ row }) => <Badge>{NEWS_CATEGORY_LABELS[row.original.category] ?? row.original.category}</Badge>,
      },
      {
        id: 'headline',
        header: 'Manşet',
        accessorFn: (row) => row.headlineRank ?? 99,
        cell: ({ row }) =>
          row.original.headlineRank
            ? <Badge tone="brand">#{row.original.headlineRank}</Badge>
            : <span className="text-xs text-ink-faint">—</span>,
      },
      {
        id: 'state',
        header: 'Durum',
        accessorFn: (row) => (row.live ? 1 : 0),
        cell: ({ row }) =>
          row.original.live
            ? <Badge tone="success" dot>Yayında</Badge>
            // The public list hides these entirely, so this row is the only
            // place a piece dated for the future can be spotted.
            : <Badge tone="warning" dot>İleri tarihli</Badge>,
      },
      {
        id: 'engagement',
        header: 'Etkileşim',
        accessorFn: (row) => row.commentCount + row.reactionCount,
        cell: ({ row }) => (
          <span className="text-xs whitespace-nowrap">
            {row.original.reactionCount} tepki · {row.original.commentCount} yorum
          </span>
        ),
      },
      {
        id: 'publishedAt',
        header: 'Tarih',
        accessorFn: (row) => row.publishedAt,
        cell: ({ row }) => <span className="text-xs whitespace-nowrap">{formatDateTime(row.original.publishedAt)}</span>,
      },
      {
        id: 'actions',
        header: '',
        enableSorting: false,
        cell: ({ row }) =>
          canPublish ? (
            <Button size="sm" variant="danger" onClick={() => setRetracting(row.original)}>Geri çek</Button>
          ) : null,
      },
    ],
    [canPublish],
  );

  return (
    <div className="grid gap-6">
      {error && <div className="rounded-card border border-warning/30 bg-warning-soft p-4 text-sm text-warning">{error}</div>}
      {notice && <div className="rounded-card border border-success/30 bg-success-soft p-4 text-sm text-success">{notice}</div>}

      {canPublish && (
        <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_auto]">
          <Card>
            <CardHeader>
              <div>
                <CardTitle>Haber yaz</CardTitle>
                <CardDescription>
                  Yayınlanan haber uygulamadaki Haber Merkezi listesine düşer. Manşet sırası verirsen ana sayfadaki şeride de girer.
                </CardDescription>
              </div>
              <Newspaper size={16} className="shrink-0 text-ink-faint" />
            </CardHeader>
            <CardContent>
              <form onSubmit={publish} className="grid gap-4">
                <Field label="Yayınlayan hesap" hint={active.length === 0 ? 'Aktif resmî hesap yok; İçerik Stüdyosu\'ndan bir tane aç.' : undefined}>
                  <Select value={authorId} onChange={(event) => setAuthorId(event.target.value)} disabled={active.length === 0}>
                    <option value="">Hesap seç</option>
                    {active.map((row) => <option key={row.id} value={row.id}>{row.displayName ?? row.id}</option>)}
                  </Select>
                </Field>

                <Field label="Başlık" hint={`${title.length} / 200 karakter`}>
                  <Input required minLength={3} maxLength={200} value={title} onChange={(event) => setTitle(event.target.value)} />
                </Field>

                <Field label="Özet" hint="Listede ve ana sayfada görünen tek paragraf.">
                  <Textarea required rows={2} minLength={3} maxLength={500} value={summary} onChange={(event) => setSummary(event.target.value)} />
                </Field>

                <Field
                  label="Haber metni"
                  hint={`${body.length} / ${BODY_LIMIT} karakter · paragraf ayırmak için bir boş satır bırak — uygulama metni böyle bölüyor`}
                >
                  <Textarea required rows={14} maxLength={BODY_LIMIT} value={body} onChange={(event) => setBody(event.target.value)} />
                </Field>

                <Field
                  label="Kapak görseli"
                  hint="Listede ve haberin başında görünür. Yükledikten sonra güvenlik taraması bitene kadar yayınlama düğmesi beklemede kalır."
                >
                  <ImageUpload ownerId={authorId} value={hero} onChange={setHero} disabled={busy} />
                </Field>

                <div className="grid gap-4 sm:grid-cols-2">
                  <Field label="Kategori">
                    <Select value={category} onChange={(event) => setCategory(event.target.value)}>
                      {NEWS_CATEGORIES.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                    </Select>
                  </Field>
                  <Field label="Manşet sırası" hint="1 en üstte. Boşaltırsan haber yalnızca Haber Merkezi listesinde kalır, ana sayfa şeridine girmez.">
                    <Input type="number" min={1} max={20} placeholder="1" value={headlineRank} onChange={(event) => setHeadlineRank(event.target.value)} />
                  </Field>
                  <Field label="Eyalet kodu" hint="Boş bırakırsan ülke geneli.">
                    <Input maxLength={2} placeholder="NJ" value={regionCode} onChange={(event) => setRegionCode(event.target.value.toUpperCase())} />
                  </Field>
                </div>

                <div className="rounded-lg border border-hairline bg-surface-raised px-4">
                  <Switch
                    label="Yorumlara açık"
                    hint="Kapatırsan haber okunur ama altına yorum yazılamaz."
                    checked={commentsEnabled}
                    onCheckedChange={setCommentsEnabled}
                  />
                </div>

                <Field label="İşlem nedeni" hint="Denetim kaydına aynen yazılır.">
                  <Textarea required rows={2} minLength={5} maxLength={500} value={reason} onChange={(event) => setReason(event.target.value)} />
                </Field>

                <div>
                  <Button type="submit" variant="primary" disabled={busy || !authorId}>
                    {busy ? 'Yayınlanıyor…' : 'Haberi yayınla'}
                  </Button>
                </div>
              </form>
            </CardContent>
          </Card>

          <PhonePreview label="Uygulamadaki görünümü">
            <ArticlePreview
              title={title}
              summary={summary}
              body={body}
              category={category}
              authorName={active.find((row) => row.id === authorId)?.displayName ?? 'Resmî hesap'}
              heroUrl={hero?.url ?? null}
            />
          </PhonePreview>
        </div>
      )}

      <div>
        <h2 className="mb-3 text-sm font-semibold text-ink">Yayındaki haberler</h2>
        <DataTable
          columns={columns}
          rows={articles}
          rowKey={(row) => row.id}
          searchPlaceholder="Başlık, özet veya hesap ara"
          emptyLabel="Henüz haber yayınlanmamış."
          isRowUrgent={(row) => !row.live}
        />
      </div>

      <ReasonDialog
        open={retracting !== null}
        onOpenChange={(open) => { if (!open) setRetracting(null); }}
        title="Haber geri çekilecek"
        description={`"${retracting?.title ?? ''}" okuyuculara kapanır. Yorumlar ve hakkında açılmış şikâyetler kayıtta kalır.`}
        confirmLabel="Geri çek"
        variant="danger"
        onConfirm={async (text) => {
          if (!retracting) return;
          await apiData(`/api/content/news/${retracting.id}`, { method: 'DELETE', body: JSON.stringify({ reason: text }) });
          await reload();
          setNotice('Haber geri çekildi.');
        }}
      />
    </div>
  );
}

function ArticlePreview({
  title, summary, body, category, authorName, heroUrl,
}: {
  title: string;
  summary: string;
  body: string;
  category: string;
  authorName: string;
  heroUrl: string | null;
}) {
  const paragraphs = previewParagraphs(body);
  return (
    <div className="px-4">
      <div className="flex h-36 items-center justify-center overflow-hidden rounded-2xl bg-[#1a1828]">
        {heroUrl ? (
          // Taranmış görselin kendisi: panel artık uygulamanın göstereceği
          // dosyayı gösteriyor, "buraya bir görsel gelecek" yazısını değil.
          // eslint-disable-next-line @next/next/no-img-element
          <img src={heroUrl} alt="" className="h-full w-full object-cover" />
        ) : (
          <div className="text-center">
            <ImageOff size={20} className="mx-auto text-ink-faint" />
            <p className="mt-1.5 text-[11px] text-ink-faint">Görsel yok</p>
          </div>
        )}
      </div>

      <span className="mt-3 inline-block rounded-full bg-brand-500/20 px-2.5 py-1 text-[10px] font-medium text-brand-300">
        {NEWS_CATEGORY_LABELS[category] ?? category}
      </span>

      <h3 className="mt-2 text-[17px] leading-snug font-semibold break-words text-white">
        {title.trim() || 'Başlık buraya gelecek'}
      </h3>

      <div className="mt-2 flex items-center gap-1.5 text-[11px] text-ink-faint">
        <BadgeCheck size={12} className="text-brand-400" />
        <span className="truncate">{authorName}</span>
        <Clock size={11} />
        <span>şimdi</span>
      </div>

      {summary.trim() && (
        <p className="mt-3 text-[13px] leading-relaxed break-words text-[#a5a1b5] italic">{summary.trim()}</p>
      )}

      <div className="mt-3 grid gap-3 pb-4">
        {paragraphs.length === 0 ? (
          <p className="text-[13px] text-ink-faint italic">Metin yazdıkça paragraflar burada belirir.</p>
        ) : (
          paragraphs.map((paragraph, index) => (
            <p key={index} className="text-[13px] leading-relaxed break-words text-[#e8e6f0]">{paragraph}</p>
          ))
        )}
      </div>
    </div>
  );
}
