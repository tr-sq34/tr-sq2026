import { NextResponse } from 'next/server';
import { setListingStatus } from '@/lib/marketplace';

const noStore = { 'cache-control': 'no-store' };

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await setListingStatus((await params).id, await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'LISTING_STATUS_REJECTED', message: error instanceof Error ? error.message : 'İlan durumu değiştirilemedi.' } }, { status: 400, headers: noStore });
  }
}
