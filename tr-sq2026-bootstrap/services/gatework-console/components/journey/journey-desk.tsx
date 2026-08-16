'use client';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Award, RefreshCw, Search, TriangleAlert, Users } from 'lucide-react';
import { api, apiData, errorText, formatDateTime } from '@/lib/api-client';
import {
  CATEGORY_LABELS,
  TIER_LABELS,
  TIER_TONE,
  badgeHealth,
  count,
  grantedAgo,
  type BadgeHolder,
  type JourneyBadge,
  type JourneyOverview,
} from '@/lib/journey-labels';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogBody, DialogContent, DialogFooter } from '@/components/ui/dialog';
import { Field, Input, Select, Textarea } from '@/components/ui/field';
import { EmptyState, NotConnected } from '@/components/ui/page';
import { StatCard } from '@/components/ui/stat-card';
import { cn } from '@/lib/cn';

/**
 * Rozetler ve Yolculuk.
 *
 * Bu ekranın asıl işi bir sayı göstermek değil, bir farkı görünür kılmak:
 * katalogda elli rozet var, kuralı olan on iki tane. Kalanının kriteri
 * uygulamada üyeye yazılı olarak gösteriliyor ve onu verecek hiçbir kod yok.
 * Sadece "kaç kişi aldı" sütunu gösterseydik, o rozetlerin hepsi "0" yazardı ve
 * bu "kimse hak etmemiş" diye okunurdu — ekranın verebileceği en yanlış cevap.
 *
 * Sıralama da bu yüzden: sorunlu rozetler üstte. Bir operatörün elli satırı
 * gözüyle tarayıp aradaki on beş kırık rozeti bulması beklenemez.
 */
type Props = { initial: JourneyOverview | null; initialFailure: string | null; canGrant: boolean };

type MemberHit = { id: string; displayName: string; email: string };

