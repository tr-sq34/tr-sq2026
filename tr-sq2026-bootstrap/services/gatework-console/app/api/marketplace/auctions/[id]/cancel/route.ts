import { NextResponse } from 'next/server';
import { cancelAuction } from '@/lib/marketplace';

const noStore = { 'cache-control': 'no-store' };

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await cancelAuction((await params).id, await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'AUCTION_CANCEL_REJECTED', message: error instanceof Error ? error.message : 'İhale iptal edilemedi.' } }, { status: 400, headers: noStore });
  }
}
