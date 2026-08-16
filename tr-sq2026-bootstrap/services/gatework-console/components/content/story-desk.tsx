'use client';
import { useCallback, useState } from 'react';
import { CircleDashed, Eye, Heart, Radio } from 'lucide-react';
import { apiData, errorText } from '@/lib/api-client';
import type { OfficialStory, SystemAccount } from '@/lib/content-labels';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Field, Select, Textarea } from '@/components/ui/field';
import { EmptyState } from '@/components/ui/page';
import { PhonePreview } from '@/components/ui/phone-preview';
import { ReasonDialog } from '@/components/ui/reason-dialog';
import { ImageUpload, type UploadedImage } from './image-upload';

/**
 * Story paylaşımı.
 *
 * Ana sayfanın en üstündeki şerit, yeni bir üyenin ağı boş olduğu için ilk gün
 * bomboş açılıyordu. Sponsorlu yuvalar Tanıtımlar ekranından yerleştirilebiliyor
 * ama platformun kendi Story'si için hiçbir yol yoktu: uygulamadaki oluşturucu
 * resmî hesap adına değil, o an giriş yapmış kişinin adına yayınlıyor.
 *
 * Süre burada bir seçim değil bir sınır. Story 24 saatte kendiliğinden düşüyor;
 * ekran bunu gizlemek yerine kalan süreyi listede yazıyor, çünkü "dün eklediğim
 * Story nerede" sorusunun cevabı başka hiçbir yerde yok.
 */
const TTL_OPTIONS = [
  [24, '24 saat (tam gün)'],
  [12, '12 saat'],
  [6, '6 saat'],
  [3, '3 saat'],
] as const;

