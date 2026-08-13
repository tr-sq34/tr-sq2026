import { NextResponse } from 'next/server';
import { listListings } from '@/lib/marketplace';

const noStore = { 'cache-control': 'no-store' };

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const data = await listListings({
      status: url.searchParams.get('status') ?? undefined,
      query: url.searchParams.get('query') ?? undefined,
      regionCode: url.searchParams.get('regionCode') ?? undefined,
    });
    return NextResponse.json({ data }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'MARKETPLACE_LISTINGS_UNAVAILABLE', message: error instanceof Error ? error.message : 'İlanlar alınamadı.' } }, { status: 400, headers: noStore });
  }
}
