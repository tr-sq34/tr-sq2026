import { NextResponse } from 'next/server';
import { listAuctions } from '@/lib/marketplace';

const noStore = { 'cache-control': 'no-store' };

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const data = await listAuctions({ state: url.searchParams.get('state') ?? undefined });
    return NextResponse.json({ data }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'MARKETPLACE_AUCTIONS_UNAVAILABLE', message: error instanceof Error ? error.message : 'İhaleler alınamadı.' } }, { status: 400, headers: noStore });
  }
}
