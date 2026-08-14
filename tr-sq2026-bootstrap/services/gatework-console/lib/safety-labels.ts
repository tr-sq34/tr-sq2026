/**
 * Browser-safe half of the Güvenlik ve SOS screen.
 *
 * Split from lib/safety.ts for the same reason as the other label modules: the
 * screen is a client component and the server module reads the session cookie.
 */

// Note what this type does not have: latitude and longitude. The list endpoint
// does not return them at any role, and the shape says so - a coordinate that
// is not in the type cannot be leaked into a card by accident.
export type SosAlert = {
  id: string;
  memberId: string;
  memberName: string | null;
  kind: string;
  status: 'active' | 'acknowledged' | 'resolved' | 'cancelled';
  note: string | null;
  locationNote: string | null;
  location: {
    shared: boolean;
    capturedAt: string | null;
    accuracyMeters: number | null;
    accessExpiresAt: string | null;
    activeWatchers: number;
  };
  createdAt: string;
  acknowledgedAt: string | null;
  closedAt: string | null;
  closureReason: string | null;
};

export type SosLocation = {
  latitude: number;
  longitude: number;
  accuracyMeters: number | null;
  capturedAt: string | null;
  accessExpiresAt: string;
};

export const SOS_KIND_LABELS: Record<string, string> = {
  personal_safety: 'Can güvenliği',
  medical: 'Sağlık',
  harassment: 'Taciz / tehdit',
  accident: 'Kaza',
  other: 'Diğer',
};

export const SOS_STATUS_LABELS: Record<SosAlert['status'], string> = {
  active: 'Bekliyor',
  acknowledged: 'Üstlenildi',
  resolved: 'Kapandı',
  cancelled: 'Üye geri aldı',
};

/// Badge tones rather than colour classes: the palette lives in one place, so a
/// status cannot end up a different shade of red from every other danger badge.
export const SOS_STATUS_TONE: Record<SosAlert['status'], 'danger' | 'warning' | 'success' | 'neutral'> = {
  active: 'danger',
  acknowledged: 'warning',
  resolved: 'success',
  cancelled: 'neutral',
};

export const isOpen = (alert: SosAlert) => alert.status === 'active' || alert.status === 'acknowledged';

export const memberLabel = (alert: SosAlert) => alert.memberName ?? `${alert.memberId.slice(0, 8)}…`;

export const sosTime = (value: string) => new Date(value).toLocaleString('tr-TR', { dateStyle: 'short', timeStyle: 'short' });

/// How long somebody has been waiting, which is the only number on this screen
/// that gets worse while nobody looks at it.
export function waitedFor(iso: string, now: number) {
  const minutes = Math.max(0, Math.round((now - new Date(iso).getTime()) / 60000));
  if (minutes < 60) return `${minutes} dk`;
  const hours = Math.floor(minutes / 60);
  return hours < 24 ? `${hours} sa ${minutes % 60} dk` : `${Math.floor(hours / 24)} gün`;
}
