import { NextResponse } from 'next/server';
import { retractNewsArticle } from '@/lib/content';

const noStore = { 'cache-control': 'no-store' };

// Retraction, not deletion. The article stops being readable; the record of it
// having existed - and of who took it down and why - does not.
export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    return NextResponse.json({ data: await retractNewsArticle(id, await request.json()) }, { headers: noStore });
  } catch {
    return NextResponse.json({ error: { code: 'NEWS_RETRACT_REJECTED', message: 'Haber geri çekilemedi.' } }, { status: 400, headers: noStore });
  }
}
