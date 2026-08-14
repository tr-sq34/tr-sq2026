'use client';
import { useCallback, useMemo, useState } from 'react';
import { Ban, CalendarClock, CalendarPlus, CheckCircle2, FilePen, Users } from 'lucide-react';
import { api, apiData, errorText } from '@/lib/api-client';
import {
  EVENT_CATEGORIES,
  EVENT_STATUS_LABELS,
  EVENT_STATUS_ORDER,
  attendanceLabel,
  categoryLabel,
  eventWhen,
  placeLabel,
  type EventRow,
} from '@/lib/events-labels';
import { Badge, type BadgeTone } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { DataTable, type ColumnDef } from '@/components/ui/data-table';
import { Field, Input, Select, Textarea } from '@/components/ui/field';
import { NotConnected } from '@/components/ui/page';
import { ReasonDialog } from '@/components/ui/reason-dialog';
import { Sheet, SheetContent } from '@/components/ui/sheet';
import { StatCard } from '@/components/ui/stat-card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';

/**
 * Etkinlikler ve Biletleme.
 *
 * The event half is real: the community service has a table, and publishing an
 * event here puts it in the app's Etkinlikler tab under the operator's name and
 * in the audit log. An event is a promise that somebody will be somewhere at a
 * stated time, so cancelling it takes a reason - that sentence is the only thing
 * the member who kept the evening free gets to read.
 *
 * The ticketing half is not built. There is no ticket table, no QR issuance and
 * no payment path, so this screen says so instead of drawing an empty revenue
 * card. A "0 ₺ bilet geliri" would be indistinguishable from a working module
 * that sold nothing, and that is the one wrong answer worth avoiding here.
 *
 * Nothing here shows who is coming - only how many. A list of names would be a
 * record of who was where on a given evening, which is the record this service
 * is built not to keep.
 */
const STATUS_TONE: Record<string, BadgeTone> = {
  published: 'success',
  draft: 'warning',
  cancelled: 'danger',
};

const EMPTY = {
  title: '',
  description: '',
  category: 'Community',
  startsAt: '',
  endsAt: '',
  venueLabel: '',
  city: '',
  regionCode: '',
  priceLabel: 'Ücretsiz',
  externalUrl: '',
  capacity: '',
};

type Status = (typeof EVENT_STATUS_ORDER)[number];
type Notice = { tone: 'ok' | 'bad'; text: string };

