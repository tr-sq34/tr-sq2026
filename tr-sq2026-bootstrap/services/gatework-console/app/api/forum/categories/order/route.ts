import { NextResponse } from 'next/server';
import { reorderForumCategories } from '@/lib/forum';

const noStore = { 'cache-control': 'no-store' };

export async function PUT(request: Request) {
  try {
    return NextResponse.json({ data: await reorderForumCategories(await request.json()) }, { headers: noStore });
  } catch (error) {
    // The service refuses a stale list rather than ordering half of it, and the
    // refusal has to reach the operator verbatim: "sayfayi yenile" is the only
    // sentence that tells them their screen no longer matches the table.
    return NextResponse.json(
      { error: { code: 'FORUM_ORDER_REJECTED', message: error instanceof Error ? error.message : 'Sıralama kaydedilemedi.' } },
      { status: 400, headers: noStore },
    );
  }
}
