import { NextResponse } from 'next/server';
import { listReports } from '@/lib/moderation';

const noStore = { 'cache-control': 'no-store' };

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const data = await listReports({ status: url.searchParams.get('status') ?? undefined, category: url.searchParams.get('category') ?? undefined });
    return NextResponse.json({ data }, { headers: noStore });
  } catch (error) {
    // The gateway decides authorization; the console only relays its refusal so
    // an operator sees why rather than an empty table.
    return NextResponse.json({ error: { code: 'REPORTS_UNAVAILABLE', message: error instanceof Error ? error.message : 'Şikâyetler alınamadı.' } }, { status: 400, headers: noStore });
  }
}
