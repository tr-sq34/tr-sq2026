import { NextResponse } from 'next/server';
import { reorderPromotions } from '@/lib/promotions';

const noStore = { 'cache-control': 'no-store' };

export async function PUT(request: Request) {
  try {
    return NextResponse.json({ data: await reorderPromotions(await request.json()) }, { headers: noStore });
  } catch (error) {
    // The service refuses a stale list rather than applying half of it, and
    // that refusal has to reach the operator verbatim: "sayfayi yenile" is the
    // only sentence that tells them their screen no longer matches the queue.
    return NextResponse.json(
      { error: { code: 'PROMOTION_ORDER_REJECTED', message: error instanceof Error ? error.message : 'Sıralama kaydedilemedi.' } },
      { status: 400, headers: noStore },
    );
  }
}