export function EventsDesk({
  initialPublished,
  initialDrafts,
  initialCancelled,
  initialFailure,
  canPublish,
}: {
  initialPublished: EventRow[];
  initialDrafts: EventRow[];
  initialCancelled: EventRow[];
  initialFailure: string | null;
  canPublish: boolean;
}) {
  const [rows, setRows] = useState<Record<Status, EventRow[]>>({
    published: initialPublished,
    draft: initialDrafts,
    cancelled: initialCancelled,
  });
  const [tab, setTab] = useState<Status>('published');
  const [form, setForm] = useState(EMPTY);
  const [composerOpen, setComposerOpen] = useState(false);
  const [selected, setSelected] = useState<EventRow | null>(null);
  const [cancelling, setCancelling] = useState<EventRow | null>(null);
  const [notice, setNotice] = useState<Notice | null>(initialFailure ? { tone: 'bad', text: initialFailure } : null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async (status: Status) => {
    const data = await apiData<EventRow[]>(`/api/events?status=${status}`);
    setRows((current) => ({ ...current, [status]: data }));
  }, []);

  const refresh = useCallback(
    async (...statuses: Status[]) => {
      try {
        await Promise.all(statuses.map((status) => load(status)));
      } catch (error) {
        setNotice({ tone: 'bad', text: errorText(error, 'Etkinlikler alınamadı.') });
      }
    },
    [load],
  );

  const set = (key: keyof typeof EMPTY) => (event: { target: { value: string } }) =>
    setForm((current) => ({ ...current, [key]: event.target.value }));

  // The service enforces all of this; checking here means the operator learns
  // about a missing city before the round trip, not after it.
  const formReady =
    form.title.trim().length >= 3 &&
    form.startsAt.length > 0 &&
    form.venueLabel.trim().length >= 2 &&
    form.city.trim().length >= 2 &&
    form.regionCode.trim().length === 2;

  async function submit(publish: boolean) {
    setBusy(true);
    try {
      await api<{ id: string }>('/api/events', {
        method: 'POST',
        body: JSON.stringify({
          ...form,
          externalUrl: form.externalUrl.trim() || undefined,
          capacity: form.capacity.trim() ? Number(form.capacity) : undefined,
          publish,
        }),
      });
      setNotice({
        tone: 'ok',
        text: publish
          ? 'Etkinlik yayında; uygulamadaki Etkinlikler sekmesinde görünüyor.'
          : 'Taslak kaydedildi; yayına almadan kimse görmüyor.',
      });
      setForm(EMPTY);
      setComposerOpen(false);
      const target: Status = publish ? 'published' : 'draft';
      setTab(target);
      await refresh(target);
    } catch (error) {
      setNotice({ tone: 'bad', text: errorText(error, 'Etkinlik kaydedilemedi.') });
    } finally {
      setBusy(false);
    }
  }

  async function publishRow(row: EventRow) {
    setBusy(true);
    try {
      await api(`/api/events/${row.id}/publish`, { method: 'POST' });
      setNotice({ tone: 'ok', text: `"${row.title}" yayında.` });
      setSelected(null);
      await refresh('draft', 'published');
    } catch (error) {
      setNotice({ tone: 'bad', text: errorText(error, 'Etkinlik yayınlanamadı.') });
    } finally {
      setBusy(false);
    }
  }

  async function cancelRow(reason: string) {
    const row = cancelling;
    if (!row) return;
    await api(`/api/events/${row.id}/cancel`, { method: 'POST', body: JSON.stringify({ reason }) });
    setNotice({ tone: 'ok', text: 'Etkinlik iptal edildi; kayıt ve gerekçe duruyor.' });
    setCancelling(null);
    setSelected(null);
    await refresh(row.status as Status, 'cancelled');
  }

  const attending = useMemo(() => rows.published.reduce((total, row) => total + row.attendeeCount, 0), [rows.published]);

  const columns: ColumnDef<EventRow, unknown>[] = [
    {
      id: 'title',
      header: 'Etkinlik',
      accessorFn: (row) => `${row.title} ${row.category}`,
      cell: ({ row }) => (
        <div className="min-w-0 max-w-80">
          <p className="truncate font-medium text-ink">{row.original.title}</p>
          <p className="mt-0.5 text-xs text-ink-faint">
            {categoryLabel(row.original.category)} · {row.original.priceLabel}
          </p>
        </div>
      ),
    },
    {
      id: 'startsAt',
      header: 'Ne zaman',
      accessorFn: (row) => row.startsAt,
      cell: ({ row }) => <span className="text-xs">{eventWhen(row.original.startsAt, row.original.endsAt)}</span>,
    },
    {
      id: 'place',
      header: 'Yer',
      accessorFn: (row) => placeLabel(row),
      cell: ({ row }) => <span className="text-xs text-ink-faint">{placeLabel(row.original)}</span>,
    },
    {
      id: 'attendance',
      header: 'Katılım',
      accessorFn: (row) => row.attendeeCount,
      cell: ({ row }) => <span className="whitespace-nowrap text-xs">{attendanceLabel(row.original)}</span>,
    },
    {
      id: 'status',
      header: 'Durum',
      accessorFn: (row) => EVENT_STATUS_LABELS[row.status] ?? row.status,
      cell: ({ row }) => (
        <Badge tone={STATUS_TONE[row.original.status] ?? 'neutral'} dot>
          {EVENT_STATUS_LABELS[row.original.status] ?? row.original.status}
        </Badge>
      ),
    },
  ];

  return (
    <div className="grid gap-6">
      {notice && (
        <Card tone={notice.tone === 'bad' ? 'urgent' : 'default'}>
          <CardContent className="flex items-start gap-3 text-sm text-ink-muted">
            {notice.tone === 'bad' ? (
              <Ban size={17} className="mt-0.5 shrink-0 text-danger" />
            ) : (
              <CheckCircle2 size={17} className="mt-0.5 shrink-0 text-success" />
            )}
            {notice.text}
          </CardContent>
        </Card>
      )}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label="Yayında" value={String(rows.published.length)} icon={CalendarClock} tone="success" detail="uygulamada görünüyor" />
        <StatCard label="Taslak" value={String(rows.draft.length)} icon={FilePen} tone="warning" detail="yayına alınmadı" />
        <StatCard label="İptal edildi" value={String(rows.cancelled.length)} icon={Ban} detail="gerekçesiyle duruyor" />
        <StatCard label="Katılacağını söyleyen" value={String(attending)} icon={Users} detail="yayındaki etkinliklerin toplamı" />
      </div>

      <NotConnected
        what="Biletleme ve QR bilet yapım aşamasında."
        why="Bilet tablosu, QR üretimi ve ödeme akışı henüz yazılmadı; bu yüzden burada bilet satışı, bilet geliri ya da kapıda okutma sayısı yok. Etkinlik yayınlama ve iptal etme aşağıda çalışıyor, ücretli etkinliklerde tahsilat şimdilik kayıt bağlantısındaki dış sistemde kalıyor."
      />

      <Tabs value={tab} onValueChange={(value) => setTab(value as Status)}>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <TabsList>
            {EVENT_STATUS_ORDER.map((status) => (
              <TabsTrigger key={status} value={status} count={rows[status].length}>
                {EVENT_STATUS_LABELS[status]}
              </TabsTrigger>
            ))}
          </TabsList>
          {canPublish && (
            <Button variant="primary" onClick={() => setComposerOpen(true)}>
              <CalendarPlus size={15} />
              Etkinlik oluştur
            </Button>
          )}
        </div>

        {EVENT_STATUS_ORDER.map((status) => (
          <TabsContent key={status} value={status} className="mt-4">
            <DataTable
              columns={columns}
              rows={rows[status]}
              rowKey={(row) => row.id}
              onRowClick={setSelected}
              searchPlaceholder="Başlık, mekân veya şehir ara"
              emptyLabel={`${EVENT_STATUS_LABELS[status]} durumunda etkinlik yok.`}
            />
          </TabsContent>
        ))}
      </Tabs>

      <Sheet open={selected !== null} onOpenChange={(open) => !open && setSelected(null)}>
        {selected && (
          <SheetContent title={selected.title} description={eventWhen(selected.startsAt, selected.endsAt)}>
            <div className="grid gap-4 p-5">
              <div className="flex flex-wrap items-center gap-2">
                <Badge tone={STATUS_TONE[selected.status] ?? 'neutral'} dot>
                  {EVENT_STATUS_LABELS[selected.status] ?? selected.status}
                </Badge>
                <Badge>{categoryLabel(selected.category)}</Badge>
                <span className="text-xs text-ink-faint">{selected.priceLabel}</span>
              </div>

              {selected.description && <p className="text-sm whitespace-pre-wrap text-ink-muted">{selected.description}</p>}

              <dl className="grid gap-2 rounded-lg border border-hairline bg-canvas p-4 text-sm">
                {(
                  [
                    ['Yer', placeLabel(selected)],
                    ['Katılım', attendanceLabel(selected)],
                    ['Kontenjan', selected.capacity ? String(selected.capacity) : 'sınırsız'],
                    ['Kayıt bağlantısı', selected.externalUrl ?? 'yok'],
                  ] as [string, string][]
                ).map(([label, value]) => (
                  <div key={label} className="flex flex-wrap items-baseline justify-between gap-3">
                    <dt className="text-xs text-ink-faint">{label}</dt>
                    <dd className="text-right text-xs break-all text-ink-muted">{value}</dd>
                  </div>
                ))}
              </dl>

              {selected.cancellationReason && (
                <Card tone="urgent">
                  <CardContent className="text-sm text-ink-muted">
                    <p className="text-xs text-ink-faint">İptal gerekçesi</p>
                    <p className="mt-1">{selected.cancellationReason}</p>
                  </CardContent>
                </Card>
              )}

              <p className="text-xs text-ink-faint">
                Kimlerin geldiği panele gelmez, yalnızca sayısı. Bilet ve QR akışı bu etkinlik için de henüz yok.
              </p>

              {canPublish && selected.status !== 'cancelled' && (
                <div className="flex flex-wrap gap-2 border-t border-hairline pt-4">
                  {selected.status === 'draft' && (
                    <Button variant="success" disabled={busy} onClick={() => void publishRow(selected)}>
                      Yayınla
                    </Button>
                  )}
                  <Button variant="danger" disabled={busy} onClick={() => setCancelling(selected)}>
                    İptal et
                  </Button>
                </div>
              )}
            </div>
          </SheetContent>
        )}
      </Sheet>

      <Sheet open={composerOpen} onOpenChange={setComposerOpen}>
        <SheetContent title="Yeni etkinlik" description="Yayınlanan etkinlik uygulamadaki Etkinlikler sekmesinde, senin adına ve denetim kaydıyla görünür.">
          <div className="grid gap-3 p-5 sm:grid-cols-2">
            <Field label="Başlık" className="sm:col-span-2" hint="En az 3 karakter.">
              <Input value={form.title} onChange={set('title')} placeholder="Türk Kahvaltısı Buluşması" />
            </Field>
            <Field label="Açıklama" className="sm:col-span-2">
              <Textarea value={form.description} onChange={set('description')} rows={4} placeholder="Ne olacağı, kimin için, ne getirmeli." />
            </Field>
            <Field label="Kategori" hint="Uygulama kapak görselini bu anahtara göre çiziyor.">
              <Select value={form.category} onChange={set('category')}>
                {EVENT_CATEGORIES.map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Ücret" hint="Tahsilat panelde değil; burası yalnızca üyeye gösterilen etiket.">
              <Input value={form.priceLabel} onChange={set('priceLabel')} placeholder="Ücretsiz / Kapıda 20$" />
            </Field>
            <Field label="Başlangıç">
              <Input type="datetime-local" value={form.startsAt} onChange={set('startsAt')} />
            </Field>
            <Field label="Bitiş" hint="İsteğe bağlı.">
              <Input type="datetime-local" value={form.endsAt} onChange={set('endsAt')} />
            </Field>
            <Field label="Mekân" className="sm:col-span-2">
              <Input value={form.venueLabel} onChange={set('venueLabel')} placeholder="Anadolu Kültür Merkezi, 214 5th Ave" />
            </Field>
            <Field label="Şehir">
              <Input value={form.city} onChange={set('city')} placeholder="Brooklyn" />
            </Field>
            <Field label="Eyalet kodu" hint="İki harf.">
              <Input
                value={form.regionCode}
                onChange={(event) => setForm((current) => ({ ...current, regionCode: event.target.value.toUpperCase().slice(0, 2) }))}
                placeholder="NY"
              />
            </Field>
            <Field label="Kontenjan" hint="Boş bırakılırsa sınırsız.">
              <Input value={form.capacity} onChange={set('capacity')} inputMode="numeric" placeholder="boş = sınırsız" />
            </Field>
            <Field label="Kayıt bağlantısı" hint="https ile başlamalı.">
              <Input value={form.externalUrl} onChange={set('externalUrl')} placeholder="https://…" />
            </Field>
            <div className="flex flex-wrap gap-2 border-t border-hairline pt-4 sm:col-span-2">
              <Button variant="primary" disabled={busy || !formReady} onClick={() => void submit(true)}>
                {busy ? 'Kaydediliyor…' : 'Yayınla'}
              </Button>
              <Button variant="outline" disabled={busy || !formReady} onClick={() => void submit(false)}>
                Taslak olarak kaydet
              </Button>
            </div>
          </div>
        </SheetContent>
      </Sheet>

      <ReasonDialog
        open={cancelling !== null}
        onOpenChange={(open) => !open && setCancelling(null)}
        title={cancelling ? `"${cancelling.title}" iptal edilecek` : 'Etkinlik iptal edilecek'}
        description="Gerekçe denetim kaydına yazılır ve üyeye gösterilir. O akşamı ayıran kişinin okuyacağı tek cümle bu."
        confirmLabel="Etkinliği iptal et"
        variant="danger"
        onConfirm={cancelRow}
      />
    </div>
  );
}
