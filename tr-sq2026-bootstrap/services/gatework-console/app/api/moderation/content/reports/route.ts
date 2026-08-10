import { NextResponse } from 'next/server';
import { listContentReports } from '@/lib/content-moderation';

const noStore = { 'cache-control': 'no-store' };

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const data = await listContentReports({
      status: url.searchParams.get('status') ?? undefined,
      category: url.searchParams.get('category') ?? undefined,
    });
    return NextResponse.json({ data }, { headers: noStore });
  } catch (error) {
    // Community decides authorization; the console only relays the refusal so an
    // operator sees why rather than an empty table.
    return NextResponse.json({ error: { code: 'CONTENT_REPORTS_UNAVAILABLE', message: error instanceof Error ? error.message : 'İçerik şikâyetleri alınamadı.' } }, { status: 400, headers: noStore });
  }
}
