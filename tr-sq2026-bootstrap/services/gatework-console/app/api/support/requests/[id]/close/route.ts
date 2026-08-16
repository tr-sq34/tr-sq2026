import { NextResponse } from 'next/server';
import { closeSupport } from '@/lib/support';

const noStore = { 'cache-control': 'no-store' };

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    await closeSupport((await params).id, await request.json());
    return NextResponse.json({ data: { closed: true } }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'SUPPORT_CLOSE_REJECTED', message: error instanceof Error ? error.message : 'Talep kapatılamadı.' } }, { status: 400, headers: noStore });
  }
}