export function JourneyDesk({ initial, initialFailure, canGrant }: Props) {
  const [overview, setOverview] = useState(initial);
  const [failure, setFailure] = useState(initialFailure);
  const [category, setCategory] = useState('');
  const [onlyBroken, setOnlyBroken] = useState(false);
  const [busy, setBusy] = useState(false);
  const [granting, setGranting] = useState<JourneyBadge | null>(null);
  const [inspecting, setInspecting] = useState<JourneyBadge | null>(null);

  const reload = useCallback(async () => {
    setBusy(true);
    try {
      const body = await api<{ overview: JourneyOverview | null }>('/api/journey');
      setOverview(body.data.overview);
      setFailure((body.meta?.failure as string | null) ?? null);
    } catch (error) {
      setFailure(errorText(error, 'Rozet kataloğu alınamadı.'));
    } finally {
      setBusy(false);
    }
  }, []);

  const badges = overview?.badges ?? [];

  // Kuralı olmayan, elle de verilmesi tasarlanmamış rozetler. Bu sayı bu
  // ekranın var oluş sebebi.
  const broken = useMemo(() => badges.filter((badge) => !badge.automated && !badge.manualOnly), [badges]);
  const silent = useMemo(() => badges.filter((badge) => badge.automated && badge.holders === 0), [badges]);

  const visible = useMemo(() => {
    const rows = badges.filter((badge) => {
      if (category && badge.category !== category) return false;
      if (onlyBroken && badgeHealth(badge).tone === 'success') return false;
      return true;
    });
    // Bozuk olan en üstte, sonra hiç verilmeyen, sonra dağıtılanlar.
    const weight = (badge: JourneyBadge) => ({ danger: 0, warning: 1, neutral: 2, success: 3 })[badgeHealth(badge).tone];
    return [...rows].sort((a, b) => weight(a) - weight(b) || b.holders - a.holders);
  }, [badges, category, onlyBroken]);

  if (!overview) {
    return (
      <NotConnected
        what="Rozet kataloğu okunamadı."
        why={failure ?? 'Topluluk servisi yanıt vermedi. Katalogda rozet olmadığı anlamına gelmez — liste hiç gelmedi.'}
      />
    );
  }

  return (
    <div className="space-y-5">
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="Puanı olan üye" value={count(overview.members)} icon={Users} detail="En az bir kez etkileşim yapmış" />
        <StatCard label="Dağıtılan rozet" value={count(overview.granted)} icon={Award} tone="brand" />
        <StatCard label="Elle verilen" value={count(overview.manualGrants)} detail="Panelden, gerekçesiyle" />
        <StatCard
          label="Kuralı olmayan rozet"
          value={`${count(broken.length)} / ${count(badges.length)}`}
          icon={TriangleAlert}
          tone={broken.length > 0 ? 'danger' : 'success'}
          detail={broken.length > 0 ? 'Kimse kazanamaz' : 'Katalogdaki her rozetin bir yolu var'}
        />
      </div>

      {broken.length > 0 && (
        <Card tone="urgent">
          <CardHeader>
            <div>
              <CardTitle>{broken.length} rozet katalogda duruyor ama kazanılamıyor</CardTitle>
              <CardDescription>
                Üye Yolculuk ekranında bu rozetlerin kriterini okuyor — “milli maç günü izleme etkinliği paylaştın”,
                “vize sorularına verdiğin yanıt En Faydalı seçildi” — ve o kriteri sağlayacak bir kural yok. İki
                dürüst çıkış var: rozete bir kural yazmak, ya da elle verilen bir rozet olarak işaretleyip buradan
                gerekçesiyle vermek.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="flex flex-wrap gap-1.5 pt-4">
            {broken.slice(0, 12).map((badge) => (
              <Badge key={badge.code} tone="danger">{badge.title}</Badge>
            ))}
            {broken.length > 12 && <Badge tone="danger">+{broken.length - 12} tane daha</Badge>}
          </CardContent>
        </Card>
      )}

      {silent.length > 0 && (
        <Card>
          <CardHeader>
            <div>
              <CardTitle>{silent.length} rozetin kuralı var ama hiç verilmemiş</CardTitle>
              <CardDescription>
                Bu bir hata olmak zorunda değil: kimse henüz o şeyi yapmamış olabilir. Ama aylardır sıfırda duran bir
                rozet, tetiklenmeyen bir kuralın da tek görünür belirtisi.
              </CardDescription>
            </div>
          </CardHeader>
        </Card>
      )}

      <Card>
        <CardHeader className="flex-wrap items-center pb-5">
          <div className="flex flex-wrap items-center gap-2">
            <Select value={category} onChange={(event) => setCategory(event.target.value)} className="h-9 w-auto text-xs">
              <option value="">Bütün kategoriler</option>
              {Object.entries(CATEGORY_LABELS).map(([value, label]) => (
                <option key={value} value={value}>{label}</option>
              ))}
            </Select>
            <Button size="sm" variant={onlyBroken ? 'primary' : 'outline'} onClick={() => setOnlyBroken((value) => !value)}>
              Sadece sorunlular
            </Button>
          </div>
          <Button size="sm" variant="ghost" onClick={() => void reload()} disabled={busy}>
            <RefreshCw size={14} className={cn(busy && 'animate-spin')} /> Yenile
          </Button>
        </CardHeader>
        <CardContent className="pt-4">
          {failure && <p className="mb-3 text-xs text-warning">Son yenileme başarısız: {failure}</p>}
          {visible.length === 0 ? (
            <EmptyState title="Bu filtrede rozet yok." description="Filtreyi genişletmeyi dene." />
          ) : (
            <ul className="divide-y divide-hairline">
              {visible.map((badge) => {
                const health = badgeHealth(badge);
                return (
                  <li key={badge.code} className="flex flex-wrap items-start gap-3 py-3.5">
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-sm font-medium text-ink">{badge.title}</span>
                        <Badge tone={TIER_TONE[badge.tier] ?? 'neutral'}>{TIER_LABELS[badge.tier] ?? badge.tier}</Badge>
                        <Badge>{CATEGORY_LABELS[badge.category] ?? badge.category}</Badge>
                        <Badge tone={health.tone}>{health.label}</Badge>
                        {badge.isSecret && <Badge>Gizli</Badge>}
                      </div>
                      <p className="mt-1 text-xs text-ink-muted">{badge.description}</p>
                      {health.note && <p className="mt-1 text-xs text-ink-faint">{health.note}</p>}
                    </div>
                    <div className="flex shrink-0 items-center gap-4 text-right">
                      <div>
                        <p className="text-sm font-semibold text-ink">{count(badge.holders)}</p>
                        <p className="text-[11px] text-ink-faint">üye</p>
                      </div>
                      <div>
                        <p className="text-sm text-ink-muted">{count(badge.inProgress)}</p>
                        <p className="text-[11px] text-ink-faint">sayaçta</p>
                      </div>
                      <div className="w-24">
                        <p className="text-xs text-ink-muted">{grantedAgo(badge.lastGrantedAt)}</p>
                        <p className="text-[11px] text-ink-faint">son veriliş</p>
                      </div>
                      <div className="flex gap-1.5">
                        <Button size="sm" variant="outline" onClick={() => setInspecting(badge)}>
                          Taşıyanlar
                        </Button>
                        {canGrant && !badge.automated && (
                          <Button size="sm" variant="primary" onClick={() => setGranting(badge)}>
                            Ver
                          </Button>
                        )}
                      </div>
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <div>
            <CardTitle>Seviye dağılımı</CardTitle>
            <CardDescription>
              Yalnızca üyesi olan basamaklar. Elli satırlık boş bir merdiven, kimsenin nerede olduğunu göstermek yerine
              gizler.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent className="pt-4">
          {overview.levels.length === 0 ? (
            <EmptyState title="Henüz kimsenin puanı yok." description="Puan ilk etkileşimde açılıyor." />
          ) : (
            <ul className="space-y-1.5">
              {overview.levels.map((level) => {
                const widest = Math.max(...overview.levels.map((row) => row.members), 1);
                return (
                  <li key={level.level} className="flex items-center gap-3 text-xs">
                    <span className="w-40 shrink-0 truncate text-ink-muted">
                      Seviye {level.level} · {level.title}
                    </span>
                    <span className="h-2 flex-1 rounded-full bg-surface-overlay">
                      <span
                        className="block h-2 rounded-full bg-brand-500"
                        style={{ width: `${Math.round((level.members / widest) * 100)}%` }}
                      />
                    </span>
                    <span className="w-12 shrink-0 text-right text-ink">{count(level.members)}</span>
                  </li>
                );
              })}
            </ul>
          )}
        </CardContent>
      </Card>

      {granting && (
        <GrantDialog
          badge={granting}
          onClose={() => setGranting(null)}
          onDone={() => { setGranting(null); void reload(); }}
        />
      )}
      {inspecting && (
        <HoldersDialog
          badge={inspecting}
          canGrant={canGrant}
          onClose={() => setInspecting(null)}
          onRevoked={() => void reload()}
        />
      )}
    </div>
  );
}

/**
 * Rozeti verme kutusu.
 *
 * Üye kimliğini elle yazdırmak yerine arama var: kırk karakterlik bir UUID'yi
 * kopyalarken yapılan bir hata, rozeti yanlış kişiye verir ve bunu kimse fark
 * etmez. Gerekçe zorunlu — altı ay sonra “bu madalya neden verilmiş” diye bakan
 * kişinin elindeki tek şey o cümle.
 */
function GrantDialog({ badge, onClose, onDone }: { badge: JourneyBadge; onClose: () => void; onDone: () => void }) {
  const [query, setQuery] = useState('');
  const [hits, setHits] = useState<MemberHit[]>([]);
  const [selected, setSelected] = useState<MemberHit | null>(null);
  const [reason, setReason] = useState('');
  const [searching, setSearching] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  async function search() {
    if (query.trim().length < 2) { setError('Aramak için en az iki karakter yaz.'); return; }
    setSearching(true);
    setError(null);
    try {
      const data = await apiData<MemberHit[]>(`/api/members?query=${encodeURIComponent(query.trim())}`);
      setHits(data);
      if (data.length === 0) setNotice('Bu aramaya uyan üye bulunamadı.');
      else setNotice(null);
    } catch (searchError) {
      setError(errorText(searchError, 'Üyeler aranamadı.'));
    } finally {
      setSearching(false);
    }
  }

  async function submit() {
    if (!selected) { setError('Önce bir üye seç.'); return; }
    setBusy(true);
    setError(null);
    try {
      const result = await apiData<{ granted: boolean }>(`/api/journey/badges/${encodeURIComponent(badge.code)}/grant`, {
        method: 'POST',
        body: JSON.stringify({ userId: selected.id, reason: reason.trim() }),
      });
      // Zaten taşıyan bir üyeye "verildi" demek, olmayan bir değişikliği
      // bildirmek olurdu.
      if (!result.granted) { setNotice('Bu üye rozeti zaten taşıyor; bir şey değişmedi.'); setBusy(false); return; }
      onDone();
    } catch (grantError) {
      setError(errorText(grantError, 'Rozet verilemedi.'));
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(next) => { if (!next && !busy) onClose(); }}>
      <DialogContent title={`${badge.title} rozetini ver`} description={badge.description}>
        <DialogBody className="space-y-4">
          <Field label="Üye ara" hint="Ad ya da e-posta. Kimliği elle yazmak yerine listeden seç.">
            <div className="flex gap-2">
              <Input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                onKeyDown={(event) => { if (event.key === 'Enter') { event.preventDefault(); void search(); } }}
                placeholder="ör. Elif"
              />
              <Button variant="outline" onClick={() => void search()} disabled={searching}>
                <Search size={14} /> Ara
              </Button>
            </div>
          </Field>

          {hits.length > 0 && (
            <ul className="max-h-48 divide-y divide-hairline overflow-y-auto rounded-lg border border-hairline">
              {hits.map((hit) => (
                <li key={hit.id}>
                  <button
                    type="button"
                    onClick={() => setSelected(hit)}
                    className={cn(
                      'flex w-full items-center justify-between gap-3 px-3 py-2 text-left text-xs transition hover:bg-surface-overlay',
                      selected?.id === hit.id && 'bg-surface-overlay',
                    )}
                  >
                    <span className="min-w-0">
                      <span className="block truncate text-ink">{hit.displayName}</span>
                      <span className="block truncate text-ink-faint">{hit.email}</span>
                    </span>
                    {selected?.id === hit.id && <Badge tone="brand">Seçili</Badge>}
                  </button>
                </li>
              ))}
            </ul>
          )}

          <Field
            label="Gerekçe"
            hint="Denetim kaydına bu cümle yazılıyor. En az 3 karakter."
            error={reason.trim().length > 0 && reason.trim().length < 3 ? 'Gerekçe en az 3 karakter olmalı.' : undefined}
          >
            <Textarea rows={3} value={reason} onChange={(event) => setReason(event.target.value)} maxLength={240} />
          </Field>

          {notice && <p className="text-xs text-ink-muted">{notice}</p>}
          {error && <p className="text-xs text-danger">{error}</p>}
        </DialogBody>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose} disabled={busy}>Vazgeç</Button>
          <Button variant="primary" onClick={() => void submit()} disabled={busy || !selected || reason.trim().length < 3}>
            {busy ? 'Veriliyor…' : 'Rozeti ver'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/**
 * Rozeti kimlerin taşıdığı.
 *
 * Elle verilen satırlarda gerekçe ve veren kişi de görünüyor; motorun verdiği
 * satırlarda görünmüyor, çünkü orada bir karar yok. Geri alma yalnızca elle
 * verilenlerde açık: kazanılmış bir rozeti panelden silmek, üyenin gerçekten
 * yaptığı bir şeyi geri almak olurdu.
 */
function HoldersDialog({
  badge,
  canGrant,
  onClose,
  onRevoked,
}: {
  badge: JourneyBadge;
  canGrant: boolean;
  onClose: () => void;
  onRevoked: () => void;
}) {
  const [holders, setHolders] = useState<BadgeHolder[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      setHolders(await apiData<BadgeHolder[]>(`/api/journey/badges/${encodeURIComponent(badge.code)}/holders`));
    } catch (loadError) {
      // `null` kalıyor: boş liste göstermek "bu rozeti kimse taşımıyor"
      // demek olurdu, oysa liste hiç gelmedi.
      setError(errorText(loadError, 'Taşıyanlar okunamadı.'));
    }
  }, [badge.code]);

  useEffect(() => { void load(); }, [load]);

  async function revoke(holder: BadgeHolder) {
    setBusyId(holder.userId);
    setError(null);
    try {
      await apiData(`/api/journey/badges/${encodeURIComponent(badge.code)}/holders/${holder.userId}`, { method: 'DELETE' });
      setHolders((current) => (current ?? []).filter((row) => row.userId !== holder.userId));
      onRevoked();
    } catch (revokeError) {
      setError(errorText(revokeError, 'Rozet geri alınamadı.'));
    } finally {
      setBusyId(null);
    }
  }

  return (
    <Dialog open onOpenChange={(next) => { if (!next) onClose(); }}>
      <DialogContent title={`${badge.title} — taşıyanlar`} description="En son alan en üstte. En fazla 100 satır.">
        <DialogBody className="space-y-3">
          {error && <p className="text-xs text-danger">{error}</p>}
          {holders === null ? (
            !error && <p className="text-xs text-ink-faint">Yükleniyor…</p>
          ) : holders.length === 0 ? (
            <EmptyState title="Bu rozeti henüz kimse taşımıyor." description={badgeHealth(badge).note || undefined} />
          ) : (
            <ul className="max-h-80 divide-y divide-hairline overflow-y-auto">
              {holders.map((holder) => (
                <li key={holder.userId} className="flex items-start gap-3 py-2.5 text-xs">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-ink">{holder.displayName ?? holder.userId}</p>
                    <p className="text-ink-faint">{formatDateTime(holder.earnedAt)}</p>
                    {holder.grantedBy ? (
                      <p className="mt-1 text-ink-muted">
                        Elle verildi — {holder.grantedByName ?? 'panel'}: {holder.grantedReason ?? 'gerekçe yazılmamış'}
                      </p>
                    ) : (
                      <p className="mt-1 text-ink-faint">Kuralla kazanıldı.</p>
                    )}
                  </div>
                  {canGrant && holder.grantedBy !== null && (
                    <Button size="sm" variant="danger" onClick={() => void revoke(holder)} disabled={busyId === holder.userId}>
                      {busyId === holder.userId ? '…' : 'Geri al'}
                    </Button>
                  )}
                </li>
              ))}
            </ul>
          )}
        </DialogBody>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>Kapat</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
