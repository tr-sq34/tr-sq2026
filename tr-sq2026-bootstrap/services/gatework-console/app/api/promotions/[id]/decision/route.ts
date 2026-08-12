import { NextResponse } from 'next/server';
import { decidePromotion } from '@/lib/promotions';

const noStore = { 'cache-control': 'no-store' };

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await decidePromotion((await params).id, await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'PROMOTION_DECISION_REJECTED', message: error instanceof Error ? error.message : 'Karar kaydedilemedi.' } }, { status: 400, headers: noStore });
  }
}
