import { NextResponse } from 'next/server';
import { closeAlert } from '@/lib/safety';

const noStore = { 'cache-control': 'no-store' };

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    await closeAlert((await params).id, await request.json());
    return NextResponse.json({ data: { closed: true } }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'SOS_CLOSE_REJECTED', message: error instanceof Error ? error.message : 'Çağrı kapatılamadı.' } }, { status: 400, headers: noStore });
  }
}
