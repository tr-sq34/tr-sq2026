import { NextResponse } from 'next/server';
import { supportThread } from '@/lib/support';

const noStore = { 'cache-control': 'no-store' };

// Yazışmanın tamamı. Listede yalnızca son mesaj var; bir talebi cevaplamadan
// önce operatörün okuması gereken şey, o güne kadar ne konuşulduğu.
export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await supportThread((await params).id) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'SUPPORT_THREAD_UNAVAILABLE', message: error instanceof Error ? error.message : 'Yazışma okunamadı.' } }, { status: 400, headers: noStore });
  }
}