export function StoryDesk({
  initialStories,
  accounts,
  loadFailure,
  canPublish,
}: {
  initialStories: OfficialStory[];
  accounts: SystemAccount[];
  loadFailure: string | null;
  canPublish: boolean;
}) {
  const [stories, setStories] = useState(initialStories);
  const [error, setError] = useState<string | null>(loadFailure);
  const [notice, setNotice] = useState<string | null>(null);
  const [retracting, setRetracting] = useState<OfficialStory | null>(null);

  const active = accounts.filter((row) => row.active);
  const [authorId, setAuthorId] = useState(active[0]?.id ?? '');
  const [image, setImage] = useState<UploadedImage | null>(null);
  const [ttlHours, setTtlHours] = useState('24');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);

  const reload = useCallback(async () => {
    const rows = await apiData<OfficialStory[]>('/api/content/stories').catch(() => null);
    if (rows) setStories(rows);
  }, []);

  async function publish(event: React.FormEvent) {
    event.preventDefault();
    setError(null); setNotice(null);
    if (!authorId) { setError('Önce Story\'yi paylaşacak resmî hesabı seç.'); return; }
    if (!image) { setError('Story bir görselden ibarettir; önce görseli yükle ve taramanın bitmesini bekle.'); return; }
    if (reason.trim().length < 5) { setError('İşlem nedeni en az 5 karakter olmalı.'); return; }
    setBusy(true);
    try {
      await apiData<{ id: string }>('/api/content/stories', {
        method: 'POST',
        body: JSON.stringify({ authorId, mediaId: image.mediaId, ttlHours: Number(ttlHours), reason: reason.trim() }),
      });
      setImage(null); setReason('');
      setNotice('Story yayınlandı ve ana sayfadaki şeride düştü.');
      await reload();
    } catch (caught) {
      setError(errorText(caught, 'Story yayınlanamadı.'));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="grid gap-6">
      {error && <div className="rounded-card border border-warning/30 bg-warning-soft p-4 text-sm text-warning">{error}</div>}
      {notice && <div className="rounded-card border border-success/30 bg-success-soft p-4 text-sm text-success">{notice}</div>}

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_auto]">
        <Card>
          <CardHeader>
            <div>
              <CardTitle>Story paylaşımı</CardTitle>
              <CardDescription>
                Ana sayfanın en üstündeki şeride resmî hesap adına düşer ve süresi dolunca kendiliğinden kalkar. Herkese görünür: şerit resmî hesapları eyalet ve arkadaşlık ayırmadan gösterir.
              </CardDescription>
            </div>
            <Radio size={16} className="shrink-0 text-ink-faint" />
          </CardHeader>
          <CardContent>
            {!canPublish ? (
              <p className="text-sm text-ink-faint">Story paylaşmak Sahip, Operasyon Yöneticisi ve İçerik Editörü rollerine açıktır.</p>
            ) : (
              <form onSubmit={publish} className="grid gap-4">
                <Field label="Paylaşan hesap" hint={active.length === 0 ? 'Aktif resmî hesap yok; yukarıdan bir tane aç.' : undefined}>
                  <Select value={authorId} onChange={(event) => setAuthorId(event.target.value)} disabled={active.length === 0}>
                    <option value="">Hesap seç</option>
                    {active.map((row) => <option key={row.id} value={row.id}>{row.displayName ?? row.id}</option>)}
                  </Select>
                </Field>

                <Field label="Story görseli" hint="Dikey (9:16) görseller şeritte ve tam ekranda en iyi görünür.">
                  <ImageUpload ownerId={authorId} value={image} onChange={setImage} disabled={busy} />
                </Field>

                <Field label="Yayında kalma süresi" hint="Üst sınır 24 saat; Story'ler bu sürenin sonunda kendiliğinden düşer.">
                  <Select value={ttlHours} onChange={(event) => setTtlHours(event.target.value)}>
                    {TTL_OPTIONS.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                  </Select>
                </Field>

                <Field label="İşlem nedeni" hint="Denetim kaydına aynen yazılır.">
                  <Textarea required rows={2} minLength={5} maxLength={500} value={reason} onChange={(event) => setReason(event.target.value)} />
                </Field>

                <div>
                  <Button type="submit" variant="primary" disabled={busy || !authorId || !image}>
                    {busy ? 'Yayınlanıyor…' : 'Story\'yi yayınla'}
                  </Button>
                </div>
              </form>
            )}
          </CardContent>
        </Card>

        <PhonePreview label="Şeritteki görünümü">
          <StoryPreview
            imageUrl={image?.url ?? null}
            authorName={active.find((row) => row.id === authorId)?.displayName ?? 'Resmî hesap'}
          />
        </PhonePreview>
      </div>

      <Card>
        <CardHeader>
          <div>
            <CardTitle>Yayındaki Storyler</CardTitle>
            <CardDescription>Süresi dolanlar bu listeden kendiliğinden çıkar.</CardDescription>
          </div>
        </CardHeader>
        <CardContent>
          {stories.length === 0 ? (
            <EmptyState
              icon={CircleDashed}
              title="Şu anda yayında panel Story'si yok"
              description="Yukarıdan bir görsel yükleyip yayınladığında burada kalan süresiyle birlikte görünür."
            />
          ) : (
            <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              {stories.map((story) => (
                <li key={story.id} className="overflow-hidden rounded-lg border border-hairline bg-surface-raised">
                  <div className="relative h-40 bg-[#1a1828]">
                    {story.imageUrl ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={story.imageUrl} alt="" className="h-full w-full object-cover" />
                    ) : (
                      <p className="flex h-full items-center justify-center px-3 text-center text-[11px] text-ink-faint">
                        Görsel bağlantısı üretilemedi
                      </p>
                    )}
                    <div className="absolute top-2 left-2"><Badge tone="brand">{remainingLabel(story.expiresAt)}</Badge></div>
                  </div>
                  <div className="grid gap-2 p-3">
                    <p className="truncate text-sm font-medium text-ink">{story.authorName}</p>
                    <p className="flex items-center gap-3 text-xs text-ink-faint">
                      <span className="flex items-center gap-1"><Eye size={12} />{story.viewCount}</span>
                      <span className="flex items-center gap-1"><Heart size={12} />{story.likeCount}</span>
                    </p>
                    {canPublish && (
                      <Button size="sm" variant="danger" onClick={() => setRetracting(story)}>Geri çek</Button>
                    )}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <ReasonDialog
        open={retracting !== null}
        onOpenChange={(open) => { if (!open) setRetracting(null); }}
        title="Story geri çekilecek"
        description="Story şeritten kalkar. Görüntülenmeleri, beğenileri ve hakkında açılmış şikâyetler kayıtta kalır."
        confirmLabel="Geri çek"
        variant="danger"
        onConfirm={async (text) => {
          if (!retracting) return;
          await apiData(`/api/content/stories/${retracting.id}`, { method: 'DELETE', body: JSON.stringify({ reason: text }) });
          await reload();
          setNotice('Story geri çekildi.');
        }}
      />
    </div>
  );
}

/// Kalan süre, bitiş tarihi değil. "15.08.2026 09:12" bir editöre "bu Story
/// bugün akşam düşecek mi" sorusunu cevaplamıyor.
function remainingLabel(expiresAt: string) {
  const minutes = Math.round((new Date(expiresAt).getTime() - Date.now()) / 60000);
  if (minutes <= 0) return 'Süresi doldu';
  if (minutes < 60) return `${minutes} dk kaldı`;
  const hours = Math.floor(minutes / 60);
  return `${hours} sa ${minutes % 60} dk kaldı`;
}

function StoryPreview({ imageUrl, authorName }: { imageUrl: string | null; authorName: string }) {
  return (
    <div className="px-4">
      <div className="relative overflow-hidden rounded-2xl bg-[#131120]" style={{ aspectRatio: '9 / 16' }}>
        {imageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={imageUrl} alt="" className="h-full w-full object-cover" />
        ) : (
          <p className="flex h-full items-center justify-center px-6 text-center text-[11px] text-ink-faint">
            Görsel yükledikçe Story burada belirir.
          </p>
        )}
        <div className="absolute inset-x-3 top-3 h-0.5 rounded-full bg-white/70" />
        <div className="absolute inset-x-3 top-6 flex items-center gap-2">
          <div className="flex size-7 items-center justify-center rounded-full bg-brand-500 text-[11px] font-semibold text-white">
            {authorName.slice(0, 1).toUpperCase()}
          </div>
          <span className="truncate text-[11px] font-medium text-white drop-shadow">{authorName}</span>
          <span className="text-[10px] text-white/70">şimdi</span>
        </div>
      </div>
    </div>
  );
}
