'use client';
import { useCallback, useEffect, useMemo, useState } from 'react';
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
import { GripVertical, Lock, MessageSquare, Pin, Search, Tags } from 'lucide-react';
import { apiData, errorText, formatDateTime } from '@/lib/api-client';
import { FORUM_STATE_LABELS, type ForumCategory, type ForumTopicRow } from '@/lib/forum-labels';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { DataTable, type ColumnDef } from '@/components/ui/data-table';
import { Dialog, DialogBody, DialogContent, DialogFooter } from '@/components/ui/dialog';
import { Field, Input, Select, Textarea } from '@/components/ui/field';
import { EmptyState } from '@/components/ui/page';
import { ReasonDialog } from '@/components/ui/reason-dialog';
import { Sheet, SheetContent } from '@/components/ui/sheet';
import { StatCard } from '@/components/ui/stat-card';

/**
 * Forum: the sections on top, the threads underneath.
 *
 * The order of the sections was the thing this screen could not do. The column
 * has always been there - `forum_categories.ordinal`, seeded in migration 019 -
 * but the only way to set it was a number typed into the create form, and the
 * edit form did not expose it at all. So the list members see was whatever
 * ordinal happened to be typed on the day each section was opened, and moving
 * one to the top meant renumbering the rest by hand, one PATCH at a time, with
 * the forum reshuffling itself between saves.
 *
 * Dragging writes the whole order in one request. Same shape as the promotion
 * board, for the same reason: a partial order is a forum nobody chose.
 *
 * The other gap was smaller and worse: an operator locking a thread could see
 * its title and nothing else. The list now carries the opening paragraph.
 */
type StateFilter = 'active' | 'hidden' | 'removed' | 'all';

const STATE_OPTIONS: [StateFilter, string][] = [
  ['active', 'Yayında'],
  ['hidden', 'Gizlenmiş'],
  ['removed', 'Kaldırılmış'],
  ['all', 'Hepsi'],
];

