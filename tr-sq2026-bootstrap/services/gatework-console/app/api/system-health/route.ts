import { NextResponse } from 'next/server';
import { notifyIfDegraded } from '@/lib/alerting';
import { canSeeServiceHealth, systemHealthSnapshot } from '@/lib/health';
import { getSession } from '@/lib/session';

export const dynamic = 'force-dynamic';

const noStore = { 'cache-control': 'no-store' };

/**
 * The snapshot the board polls.
 *
 * Same gate as the page that renders it, checked here rather than trusted from
 * there: this route is reachable directly and returns infrastructure state.
 *
 * The alert dispatch hangs off this poll deliberately. It is the one thing in
 * the console that runs repeatedly without an operator pressing anything, so it
 * is the cheapest place to notice a red state - and it is awaited, so a webhook
 * that is refusing connections cannot pile up requests behind the page.
 */
export async function GET(request: Request) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: { code: 'UNAUTHENTICATED', message: 'Oturum gerekli.' } }, { status: 401, headers: noStore });
  }
  if (!canSeeServiceHealth(session.member.roles)) {
    return NextResponse.json({ error: { code: 'FORBIDDEN', message: 'Bu rol için sistem durumu gösterilmez.' } }, { status: 403, headers: noStore });
  }

  const requested = Number(new URL(request.url).searchParams.get('hours') ?? 24);
  const hours = Number.isFinite(requested) ? Math.min(720, Math.max(1, Math.round(requested))) : 24;

  try {
    const snapshot = await systemHealthSnapshot(hours);
    await notifyIfDegraded(snapshot);
    return NextResponse.json({ data: snapshot }, { headers: noStore });
  } catch (error) {
    return NextResponse.json(
      { error: { code: 'HEALTH_UNAVAILABLE', message: error instanceof Error ? error.message : 'Sistem durumu okunamadı.' } },
      { status: 500, headers: noStore },
    );
  }
}
