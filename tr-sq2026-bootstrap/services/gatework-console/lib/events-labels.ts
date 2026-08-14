/**
 * Browser-safe half of the Etkinlikler screen: the row shape and the Turkish
 * labels. Split from lib/events.ts for the reason every other desk splits -
 * the screen is a client component and the server module reads the session
 * cookie.
 */

export type EventRow = {
  id: string;
  title: string;
  description: string;
  category: string;
  startsAt: string;
  endsAt: string | null;
  location: string;
  city: string;
  regionCode: string;
  priceLabel: string;
  externalUrl: string | null;
  capacity: number | null;
  imageUrl: string | null;
  attendeeCount: number;
  interestedCount: number;
  status: string;
  cancellationReason: string | null;
};

export const EVENT_STATUS_LABELS: Record<string, string> = {
  draft: 'Taslak',
  published: 'Yayında',
  cancelled: 'İptal edildi',
};

export const EVENT_STATUS_ORDER = ['published', 'draft', 'cancelled'] as const;

export const eventStatusTone = (status: string) =>
  status === 'published' ? 'text-emerald-300' : status === 'cancelled' ? 'text-rose-300' : 'text-amber-300';

/** Etkinlik tarihi, panelin çalıştığı yerin saatiyle değil, okunur bir satırla. */
export const eventWhen = (startsAt: string, endsAt: string | null) => {
  const start = new Date(startsAt);
  const day = start.toLocaleDateString('tr-TR', { day: 'numeric', month: 'long', year: 'numeric', weekday: 'long' });
  const clock = start.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
  if (!endsAt) return `${day} · ${clock}`;
  const end = new Date(endsAt);
  const sameDay = end.toDateString() === start.toDateString();
  const endClock = end.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
  return sameDay
    ? `${day} · ${clock} – ${endClock}`
    : `${day} ${clock} → ${end.toLocaleDateString('tr-TR', { day: 'numeric', month: 'long' })} ${endClock}`;
};

export const placeLabel = (row: Pick<EventRow, 'location' | 'city' | 'regionCode'>) =>
  [row.location, [row.city, row.regionCode].filter(Boolean).join(', ')].filter(Boolean).join(' — ');

/**
 * Kaç kişi geliyor. Katılanların kim olduğu panele de gelmiyor: bir akşam
 * kimin nerede olduğunun listesi, bu servisin özellikle tutmadığı kayıt.
 */
export const attendanceLabel = (row: Pick<EventRow, 'attendeeCount' | 'interestedCount' | 'capacity'>) => {
  const going = row.capacity ? `${row.attendeeCount}/${row.capacity} katılıyor` : `${row.attendeeCount} katılıyor`;
  return row.interestedCount ? `${going} · ${row.interestedCount} ilgileniyor` : going;
};
