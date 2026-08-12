import { NextResponse } from 'next/server';
import { listPromotions, placePromotion } from '@/lib/promotions';

const noStore = { 'cache-control': 'no-store' };

export async function GET(request: Request) {
  try {
    const status = new URL(request.url).searchParams.get('status') ?? 'pending';
    return NextResponse.json({ data: await listPromotions(status) }, { headers: noStore });
  } catch (error) {
    // Community decides authorization; the console only relays the refusal so an
    // operator sees why rather than an empty table.
    return NextResponse.json({ error: { code: 'PROMOTIONS_UNAVAILABLE', message: error instanceof Error ? error.message : 'Tanıtım kuyruğu alınamadı.' } }, { status: 400, headers: noStore });
  }
}

export async function POST(request: Request) {
  try {
    return NextResponse.json({ data: await placePromotion(await request.json()) }, { status: 201, headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'PROMOTION_PLACEMENT_REJECTED', message: error instanceof Error ? error.message : 'Tanıtım yerleştirilemedi.' } }, { status: 400, headers: noStore });
  }
}