export function ForumDesk({
  initialCategories,
  loadFailure,
  canEdit,
  canModerate,
}: {
  initialCategories: ForumCategory[];
  loadFailure: string | null;
  canEdit: boolean;
  canModerate: boolean;
}) {
  const [categories, setCategories] = useState(initialCategories);
  const [topics, setTopics] = useState<ForumTopicRow[]>([]);
  const [error, setError] = useState<string | null>(loadFailure);
  const [notice, setNotice] = useState<string | null>(null);

  const [categoryFilter, setCategoryFilter] = useState('');
  const [stateFilter, setStateFilter] = useState<StateFilter>('active');
  const [query, setQuery] = useState('');
  const [appliedQuery, setAppliedQuery] = useState('');

  const [openTopicId, setOpenTopicId] = useState<string | null>(null);
  const [topicAction, setTopicAction] = useState<{ topic: ForumTopicRow; field: 'isPinned' | 'isLocked' } | null>(null);

  const reloadCategories = useCallback(async () => {
    setCategories(await apiData<ForumCategory[]>('/api/forum/categories'));
  }, []);

  const loadTopics = useCallback(async (category: string, state: StateFilter, search: string) => {
    const params = new URLSearchParams({ state });
    if (category) params.set('categoryId', category);
    // The service wants at least two characters; sending one back means an
    // unfiltered list arriving as if it were a search result.
    if (search.trim().length >= 2) params.set('query', search.trim());
    try {
      setTopics(await apiData<ForumTopicRow[]>(`/api/forum/topics?${params}`));
    } catch (caught) {
      setError(errorText(caught, 'Konular okunamadı.'));
    }
  }, []);

  useEffect(() => { void loadTopics(categoryFilter, stateFilter, appliedQuery); }, [loadTopics, categoryFilter, stateFilter, appliedQuery]);

  const totals = useMemo(() => ({
    active: categories.filter((row) => row.isActive).length,
    closed: categories.filter((row) => !row.isActive).length,
    topics: categories.reduce((sum, row) => sum + row.topicCount, 0),
    replies: categories.reduce((sum, row) => sum + row.replyCount, 0),
  }), [categories]);

  const openTopic = topics.find((row) => row.id === openTopicId) ?? null;

  const columns = useMemo<ColumnDef<ForumTopicRow, unknown>[]>(
    () => [
      {
        id: 'title',
        header: 'Konu',
        accessorFn: (row) => `${row.title} ${row.authorName ?? ''}`,
        cell: ({ row }) => (
          <div className="max-w-md min-w-0">
            <div className="flex items-center gap-1.5">
              {row.original.isPinned && <Pin size={12} className="shrink-0 text-brand-300" />}
              {row.original.isLocked && <Lock size={12} className="shrink-0 text-warning" />}
              <p className="truncate font-medium text-ink">{row.original.title}</p>
            </div>
            <p className="truncate text-xs text-ink-faint">
              {row.original.categoryTitle} · {row.original.authorName ?? row.original.authorId.slice(0, 8)}
            </p>
          </div>
        ),
      },
      {
        id: 'state',
        header: 'Durum',
        accessorFn: (row) => row.moderationState,
        cell: ({ row }) =>
          row.original.moderationState === 'active'
            ? <Badge tone="success" dot>Yayında</Badge>
            : <Badge tone="danger" dot>{FORUM_STATE_LABELS[row.original.moderationState] ?? row.original.moderationState}</Badge>,
      },
      {
        id: 'engagement',
        header: 'Hareket',
        accessorFn: (row) => row.replyCount,
        cell: ({ row }) => (
          <span className="text-xs whitespace-nowrap">{row.original.replyCount} yanıt · {row.original.viewCount} görüntülenme</span>
        ),
      },
      {
        id: 'lastActivity',
        header: 'Son hareket',
        accessorFn: (row) => row.lastActivityAt,
        cell: ({ row }) => <span className="text-xs whitespace-nowrap">{formatDateTime(row.original.lastActivityAt)}</span>,
      },
      {
        id: 'actions',
        header: '',
        enableSorting: false,
        cell: ({ row }) => <Button size="sm" variant="outline" onClick={() => setOpenTopicId(row.original.id)}>Aç</Button>,
      },
    ],
    [],
  );

  async function applyTopicState(reason: string) {
    if (!topicAction) return;
    const { topic, field } = topicAction;
    const next = await apiData<{ id: string; isPinned: boolean; isLocked: boolean }>(
      `/api/forum/topics/${topic.id}/state`,
      { method: 'POST', body: JSON.stringify({ [field]: !topic[field], reason }) },
    );
    setTopics((current) => current.map((row) => (row.id === next.id ? { ...row, isPinned: next.isPinned, isLocked: next.isLocked } : row)));
    setNotice('Konu durumu güncellendi ve denetim kaydına yazıldı.');
  }

  return (
    <div className="grid gap-6">
      {error && <div className="rounded-card border border-warning/30 bg-warning-soft p-4 text-sm text-warning">{error}</div>}
      {notice && <div className="rounded-card border border-success/30 bg-success-soft p-4 text-sm text-success">{notice}</div>}

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="Açık bölüm" value={String(totals.active)} detail="Yeni konu alabilen kategoriler" icon={Tags} tone="brand" />
        <StatCard label="Kapalı bölüm" value={String(totals.closed)} detail="Okunur, yeni konu almaz" icon={Lock} tone={totals.closed > 0 ? 'warning' : 'neutral'} />
        <StatCard label="Konu" value={String(totals.topics)} detail="Yayında olan konular" icon={MessageSquare} />
        <StatCard label="Yanıt" value={String(totals.replies)} detail="Bu konulara yazılan yanıtlar" />
      </div>

      <CategoryBoard
        categories={categories}
        canEdit={canEdit}
        onError={setError}
        onDone={async (message) => { setNotice(message); await reloadCategories(); }}
      />

      <div>
        <div className="mb-3 flex flex-wrap items-end justify-between gap-3">
          <div>
            <h2 className="text-sm font-semibold text-ink">Konular</h2>
            <p className="mt-1 max-w-2xl text-xs text-ink-faint">
              Sabitlenen konu listenin başında durur; kilitlenen konu okunur ama yeni yanıt almaz. İçerik kaldırma bu ekranda değil, Moderasyon Merkezi&apos;ndeki şikâyet kuyruğunda yapılır.
            </p>
          </div>
        </div>

        <form
          className="mb-3 flex flex-wrap gap-2"
          onSubmit={(event) => { event.preventDefault(); setAppliedQuery(query); }}
        >
          <Select className="w-auto min-w-48" value={categoryFilter} onChange={(event) => setCategoryFilter(event.target.value)} aria-label="Kategori süzgeci">
            <option value="">Tüm kategoriler</option>
            {categories.map((category) => <option key={category.id} value={category.id}>{category.title}</option>)}
          </Select>
          <Select className="w-auto min-w-40" value={stateFilter} onChange={(event) => setStateFilter(event.target.value as StateFilter)} aria-label="Durum süzgeci">
            {STATE_OPTIONS.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </Select>
          <Input
            className="min-w-56 flex-1"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Başlıkta ara (en az 2 harf)"
            aria-label="Başlıkta ara"
          />
          {/* Server-side, unlike the table's own filter: an operator looking for
              a thread means all of them, not the fifty on this page. */}
          <Button type="submit" variant="secondary"><Search size={15} /> Ara</Button>
        </form>

        <DataTable
          columns={columns}
          rows={topics}
          rowKey={(row) => row.id}
          onRowClick={(row) => setOpenTopicId(row.id)}
          emptyLabel="Bu süzgeçte konu yok."
          isRowUrgent={(row) => row.moderationState !== 'active'}
        />
      </div>

      <Sheet open={openTopic !== null} onOpenChange={(open) => { if (!open) setOpenTopicId(null); }}>
        {openTopic && (
          <SheetContent title={openTopic.title} description={`${openTopic.categoryTitle} · ${openTopic.authorName ?? openTopic.authorId}`}>
            <TopicDetail
              topic={openTopic}
              canModerate={canModerate}
              onAct={(field) => setTopicAction({ topic: openTopic, field })}
            />
          </SheetContent>
        )}
      </Sheet>

      <ReasonDialog
        open={topicAction !== null}
        onOpenChange={(open) => { if (!open) setTopicAction(null); }}
        title={
          topicAction?.field === 'isPinned'
            ? (topicAction.topic.isPinned ? 'Sabitleme kaldırılacak' : 'Konu sabitlenecek')
            : (topicAction?.topic.isLocked ? 'Kilit açılacak' : 'Konu kilitlenecek')
        }
        description={
          topicAction?.field === 'isPinned'
            ? `"${topicAction.topic.title}" ${topicAction.topic.isPinned ? 'listenin başından inecek.' : 'kategorisinin en üstünde duracak.'}`
            : `"${topicAction?.topic.title ?? ''}" ${topicAction?.topic.isLocked ? 'yeniden yanıt alacak.' : 'okunmaya devam eder ama yeni yanıt almaz.'}`
        }
        confirmLabel="Uygula"
        onConfirm={applyTopicState}
      />
    </div>
  );
}

function TopicDetail({
  topic, canModerate, onAct,
}: {
  topic: ForumTopicRow;
  canModerate: boolean;
  onAct: (field: 'isPinned' | 'isLocked') => void;
}) {
  return (
    <div className="grid gap-5 p-5">
      <div className="flex flex-wrap items-center gap-2">
        {topic.isPinned && <Badge tone="brand"><Pin size={12} /> Sabit</Badge>}
        {topic.isLocked && <Badge tone="warning"><Lock size={12} /> Kilitli</Badge>}
        <Badge tone={topic.moderationState === 'active' ? 'success' : 'danger'} dot>
          {FORUM_STATE_LABELS[topic.moderationState] ?? topic.moderationState}
        </Badge>
      </div>

      <div className="rounded-card border border-hairline bg-surface-raised p-4">
        <p className="text-sm leading-relaxed whitespace-pre-wrap text-ink-muted">{topic.excerpt}</p>
        {/* Honest about the cut: the list carries the first 600 characters, and
            a decision taken on a paragraph should know it was a paragraph. */}
        <p className="mt-3 text-xs text-ink-faint">Konunun ilk 600 karakteri. Tamamı uygulamada okunur.</p>
      </div>

      <dl className="grid gap-x-6 gap-y-3 text-sm sm:grid-cols-2">
        <div><dt className="text-xs text-ink-faint">Kategori</dt><dd className="text-ink">{topic.categoryTitle}</dd></div>
        <div><dt className="text-xs text-ink-faint">Açan</dt><dd className="truncate text-ink">{topic.authorName ?? topic.authorId}</dd></div>
        <div><dt className="text-xs text-ink-faint">Açılış</dt><dd className="text-ink">{formatDateTime(topic.createdAt)}</dd></div>
        <div><dt className="text-xs text-ink-faint">Son hareket</dt><dd className="text-ink">{formatDateTime(topic.lastActivityAt)}</dd></div>
        <div><dt className="text-xs text-ink-faint">Yanıt</dt><dd className="text-ink">{topic.replyCount}</dd></div>
        <div><dt className="text-xs text-ink-faint">Görüntülenme</dt><dd className="text-ink">{topic.viewCount}</dd></div>
      </dl>

      {canModerate && (
        <div className="flex flex-wrap gap-2 border-t border-hairline pt-5">
          <Button variant="secondary" onClick={() => onAct('isPinned')}>
            <Pin size={15} /> {topic.isPinned ? 'Sabitlemeyi kaldır' : 'Sabitle'}
          </Button>
          <Button variant={topic.isLocked ? 'secondary' : 'danger'} onClick={() => onAct('isLocked')}>
            <Lock size={15} /> {topic.isLocked ? 'Kilidi aç' : 'Kilitle'}
          </Button>
        </div>
      )}
    </div>
  );
}

/// The sections, in the order members see them.
function CategoryBoard({
  categories, canEdit, onError, onDone,
}: {
  categories: ForumCategory[];
  canEdit: boolean;
  onError: (message: string | null) => void;
  onDone: (message: string) => Promise<void>;
}) {
  const [draft, setDraft] = useState<ForumCategory[] | null>(null);
  const [confirmingOrder, setConfirmingOrder] = useState(false);
  const [editing, setEditing] = useState<ForumCategory | 'new' | null>(null);
  const [toggling, setToggling] = useState<ForumCategory | null>(null);

  const sensors = useSensors(
    // A few pixels of travel before a drag starts, so clicking a button in the
    // row is not read as the beginning of a reorder.
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const list = draft ?? categories;
  const dirty = draft !== null && draft.some((row, index) => categories[index]?.id !== row.id);

  function onDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const current = draft ?? categories;
    const from = current.findIndex((row) => row.id === active.id);
    const to = current.findIndex((row) => row.id === over.id);
    if (from < 0 || to < 0) return;
    setDraft(arrayMove(current, from, to));
  }

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle>Bölümler</CardTitle>
          <CardDescription>
            Sıra uygulamadaki forum listesinin sırasıdır; sürükleyip kaydettiğinde üyeler bir sonraki açılışta yeni sırayı görür.
            Kapatılan bölüm silinmez: yeni konu almaz, içindeki konular okunmaya devam eder. Kısa ad (slug) sonradan değiştirilemez, çünkü bağlantılar ve kayıtlı süzgeçler ona bağlıdır.
          </CardDescription>
        </div>
        {canEdit && <Button size="sm" variant="primary" onClick={() => setEditing('new')}>Yeni bölüm</Button>}
      </CardHeader>
      <CardContent className="pt-4">
        {dirty && (
          <div className="mb-3 flex items-center justify-end gap-2">
            <Button size="sm" variant="ghost" onClick={() => setDraft(null)}>Vazgeç</Button>
            <Button size="sm" variant="primary" onClick={() => setConfirmingOrder(true)}>Sırayı kaydet</Button>
          </div>
        )}

        {list.length === 0 ? (
          <EmptyState title="Henüz bölüm yok." description="Üyelerin konu açabilmesi için en az bir bölüm gerekir." />
        ) : (
          <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
            <SortableContext items={list.map((row) => row.id)} strategy={verticalListSortingStrategy}>
              <ul className="grid gap-2">
                {list.map((category, index) => (
                  <SortableCategory
                    key={category.id}
                    category={category}
                    index={index}
                    canEdit={canEdit}
                    onEdit={() => setEditing(category)}
                    onToggle={() => setToggling(category)}
                  />
                ))}
              </ul>
            </SortableContext>
          </DndContext>
        )}
      </CardContent>

      <ReasonDialog
        open={confirmingOrder}
        onOpenChange={setConfirmingOrder}
        title="Bölüm sırası değişecek"
        description={`${list.length} bölümün sırası kaydedilir ve uygulamadaki forum listesinde hemen geçerli olur.`}
        confirmLabel="Sırayı kaydet"
        onConfirm={async (reason) => {
          onError(null);
          await apiData('/api/forum/categories/order', {
            method: 'PUT',
            body: JSON.stringify({ ids: list.map((row) => row.id), reason }),
          });
          setDraft(null);
          await onDone('Bölüm sırası kaydedildi.');
        }}
      />

      <ReasonDialog
        open={toggling !== null}
        onOpenChange={(open) => { if (!open) setToggling(null); }}
        title={toggling?.isActive ? 'Bölüm kapatılacak' : 'Bölüm yeniden açılacak'}
        description={
          toggling?.isActive
            ? `"${toggling.title}" yeni konu almaz. İçindeki ${toggling.topicCount} konu okunmaya devam eder.`
            : `"${toggling?.title ?? ''}" yeniden konu alabilir hâle gelir.`
        }
        confirmLabel={toggling?.isActive ? 'Kapat' : 'Aç'}
        variant={toggling?.isActive ? 'danger' : 'success'}
        onConfirm={async (reason) => {
          if (!toggling) return;
          await apiData(`/api/forum/categories/${toggling.id}`, {
            method: 'PATCH',
            body: JSON.stringify({ isActive: !toggling.isActive, reason }),
          });
          await onDone(toggling.isActive ? 'Bölüm kapatıldı.' : 'Bölüm yeniden açıldı.');
        }}
      />

      {editing && (
        <CategoryDialog
          category={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={async (message) => { setEditing(null); await onDone(message); }}
        />
      )}
    </Card>
  );
}

function SortableCategory({
  category, index, canEdit, onEdit, onToggle,
}: {
  category: ForumCategory;
  index: number;
  canEdit: boolean;
  onEdit: () => void;
  onToggle: () => void;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: category.id, disabled: !canEdit });

  return (
    <li
      ref={setNodeRef}
      style={{ transform: CSS.Transform.toString(transform), transition }}
      className={`flex flex-wrap items-center gap-3 rounded-lg border p-3 ${
        isDragging ? 'z-10 border-brand-400/60 shadow-2xl' : 'border-hairline'
      } ${category.isActive ? 'bg-surface-raised' : 'bg-canvas'}`}
    >
      <span className="w-6 shrink-0 text-center text-sm font-semibold text-ink-faint tabular-nums">{index + 1}</span>
      {canEdit && (
        <button
          type="button"
          // A real button so the keyboard sensor can pick the row up with space
          // and move it with the arrow keys.
          className="cursor-grab rounded p-1 text-ink-faint transition hover:bg-surface-overlay hover:text-ink active:cursor-grabbing"
          aria-label={`${category.title} sırasını değiştir`}
          {...attributes}
          {...listeners}
        >
          <GripVertical size={16} />
        </button>
      )}
      <span className="text-lg" aria-hidden>{category.emoji}</span>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <p className="truncate text-sm font-medium text-ink">{category.title}</p>
          {!category.isActive && <Badge tone="warning">Kapalı</Badge>}
        </div>
        <p className="truncate text-xs text-ink-faint">
          /{category.slug} · {category.topicCount} konu · {category.replyCount} yanıt ·{' '}
          {category.lastActivityAt ? `son hareket ${formatDateTime(category.lastActivityAt)}` : 'hareket yok'}
        </p>
        {category.description && <p className="mt-1 truncate text-xs text-ink-muted">{category.description}</p>}
      </div>
      {canEdit && (
        <div className="flex gap-2">
          <Button size="sm" variant="outline" onClick={onEdit}>Düzenle</Button>
          <Button size="sm" variant={category.isActive ? 'danger' : 'success'} onClick={onToggle}>
            {category.isActive ? 'Kapat' : 'Aç'}
          </Button>
        </div>
      )}
    </li>
  );
}

