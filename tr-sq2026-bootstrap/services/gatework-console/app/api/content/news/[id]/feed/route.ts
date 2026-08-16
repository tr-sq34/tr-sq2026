import { NextResponse } from 'next/server';
import { setNewsFeedShare } from '@/lib/content';

const noStore = { 'cache-control': 'no-store' };

// Akışa çıkarma / akıştan alma. Haberin kendisine dokunmuyor: kapatıldığında
// makale Haber Merkezi'nde okunmaya, beğenilmeye ve yorumlanmaya devam eder.
export async function PUT(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    return NextResponse.json({ data: await setNewsFeedShare(id, await request.json()) }, { headers: noStore });
  } catch {
    return NextResponse.json(
      { error: { code: 'NEWS_FEED_SHARE_REJECTED', message: 'Akış kararı kaydedilemedi.' } },
      { status: 400, headers: noStore },
    );
  }
}
