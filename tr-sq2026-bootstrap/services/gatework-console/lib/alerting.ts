import { RISK_LEVELS, type SystemHealthSnapshot } from './health-labels';

/**
 * Telling somebody, when nobody is looking at the panel.
 *
 * A dashboard is only an alerting system while an operator has it open, so this
 * fires from two places and neither one is this file's business: the snapshot
 * API calls it on every poll, and `.github/workflows/uptime-watch.yml` probes
 * the same `/health` endpoints on a schedule for the hours when the console is
 * closed. Both post to the same `OPS_ALERT_WEBHOOK_URL`.
 *
 * The body carries the same sentence under three keys because the three
 * services people actually use disagree about the name: Slack reads `text`,
 * Discord reads `content`, and most generic relays read `message`. One request
 * works with all of them and none of them sees a field it does not understand.
 *
 * What this must never do is fail loudly. An alerting channel that breaks the
 * page it is reporting on has made the outage worse.
 */
const COOLDOWN_MS = 15 * 60_000;

// Module state, so a restarted container starts quiet rather than replaying an
// hour of alerts. That is the right trade: a missed repeat costs a duplicate
// notification, a replayed history costs the operator's trust in the channel.
let lastNotifiedAt = 0;
let lastNotifiedLevel: string | null = null;

const SEVERITY: Record<string, number> = { saglikli: 0, izlemede: 1, bozulma: 2, kritik: 3 };

export function alertMessageFor(snapshot: SystemHealthSnapshot): string | null {
  const { risk } = snapshot;
  if (risk.level === null) {
    return 'TurkSquare · Sistem sağlığı ölçülemedi. Panel servislere ulaşamıyor.';
  }
  if (SEVERITY[risk.level] < SEVERITY.bozulma) return null;

  const lines = [
    `TurkSquare · ${RISK_LEVELS[risk.level].label} (sorun riski %${risk.score})`,
    ...risk.reasons.map((reason) => `• ${reason}`),
  ];
  if (snapshot.stability?.crashFreeRate !== null && snapshot.stability) {
    lines.push(`• Çökmesiz kullanım: %${snapshot.stability.crashFreeRate!.toFixed(1)} (son ${snapshot.stability.windowHours} saat)`);
  }
  return lines.join('\n');
}

export async function notifyIfDegraded(snapshot: SystemHealthSnapshot): Promise<void> {
  const url = process.env.OPS_ALERT_WEBHOOK_URL;
  if (!url) return;

  const level = snapshot.risk.level ?? 'kritik';
  const message = alertMessageFor(snapshot);

  if (message === null) {
    // Recovery is worth one message, and only to somebody who was told about
    // the problem in the first place.
    if (lastNotifiedLevel !== null) {
      lastNotifiedLevel = null;
      lastNotifiedAt = Date.now();
      await post(url, 'TurkSquare · Sistem normale döndü.');
    }
    return;
  }

  const escalated = lastNotifiedLevel !== null && (SEVERITY[level] ?? 0) > (SEVERITY[lastNotifiedLevel] ?? 0);
  const cooled = Date.now() - lastNotifiedAt > COOLDOWN_MS;
  if (lastNotifiedLevel === level && !cooled) return;
  if (!escalated && !cooled && lastNotifiedLevel !== null) return;

  lastNotifiedLevel = level;
  lastNotifiedAt = Date.now();
  await post(url, message);
}

async function post(url: string, text: string) {
  try {
    await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ text, content: text, message: text }),
      signal: AbortSignal.timeout(4000),
    });
  } catch {
    // Swallowed on purpose: see the note above. The panel already shows the
    // state this message was trying to describe.
  }
}