/**
 * One dialog for opening a section and for editing one, because they are the
 * same form minus the slug. The slug is asked once and never again: community
 * refuses to patch it, since a shared link and a saved filter hang off it.
 */
function CategoryDialog({
  category, onClose, onSaved,
}: {
  category: ForumCategory | null;
  onClose: () => void;
  onSaved: (message: string) => Promise<void>;
}) {
  const [title, setTitle] = useState(category?.title ?? '');
  const [slug, setSlug] = useState('');
  const [emoji, setEmoji] = useState(category?.emoji ?? '💬');
  const [description, setDescription] = useState(category?.description ?? '');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const creating = category === null;
  const slugValid = /^[a-z0-9-]{2,48}$/.test(slug);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    if (creating && !slugValid) { setError('Kısa ad yalnızca küçük harf, rakam ve tire içerebilir (2-48 karakter).'); return; }
    if (reason.trim().length < 5) { setError('Gerekçe en az 5 karakter olmalı.'); return; }
    setBusy(true);
    try {
      if (creating) {
        await apiData('/api/forum/categories', {
          method: 'POST',
          body: JSON.stringify({ slug, title: title.trim(), emoji: emoji.trim() || '💬', description: description.trim(), reason: reason.trim() }),
        });
        await onSaved('Bölüm açıldı.');
      } else {
        await apiData(`/api/forum/categories/${category.id}`, {
          method: 'PATCH',
          body: JSON.stringify({ title: title.trim(), emoji: emoji.trim(), description: description.trim(), reason: reason.trim() }),
        });
        await onSaved('Bölüm güncellendi.');
      }
    } catch (caught) {
      setError(errorText(caught, 'Bölüm kaydedilemedi.'));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(open) => { if (!open && !busy) onClose(); }}>
      <DialogContent
        title={creating ? 'Yeni bölüm aç' : `${category.title} düzenle`}
        description={creating ? 'Bölüm listenin sonuna eklenir; sırasını sürükleyerek değiştirebilirsin.' : 'Kısa ad değiştirilemez.'}
      >
        <form onSubmit={submit}>
          <DialogBody className="grid gap-4">
            <Field label="Başlık">
              <Input required minLength={2} maxLength={80} value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Vize & Göçmenlik" />
            </Field>
            {creating && (
              <Field
                label="Kısa ad"
                hint="Küçük harf, rakam ve tire. Sonradan değiştirilemez."
                error={slug.length > 0 && !slugValid ? 'Yalnızca küçük harf, rakam ve tire kullanılabilir.' : undefined}
              >
                <Input required value={slug} onChange={(event) => setSlug(event.target.value.toLowerCase())} placeholder="vize-gocmenlik" />
              </Field>
            )}
            <div className="grid gap-4 sm:grid-cols-[100px_minmax(0,1fr)]">
              <Field label="Simge">
                <Input maxLength={8} value={emoji} onChange={(event) => setEmoji(event.target.value)} placeholder="🎓" />
              </Field>
              <Field label="Açıklama" hint="Listede başlığın altında görünür.">
                <Input maxLength={240} value={description} onChange={(event) => setDescription(event.target.value)} placeholder="Vize türleri, yeşil kart, vatandaşlık ve randevular" />
              </Field>
            </div>
            <Field label="İşlem nedeni" hint="Denetim kaydına aynen yazılır." error={error ?? undefined}>
              <Textarea required rows={2} minLength={5} maxLength={500} value={reason} onChange={(event) => setReason(event.target.value)} />
            </Field>
          </DialogBody>
          <DialogFooter>
            <Button type="button" variant="ghost" disabled={busy} onClick={onClose}>Vazgeç</Button>
            <Button type="submit" variant="primary" disabled={busy}>{busy ? 'Kaydediliyor…' : creating ? 'Bölümü aç' : 'Kaydet'}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
