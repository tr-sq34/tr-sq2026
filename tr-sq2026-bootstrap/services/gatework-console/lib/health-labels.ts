/**
 * The vocabulary of the health board, and the scoring rule behind it.
 *
 * Split from `health.ts` for one hard reason: that file reads the operator's
 * session cookie and mints delegation tokens, which makes it server-only, while
 * the board that draws these numbers runs in the browser. Everything here is
 * pure - types, thresholds and arithmetic - so both halves can share it without
 * dragging `next/headers` into a client bundle.
 *
 * The same split exists for analytics, moderation and the rest of the console;
 * this follows it rather than inventing a second convention.
 */

/** A health check that goes through Cloudflare, a container app and `SELECT 1`
    lands well under this. Past it something is queueing, and a member feels it
    long before the check fails outright. */
export const SLOW_MS = 800;
export const PROBE_TIMEOUT_MS = 3000;

export type ServiceState = 'up' | 'slow' | 'down';

export type ServiceHealth = {
  key: string;
  name: string;
  state: ServiceState;
  /** Round trip in milliseconds, or `null` when there was no answer to time. */
  latencyMs: number | null;
  detail: string;
};

export type CrashGroup = {
  fingerprint: string;
  errorType: string;
  message: string;
  screen: string | null;
  occurrences: number;
  sessions: number;
  fatal: boolean;
  lastSeen: string;
  platforms: string[];
  appVersions: string[];
  deviceModels: string[];
};

export type AppStability = {
  windowHours: number;
  minSessionsForRate: number;
  sessions: number;
  crashedSessions: number;
  /** `null` when too few sessions were recorded for a percentage to mean
      anything. It is never rendered as 100. */
  crashFreeRate: number | null;
  previous: { sessions: number; crashFreeRate: number | null };
  crashes: number;
  fatalCrashes: number;
  platforms: { platform: string; sessions: number; crashFreeRate: number | null }[];
  groups: CrashGroup[];
};

export type RiskLevel = 'saglikli' | 'izlemede' | 'bozulma' | 'kritik';

export type RiskAssessment = {
  /** 0 is green, 100 is red. `null` means nothing could be measured - which is
      its own kind of bad and is never drawn as zero. */
  score: number | null;
  level: RiskLevel | null;
  headline: string;
  /** What pushed the number up, in the operator's words. */
  reasons: string[];
  /** What could not be measured at all. A low score with a long list here is
      not the same as a low score with an empty one. */
  blindSpots: string[];
};

export type SystemHealthSnapshot = {
  checkedAt: string;
  windowHours: number;
  services: ServiceHealth[] | null;
  servicesFailure: string | null;
  stability: AppStability | null;
  stabilityFailure: string | null;
  risk: RiskAssessment;
  /** Whether an outbound alert channel is configured for this deployment. The
      panel says so plainly either way; a silent alerting system that is not
      wired up is the worst of both. */
  alerting: { configured: boolean };
};

export const RISK_LEVELS: Record<RiskLevel, { label: string; tone: 'success' | 'warning' | 'danger'; description: string }> = {
  saglikli: { label: 'Sağlıklı', tone: 'success', description: 'Ölçülen her şey beklenen aralıkta.' },
  izlemede: { label: 'İzlemede', tone: 'warning', description: 'Tek tük sinyal var; şimdilik müdahale gerekmiyor.' },
  bozulma: { label: 'Bozulma var', tone: 'warning', description: 'Üyeler bunu hissediyor. Bugün bakılması gereken bir şey var.' },
  kritik: { label: 'Kritik', tone: 'danger', description: 'Uygulama şu anda düzgün çalışmıyor. Hemen müdahale edilmeli.' },
};

export const riskLevelFor = (score: number): RiskLevel =>
  score < 10 ? 'saglikli' : score < 30 ? 'izlemede' : score < 60 ? 'bozulma' : 'kritik';

/// Green through amber to red, continuously. A level chip alone made 31 and 59
/// look identical; the bar is the thing an operator reads first.
export const riskColor = (score: number) =>
  `hsl(${Math.round(152 - 152 * (Math.min(Math.max(score, 0), 100) / 100))} 62% 46%)`;

/**
 * The score.
 *
 * Every weight below is a claim about how much a member is hurt, not about how
 * alarming something looks on a graph:
 *
 * - A service that is not answering costs 30. Two of the four down is 60, which
 *   is `kritik`, and that is right - half the app is gone.
 * - A slow service costs 10. It is not an outage, but it is the shape an outage
 *   arrives in.
 * - The crash-free rate is the heaviest single input, because it is the only
 *   one measured on the member's own device. Below 95% the app is failing for
 *   one launch in twenty and nothing else on this page matters.
 *
 * A measurement that is missing adds nothing to the score. Inflating risk for
 * missing data would make the number unreadable during a telemetry outage; the
 * gap is reported separately, as a blind spot, and stays visible.
 */
export function assessRisk(services: ServiceHealth[] | null, stability: AppStability | null): RiskAssessment {
  const reasons: string[] = [];
  const blindSpots: string[] = [];
  let score = 0;
  let measured = false;

  if (services === null) {
    blindSpots.push('Servis sağlığı okunamadı; bu panelin kendisi servislere ulaşamıyor.');
  } else {
    measured = true;
    const down = services.filter((check) => check.state === 'down');
    const slow = services.filter((check) => check.state === 'slow');
    score += down.length * 30 + slow.length * 10;
    if (down.length) reasons.push(`${down.map((check) => check.name).join(', ')} yanıt vermiyor.`);
    if (slow.length) reasons.push(`${slow.map((check) => check.name).join(', ')} ${SLOW_MS} ms üzerinde yanıt veriyor.`);
  }

  if (stability === null) {
    blindSpots.push('Uygulama kararlılık verisi okunamadı; çökme oranı bu ölçümde yok.');
  } else if (stability.crashFreeRate === null) {
    blindSpots.push(
      `Son ${stability.windowHours} saatte ${stability.sessions} oturum kaydedildi. ` +
      `Oran için en az ${stability.minSessionsForRate} gerekiyor, bu yüzden yüzde gösterilmiyor.`,
    );
  } else {
    measured = true;
    const rate = stability.crashFreeRate;
    const penalty = rate >= 99.5 ? 0 : rate >= 99 ? 10 : rate >= 98 ? 25 : rate >= 95 ? 45 : 70;
    score += penalty;
    if (penalty > 0) {
      reasons.push(
        `Çökmesiz kullanım %${rate.toFixed(1)}; her ${Math.max(1, Math.round(100 / (100 - rate)))} oturumdan biri çökmeyle bitiyor.`,
      );
    }
    const before = stability.previous.crashFreeRate;
    // A drop is worth saying out loud even when the absolute number is still
    // fine: 99.9 to 99.5 is a fivefold increase in crashes.
    if (before !== null && rate < before - 0.3) {
      reasons.push(`Bir önceki ${stability.windowHours} saate göre düşüş var: %${before.toFixed(1)} → %${rate.toFixed(1)}.`);
      score += 10;
    }
  }

  if (!measured) return { score: null, level: null, headline: 'Ölçülemedi', reasons, blindSpots };

  score = Math.min(100, Math.round(score));
  const level = riskLevelFor(score);
  return { score, level, headline: RISK_LEVELS[level].label, reasons, blindSpots };
}
