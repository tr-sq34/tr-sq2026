'use client';
import { useCallback, useMemo, useState } from 'react';
import {
  DndContext,
  KeyboardSensor,
  PointerSensor,
  closestCenter,
  useSensor,
  useSensors,
  type DragEndEvent,
} from '@dnd-kit/core';
import {
  SortableContext,
  arrayMove,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { GripVertical, ImageOff, MousePointerClick, Eye, Percent, Radio } from 'lucide-react';
import { apiData, errorText, formatDateTime } from '@/lib/api-client';
import type { SystemAccount } from '@/lib/content-labels';
import {
  PROMOTION_PLACEMENT_LABELS,
  PROMOTION_STATUS_LABELS,
  PROMOTION_WINDOW_LABELS,
  formatCount,
  formatCtr,
  promotionCtr,
  promotionWindowState,
  type PromotionSummary,
} from '@/lib/promotion-labels';
import { ImageUpload, type UploadedImage } from '@/components/content/image-upload';
import { Badge, type BadgeTone } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { DataTable, type ColumnDef } from '@/components/ui/data-table';
import { Field, Input, Select, Textarea } from '@/components/ui/field';
import { EmptyState } from '@/components/ui/page';
import { PhonePreview } from '@/components/ui/phone-preview';
import { ReasonDialog } from '@/components/ui/reason-dialog';
import { Sheet, SheetContent } from '@/components/ui/sheet';
import { StatCard } from '@/components/ui/stat-card';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';

/**
 * Tanitim Yap's console side.
 *
 * Three things the old studio could not do, all of them decisions an operator
 * was making blind.
 *
 * It could not say whether a placement was working. The counters existed -
 * `promotion_impressions` has been filled since the home screen started
 * counting - and a member could see their own, but the person deciding whether
 * to keep a card running could not. "Is this worth the slot" was answered by
 * opinion.
 *
 * It could not order the live cards. The only way to move one up was to end it
 * and place it again with a later start, which resets its counters and loses
 * the reason it was approved for. Migration 031 gave the row a place to keep
 * that opinion; this is where it gets set.
 *
 * And it could not show what it was about to produce. The preview on the right
 * is the same card `discover_screen.dart` draws - 260x130, gradient, "Sponsorlu"
 * badge - so a title that gets cut off is visible before it ships.
 */
type Status = 'pending' | 'approved' | 'rejected' | 'ended';
type Placement = 'featured_card' | 'story_slot' | 'app_banner';

const STATUS_TABS: [Status, string][] = [
  ['pending', 'Onay bekleyen'],
  ['approved', 'Onaylı'],
  ['rejected', 'Reddedilen'],
  ['ended', 'Sonlandırılan'],
];

const PLACEMENTS: Placement[] = ['featured_card', 'story_slot', 'app_banner'];

const WINDOW_TONES: Record<string, BadgeTone> = {
  live: 'success',
  scheduled: 'brand',
  expired: 'warning',
  off: 'neutral',
};

// `datetime-local` hands over a local wall clock with no zone. The instant is
// settled once, here, so an operator in Istanbul and one in New Jersey do not
// disagree about when a placement starts.
const instant = (value: string) => (value ? new Date(value).toISOString() : undefined);

export function PromotionDesk({
  initialPending,
  initialApproved,
  accounts,
  loadFailure,
  canDecide,
}: {
  initialPending: PromotionSummary[];
  initialApproved: PromotionSummary[];
  accounts: SystemAccount[];
  loadFailure: string | null;
  canDecide: boolean;
}) {
  const [status, setStatus] = useState<Status>('pending');
  // Only the two tabs an operator opens first are loaded on the server; the
  // archive tabs are fetched when asked for and then kept, so switching back
  // and forth does not re-hit the service.
  const [cache, setCache] = useState<Partial<Record<Status, PromotionSummary[]>>>({
    pending: initialPending,
    approved: initialApproved,
  });
  const [error, setError] = useState<string | null>(loadFailure);
  const [notice, setNotice] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [decision, setDecision] = useState<{ id: string; action: 'approve' | 'reject' | 'end'; title: string } | null>(null);

  const rows = cache[status] ?? [];
  const selected = rows.find((row) => row.id === selectedId) ?? null;

  const load = useCallback(async (next: Status) => {
    setStatus(next);
    setError(null);
    if (cache[next]) return;
    try {
      const fetched = await apiData<PromotionSummary[]>(`/api/promotions?status=${next}`);
      setCache((current) => ({ ...current, [next]: fetched }));
    } catch (caught) {
      setError(errorText(caught, 'Tanıtım listesi okunamadı.'));
    }
  }, [cache]);

  const refresh = useCallback(async (target: Status) => {
    try {
      const fresh = await apiData<PromotionSummary[]>(`/api/promotions?status=${target}`);
      setCache((current) => ({ ...current, [target]: fresh }));
    } catch (caught) {
      setError(errorText(caught, 'Liste yenilenemedi.'));
    }
  }, []);

  const totals = useMemo(() => {
    const impressions = rows.reduce((sum, row) => sum + row.impressions, 0);
    const clicks = rows.reduce((sum, row) => sum + row.clicks, 0);
    const live = rows.filter((row) => promotionWindowState(row) === 'live').length;
    return { impressions, clicks, live };
  }, [rows]);

  const columns = useMemo<ColumnDef<PromotionSummary, unknown>[]>(
    () => [
      {
        id: 'title',
        header: 'Tanıtım',
        accessorFn: (row) => `${row.title} ${row.subtitle ?? ''} ${row.ownerName}`,
        cell: ({ row }) => (
          <div className="max-w-sm min-w-0">
            <p className="truncate font-medium text-ink">{row.original.title}</p>
            <p className="truncate text-xs text-ink-faint">{row.original.ownerName}{row.original.subtitle ? ` · ${row.original.subtitle}` : ''}</p>
          </div>
        ),
      },
      {
        id: 'placement',
        header: 'Alan',
        accessorFn: (row) => row.placement,
        cell: ({ row }) => <Badge>{PROMOTION_PLACEMENT_LABELS[row.original.placement] ?? row.original.placement}</Badge>,
      },
      {
        id: 'audience',
        header: 'Hedef',
        accessorFn: (row) => `${row.city ?? ''} ${row.regionCode ?? ''}`,
        cell: ({ row }) => (
          <span className="text-xs whitespace-nowrap">
            {[row.original.city, row.original.regionCode].filter(Boolean).join(', ') || 'Tüm ülke'}
          </span>
        ),
      },
      {
        id: 'window',
        header: 'Yayın aralığı',
        accessorFn: (row) => row.startsAt,
        cell: ({ row }) => (
          <span className="text-xs whitespace-nowrap">{formatDateTime(row.original.startsAt)} → {formatDateTime(row.original.endsAt)}</span>
        ),
      },
      {
        id: 'reach',
        header: 'Etkileşim',
        accessorFn: (row) => row.impressions,
        cell: ({ row }) => <MetricLine row={row.original} />,
      },
      {
        id: 'actions',
        header: '',
        enableSorting: false,
        cell: ({ row }) => <Button size="sm" variant="outline" onClick={() => setSelectedId(row.original.id)}>Aç</Button>,
      },
    ],
    [],
  );

  async function applyDecision(reason: string) {
    if (!decision) return;
    await apiData(`/api/promotions/${decision.id}/decision`, {
      method: 'POST',
      body: JSON.stringify({ action: decision.action, reason }),
    });
    setSelectedId(null);
    setNotice('Karar kaydedildi ve denetim kaydına yazıldı.');
    // Both lists move: the row leaves one tab and lands in another, and an
    // approved list that still shows a card an operator just pulled is the
    // exact confusion this screen exists to remove.
    await Promise.all([refresh('pending'), refresh('approved')]);
    if (decision.action !== 'approve') await refresh(decision.action === 'reject' ? 'rejected' : 'ended');
  }

  return (
    <div className="grid gap-6">
      {error && <div className="rounded-card border border-warning/30 bg-warning-soft p-4 text-sm text-warning">{error}</div>}
      {notice && <div className="rounded-card border border-success/30 bg-success-soft p-4 text-sm text-success">{notice}</div>}

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Gösterim"
          value={formatCount(totals.impressions)}
          detail={`${PROMOTION_STATUS_LABELS[status]} ${rows.length} tanıtımın toplamı`}
          icon={Eye}
        />
        <StatCard label="Tıklanma" value={formatCount(totals.clicks)} detail="Karta dokunup açılan sayısı" icon={MousePointerClick} tone="brand" />
        <StatCard
          label="CTR"
          value={formatCtr(promotionCtr(totals.impressions, totals.clicks))}
          // Zero impressions is not a zero rate; the card says which one it is
          // rather than printing a percentage nothing was measured for.
          detail={totals.impressions === 0 ? 'Henüz gösterim sayılmadı' : 'Gösterim başına tıklanma'}
          unavailable={totals.impressions === 0}
          icon={Percent}
        />
        <StatCard
          label="Şu an ekranda"
          value={formatCount(totals.live)}
          detail="Onaylı ve yayın aralığı içinde"
          icon={Radio}
          tone={totals.live > 0 ? 'success' : 'neutral'}
        />
      </div>

      <Tabs value={status} onValueChange={(value) => void load(value as Status)}>
        <TabsList>
          {STATUS_TABS.map(([value, label]) => (
            <TabsTrigger key={value} value={value} count={cache[value]?.length}>{label}</TabsTrigger>
          ))}
        </TabsList>
      </Tabs>

      {status === 'approved' ? (
        <OrderBoard
          rows={rows}
          canDecide={canDecide}
          onOpen={setSelectedId}
          onSaved={async (message) => { setNotice(message); await refresh('approved'); }}
          onError={setError}
        />
      ) : (
        <DataTable
          columns={columns}
          rows={rows}
          rowKey={(row) => row.id}
          onRowClick={(row) => setSelectedId(row.id)}
          searchPlaceholder="Başlık, sahip ya da alt satır ara"
          emptyLabel={`Bu filtrede tanıtım yok (${PROMOTION_STATUS_LABELS[status]}).`}
        />
      )}

      {canDecide && <PlaceForm accounts={accounts} onPlaced={async () => { setNotice('Tanıtım yayına alındı.'); await refresh('approved'); }} onError={setError} />}

      <Sheet open={selected !== null} onOpenChange={(open) => { if (!open) setSelectedId(null); }}>
        {selected && (
          <SheetContent title={selected.title} description={`${PROMOTION_PLACEMENT_LABELS[selected.placement] ?? selected.placement} · ${selected.ownerName}`}>
            <PromotionDetail
              row={selected}
              canDecide={canDecide}
              onDecide={(action) => setDecision({ id: selected.id, action, title: selected.title })}
            />
          </SheetContent>
        )}
      </Sheet>

      <ReasonDialog
        open={decision !== null}
        onOpenChange={(open) => { if (!open) setDecision(null); }}
        title={
          decision?.action === 'approve' ? 'Tanıtım yayına alınacak'
            : decision?.action === 'reject' ? 'Tanıtım reddedilecek'
              : 'Tanıtım yayından kaldırılacak'
        }
        description={`"${decision?.title ?? ''}" için yazdığın gerekçe üyeye gösterilir ve denetim kaydına aynen geçer.`}
        confirmLabel={decision?.action === 'approve' ? 'Onayla' : decision?.action === 'reject' ? 'Reddet' : 'Yayından kaldır'}
        variant={decision?.action === 'approve' ? 'success' : 'danger'}
        onConfirm={applyDecision}
      />
    </div>
  );
}

function MetricLine({ row }: { row: PromotionSummary }) {
  const ctr = promotionCtr(row.impressions, row.clicks);
  return (
    <span className="text-xs whitespace-nowrap text-ink-muted">
      {formatCount(row.impressions)} gösterim · {formatCount(row.clicks)} tıklanma
      {ctr !== null && <span className="ml-1.5 text-ink-faint">({formatCtr(ctr)})</span>}
    </span>
  );
}

/**
 * The running order, one strip at a time.
 *
 * `display_order` is a single column across all approved rows, but the app
 * splits them by placement before drawing, so two cards in different strips are
 * never compared to each other. Ordering one strip at a time is therefore both
 * correct and the only framing that means anything to an operator: "which card
 * comes first in Sana Ozel One Cikanlar" is a question; "which comes first
 * among all promotions" is not.
 */
function OrderBoard({
  rows,
  canDecide,
  onOpen,
  onSaved,
  onError,
}: {
  rows: PromotionSummary[];
  canDecide: boolean;
  onOpen: (id: string) => void;
  onSaved: (message: string) => Promise<void>;
  onError: (message: string | null) => void;
}) {
  const [placement, setPlacement] = useState<Placement>('featured_card');
  const [draft, setDraft] = useState<PromotionSummary[] | null>(null);
  const [confirming, setConfirming] = useState(false);

  const sensors = useSensors(
    // A few pixels of travel before a drag starts, so clicking a row to open it
    // is not read as the beginning of a reorder.
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const scoped = useMemo(() => rows.filter((row) => row.placement === placement), [rows, placement]);
  const list = draft ?? scoped;
  const dirty = draft !== null && draft.some((row, index) => scoped[index]?.id !== row.id);

  function onDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const current = draft ?? scoped;
    const from = current.findIndex((row) => row.id === active.id);
    const to = current.findIndex((row) => row.id === over.id);
    if (from < 0 || to < 0) return;
    setDraft(arrayMove(current, from, to));
  }

  function switchPlacement(next: Placement) {
    setDraft(null);
    setPlacement(next);
  }

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle>Yayın sırası</CardTitle>
          <CardDescription>
            Kartları sürükleyerek uygulamadaki sırayı belirle. Sıralanmamış tanıtımlar en sonda, başlangıç tarihi yenisi önde olacak şekilde kalır.
            {placement === 'featured_card' && ' “Sana Özel Öne Çıkanlar” şeridinde ilk kart her zaman rozet kartıdır; buradaki 1. sıra ekranda onun hemen ardından gelir.'}
          </CardDescription>
        </div>
      </CardHeader>
      <CardContent className="pt-4">
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <Tabs value={placement} onValueChange={(value) => switchPlacement(value as Placement)}>
            <TabsList>
              {PLACEMENTS.map((value) => (
                <TabsTrigger key={value} value={value} count={rows.filter((row) => row.placement === value).length}>
                  {PROMOTION_PLACEMENT_LABELS[value]}
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
          {dirty && (
            <div className="flex items-center gap-2">
              <Button size="sm" variant="ghost" onClick={() => setDraft(null)}>Vazgeç</Button>
              <Button size="sm" variant="primary" onClick={() => setConfirming(true)}>Sırayı kaydet</Button>
            </div>
          )}
        </div>

        {list.length === 0 ? (
          <EmptyState title="Bu alanda onaylı tanıtım yok." description="Onayladığın ya da panelden yerleştirdiğin kartlar burada sıralanır." />
        ) : (
          <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
            <SortableContext items={list.map((row) => row.id)} strategy={verticalListSortingStrategy}>
              <ul className="grid gap-2">
                {list.map((row, index) => (
                  <SortableRow key={row.id} row={row} index={index} draggable={canDecide} onOpen={onOpen} />
                ))}
              </ul>
            </SortableContext>
          </DndContext>
        )}
      </CardContent>

      <ReasonDialog
        open={confirming}
        onOpenChange={setConfirming}
        title="Yayın sırası değişecek"
        description={`${PROMOTION_PLACEMENT_LABELS[placement]} alanındaki ${list.length} kartın sırası kaydedilir ve uygulamada hemen geçerli olur.`}
        confirmLabel="Sırayı kaydet"
        onConfirm={async (reason) => {
          onError(null);
          await apiData('/api/promotions/order', {
            method: 'PUT',
            body: JSON.stringify({ ids: list.map((row) => row.id), reason }),
          });
          setDraft(null);
          await onSaved('Yayın sırası kaydedildi.');
        }}
      />
    </Card>
  );
}

function SortableRow({
  row, index, draggable, onOpen,
}: {
  row: PromotionSummary;
  index: number;
  draggable: boolean;
  onOpen: (id: string) => void;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: row.id, disabled: !draggable });
  const state = promotionWindowState(row);

  return (
    <li
      ref={setNodeRef}
      style={{ transform: CSS.Transform.toString(transform), transition }}
      className={`flex items-center gap-3 rounded-lg border border-hairline bg-surface-raised p-3 ${isDragging ? 'z-10 border-brand-400/60 shadow-2xl' : ''}`}
    >
      <span className="w-6 shrink-0 text-center text-sm font-semibold text-ink-faint tabular-nums">{index + 1}</span>
      {draggable && (
        <button
          type="button"
          // The handle is the only draggable part, and it is a real button so
          // the keyboard sensor can pick the row up with space and move it
          // with the arrow keys.
          className="cursor-grab rounded p-1 text-ink-faint transition hover:bg-surface-overlay hover:text-ink active:cursor-grabbing"
          aria-label={`${row.title} sırasını değiştir`}
          {...attributes}
          {...listeners}
        >
          <GripVertical size={16} />
        </button>
      )}
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium text-ink">{row.title}</p>
        <p className="truncate text-xs text-ink-faint">
          {row.ownerName} · {[row.city, row.regionCode].filter(Boolean).join(', ') || 'Tüm ülke'} · {formatDateTime(row.endsAt)} tarihinde biter
        </p>
      </div>
      <MetricLine row={row} />
      <Badge tone={WINDOW_TONES[state]} dot>{PROMOTION_WINDOW_LABELS[state]}</Badge>
      <Button size="sm" variant="outline" onClick={() => onOpen(row.id)}>Aç</Button>
    </li>
  );
}

function PromotionDetail({
  row, canDecide, onDecide,
}: {
  row: PromotionSummary;
  canDecide: boolean;
  onDecide: (action: 'approve' | 'reject' | 'end') => void;
}) {
  const state = promotionWindowState(row);
  const ctr = promotionCtr(row.impressions, row.clicks);

  return (
    <div className="grid gap-5 p-5">
      <div className="flex flex-wrap items-center gap-2">
        <Badge>{PROMOTION_STATUS_LABELS[row.status] ?? row.status}</Badge>
        <Badge tone={WINDOW_TONES[state]} dot>{PROMOTION_WINDOW_LABELS[state]}</Badge>
        {row.displayOrder !== null && <Badge tone="brand">Sıra #{row.displayOrder}</Badge>}
      </div>

      {row.subtitle && <p className="text-sm text-ink-muted">{row.subtitle}</p>}

      {/* The picture an operator is approving, not a placeholder: the decision
          is about what members will actually see. */}
      {row.imageUrl ? (
        <img src={row.imageUrl} alt="" className="max-h-56 w-full rounded-card border border-hairline object-cover" />
      ) : (
        <div className="flex items-center gap-2 rounded-card border border-dashed border-hairline p-4 text-xs text-ink-faint">
          <ImageOff size={15} /> Görsel yok — kart düz arka planla çizilir.
        </div>
      )}

      <div className="grid grid-cols-3 gap-3">
        <MetricBox label="Gösterim" value={formatCount(row.impressions)} />
        <MetricBox label="Tıklanma" value={formatCount(row.clicks)} />
        <MetricBox label="CTR" value={formatCtr(ctr)} muted={ctr === null} />
      </div>

      <dl className="grid gap-x-6 gap-y-3 text-sm sm:grid-cols-2">
        <Row label="İsteyen" value={row.ownerName} />
        <Row label="Hedef kitle" value={[row.city, row.regionCode].filter(Boolean).join(', ') || 'Tüm ülke'} />
        <Row label="Başlangıç" value={formatDateTime(row.startsAt)} />
        <Row label="Bitiş" value={formatDateTime(row.endsAt)} />
        <Row label="Bağlantı" value={row.targetValue ? `${row.targetKind}: ${row.targetValue}` : 'Yok'} />
        <Row label="Talep tarihi" value={formatDateTime(row.createdAt)} />
      </dl>

      {row.requestNote && (
        <div className="rounded-card border border-hairline bg-surface-raised p-4 text-sm text-ink-muted">
          <span className="text-ink-faint">Üyenin gerekçesi: </span>{row.requestNote}
        </div>
      )}
      {row.decisionReason && (
        <div className="rounded-card border border-hairline bg-surface-raised p-4 text-sm text-ink-muted">
          <span className="text-ink-faint">Karar notu: </span>{row.decisionReason}
        </div>
      )}

      {canDecide && row.status === 'pending' && (
        <div className="flex flex-wrap gap-2 border-t border-hairline pt-5">
          <Button variant="success" onClick={() => onDecide('approve')}>Onayla ve yayına al</Button>
          <Button variant="danger" onClick={() => onDecide('reject')}>Reddet</Button>
        </div>
      )}
      {canDecide && row.status === 'approved' && (
        <div className="border-t border-hairline pt-5">
          <Button variant="danger" onClick={() => onDecide('end')}>Yayından kaldır</Button>
          <p className="mt-2 text-xs text-ink-faint">Sayaçlar kayıtta kalır; kart bir daha gösterilmez.</p>
        </div>
      )}
    </div>
  );
}

function MetricBox({ label, value, muted = false }: { label: string; value: string; muted?: boolean }) {
  return (
    <div className="rounded-card border border-hairline bg-surface-raised p-3">
      <p className="text-[11px] tracking-wide text-ink-faint uppercase">{label}</p>
      <p className={`mt-1 text-lg font-semibold ${muted ? 'text-ink-faint' : 'text-ink'}`}>{value}</p>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0">
      <dt className="text-xs text-ink-faint">{label}</dt>
      <dd className="truncate text-ink">{value}</dd>
    </div>
  );
}

/**
 * Placing one straight from the console. No approval step: the person placing
 * it is the person who would have approved it, and the audit record says so.
 *
 * The owner used to be a UUID typed into a text box. Every official account the
 * panel opens is now in the list, because pasting the wrong id put a promotion
 * under someone else's name and nothing on the screen showed it.
 */
function PlaceForm({
  accounts, onPlaced, onError,
}: {
  accounts: SystemAccount[];
  onPlaced: () => Promise<void>;
  onError: (message: string | null) => void;
}) {
  const active = accounts.filter((row) => row.active);
  const [ownerChoice, setOwnerChoice] = useState(active[0]?.id ?? 'manual');
  const [manualOwnerId, setManualOwnerId] = useState('');
  const [placement, setPlacement] = useState<Placement>('featured_card');
  const [title, setTitle] = useState('');
  const [subtitle, setSubtitle] = useState('');
  const [image, setImage] = useState<UploadedImage | null>(null);
  const [targetKind, setTargetKind] = useState('');
  const [targetValue, setTargetValue] = useState('');
  const [regionCode, setRegionCode] = useState('');
  const [city, setCity] = useState('');
  const [startsAt, setStartsAt] = useState('');
  const [endsAt, setEndsAt] = useState('');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);

  const ownerId = ownerChoice === 'manual' ? manualOwnerId.trim() : ownerChoice;

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    onError(null);
    if (!ownerId) { onError('Tanıtımın hangi hesabın adına çıkacağını seç.'); return; }
    setBusy(true);
    try {
      await apiData<{ id: string }>('/api/promotions', {
        method: 'POST',
        body: JSON.stringify({
          placement,
          ownerId,
          title: title.trim(),
          subtitle: subtitle.trim() || undefined,
          mediaId: image?.mediaId,
          targetKind: targetKind || undefined,
          targetValue: targetValue.trim() || undefined,
          regionCode: regionCode.trim() || undefined,
          city: city.trim() || undefined,
          startsAt: instant(startsAt),
          endsAt: instant(endsAt),
          reason: reason.trim(),
        }),
      });
      setTitle(''); setSubtitle(''); setImage(null); setTargetValue(''); setReason('');
      await onPlaced();
    } catch (caught) {
      onError(errorText(caught, 'Tanıtım yerleştirilemedi.'));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_auto]">
      <Card>
        <CardHeader>
          <div>
            <CardTitle>Panelden tanıtım yerleştir</CardTitle>
            <CardDescription>
              Onay adımı yok: yerleştiren kişi zaten onaylayacak kişidir ve işlem denetim kaydına bu şekilde yazılır. “Sana Özel Öne Çıkanlar” kartları yalnızca buradan girilir.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent>
          <form onSubmit={submit} className="grid gap-4">
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="Alan">
                <Select value={placement} onChange={(event) => setPlacement(event.target.value as Placement)}>
                  {PLACEMENTS.map((value) => <option key={value} value={value}>{PROMOTION_PLACEMENT_LABELS[value]}</option>)}
                </Select>
              </Field>
              <Field label="Tanıtımın sahibi" hint={active.length === 0 ? 'Aktif resmî hesap yok; İçerik Stüdyosu\'ndan bir tane açabilirsin.' : 'Kart bu hesabın adına yayınlanır.'}>
                <Select value={ownerChoice} onChange={(event) => setOwnerChoice(event.target.value)}>
                  {active.map((row) => <option key={row.id} value={row.id}>{row.displayName ?? row.id}</option>)}
                  <option value="manual">Başka bir üye (kimlik gir)</option>
                </Select>
              </Field>
            </div>

            {ownerChoice === 'manual' && (
              <Field label="Üye kimliği" hint="Üyeler ekranındaki kimliği kopyala; yanlış kimlik tanıtımı başkasının adına yayınlar.">
                <Input required value={manualOwnerId} onChange={(event) => setManualOwnerId(event.target.value)} placeholder="00000000-0000-0000-0000-000000000000" />
              </Field>
            )}

            <Field label="Başlık" hint={`${title.length} / 120 karakter · kartta iki satıra sığması gerekir`}>
              <Input required minLength={3} maxLength={120} value={title} onChange={(event) => setTitle(event.target.value)} />
            </Field>
            <Field label="Alt satır" hint="Boş bırakırsan uygulama hedef kitle etiketini yazar.">
              <Input maxLength={200} value={subtitle} onChange={(event) => setSubtitle(event.target.value)} />
            </Field>

            <Field
              label="Kart görseli"
              hint={
                placement === 'story_slot'
                  ? 'Story şeridinde tam ekran açılır; dikey (9:16) görsel kullan.'
                  : 'Kartın üzerine %40 karartmayla serilir. Boş bırakırsan kart degradeyle çizilir.'
              }
            >
              <ImageUpload ownerId={ownerId} value={image} onChange={setImage} disabled={busy} />
            </Field>

            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="Bağlantı türü" hint="Karta dokununca ne açılacak?">
                <Select value={targetKind} onChange={(event) => setTargetKind(event.target.value)}>
                  <option value="">Yok</option>
                  <option value="post">Paylaşım</option>
                  <option value="listing">İlan</option>
                  <option value="news">Haber</option>
                  <option value="event">Etkinlik</option>
                  <option value="external">Dış bağlantı</option>
                </Select>
              </Field>
              <Field label="Bağlantı değeri">
                <Input maxLength={500} value={targetValue} onChange={(event) => setTargetValue(event.target.value)} placeholder="Kimlik ya da https://..." />
              </Field>
              <Field label="Eyalet kodu" hint="Boşsa ülke geneli.">
                <Input maxLength={2} value={regionCode} onChange={(event) => setRegionCode(event.target.value.toUpperCase())} placeholder="NJ" />
              </Field>
              <Field label="Şehir" hint="Eyalet koduyla birlikte anlamlı.">
                <Input maxLength={80} value={city} onChange={(event) => setCity(event.target.value)} placeholder="Paterson" />
              </Field>
              <Field label="Başlangıç">
                <Input type="datetime-local" required value={startsAt} onChange={(event) => setStartsAt(event.target.value)} />
              </Field>
              <Field label="Bitiş">
                <Input type="datetime-local" required value={endsAt} onChange={(event) => setEndsAt(event.target.value)} />
              </Field>
            </div>

            <Field label="İşlem nedeni" hint="Denetim kaydına aynen yazılır.">
              <Textarea required rows={2} minLength={5} maxLength={500} value={reason} onChange={(event) => setReason(event.target.value)} />
            </Field>

            <div>
              <Button type="submit" variant="primary" disabled={busy}>{busy ? 'Yerleştiriliyor…' : 'Tanıtımı yayına al'}</Button>
            </div>
          </form>
        </CardContent>
      </Card>

      <PhonePreview label="Ana sayfadaki görünümü">
        <CardPreview
          title={title}
          subtitle={subtitle}
          audience={[city, regionCode].filter(Boolean).join(', ') || 'Tüm ülke'}
          imageUrl={image?.url ?? null}
          placement={placement}
        />
      </PhonePreview>
    </div>
  );
}

/**
 * The same card `_HighlightCard` in discover_screen.dart draws: 260x130, a
 * rounded slate gradient, the "Sponsorlu" pill and two lines of text. It is
 * here so a title that would be cut off is cut off on this screen first.
 */
function CardPreview({
  title, subtitle, audience, imageUrl, placement,
}: {
  title: string;
  subtitle: string;
  audience: string;
  imageUrl: string | null;
  placement: Placement;
}) {
  // Story yuvası akışta kart değil, şeritte yuvarlak bir kapak ve dokununca tam
  // ekran açılan dikey bir görsel. Aynı önizlemeyi ikisine de çizmek, yatay bir
  // görselin şeritte kırpıldığını yayına girene kadar gizliyordu.
  if (placement === 'story_slot') {
    return (
      <div className="px-4">
        <p className="text-[15px] font-black text-white">Story şeridi</p>
        <p className="text-[10px] font-medium text-[#8b93a7]">Sponsorlu alan · şeridin başında</p>

        <div className="mt-3 flex items-start gap-3">
          <div className="w-[68px] shrink-0">
            <div className="rounded-full bg-gradient-to-br from-[#f59e0b] to-[#ec4899] p-[2px]">
              <div className="overflow-hidden rounded-full border-2 border-[#0b0a12] bg-[#1a1828]" style={{ aspectRatio: '1 / 1' }}>
                {imageUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={imageUrl} alt="" className="h-full w-full object-cover" />
                ) : null}
              </div>
            </div>
            <p className="mt-1 truncate text-center text-[9px] text-white/80">{title.trim() || 'Başlık'}</p>
          </div>

          <div className="relative w-[92px] overflow-hidden rounded-xl bg-[#131120]" style={{ aspectRatio: '9 / 16' }}>
            {imageUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={imageUrl} alt="" className="h-full w-full object-cover" />
            ) : (
              <p className="flex h-full items-center justify-center px-2 text-center text-[9px] text-ink-faint">Tam ekran</p>
            )}
            <span className="absolute top-2 left-2 rounded-md border border-white/20 bg-black/40 px-1.5 py-0.5 text-[8px] font-bold text-white">
              Sponsorlu
            </span>
          </div>
        </div>

        <p className="mt-3 text-[11px] text-ink-faint">
          {imageUrl
            ? 'Şeritte kapak dairesel kırpılır, dokununca görsel tam ekran açılır.'
            : 'Görsel yok: Story yuvası görselsiz yayına giremez, şeritte boş bir daire kalır.'}
        </p>
      </div>
    );
  }

  return (
    <div className="px-4">
      <p className="text-[15px] font-black text-white">
        {placement === 'featured_card' ? 'Sana Özel Öne Çıkanlar' : 'Uygulama içi banner'}
      </p>
      <p className="text-[10px] font-medium text-[#8b93a7]">
        {placement === 'featured_card' ? 'Bulunduğun yere göre seçilen kartlar' : 'Sponsorlu alan'}
      </p>

      <div className="relative mt-3 h-[130px] w-[240px] overflow-hidden rounded-3xl bg-gradient-to-br from-[#334155] to-[#0F172A] shadow-lg">
        {imageUrl && (
          <>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={imageUrl} alt="" className="absolute inset-0 h-full w-full object-cover" />
            <div className="absolute inset-0 bg-black/40" />
          </>
        )}
        <div className="relative flex h-full flex-col justify-between p-4">
          <span className="self-start rounded-lg border border-white/20 bg-white/15 px-2 py-1 text-[9px] font-bold text-white">
            Sponsorlu
          </span>
          <div className="min-w-0">
            <p className="line-clamp-2 text-[15px] leading-tight font-bold break-words text-white">
              {title.trim() || 'Başlık buraya gelecek'}
            </p>
            <p className="mt-1 truncate text-[10px] text-white/70">{subtitle.trim() || audience}</p>
          </div>
        </div>
      </div>

      <p className="mt-3 text-[11px] text-ink-faint">
        {imageUrl
          ? 'Görsel kartın üzerine %40 karartmayla serilir; başlık her hâlükârda okunur kalır.'
          : 'Görsel yok: kart bu degradeyle çizilir.'}
      </p>
    </div>
  );
}
