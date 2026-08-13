import { NextResponse } from 'next/server';
import { acknowledgeAlert } from '@/lib/safety';

const noStore = { 'cache-control': 'no-store' };

export async function POST(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    await acknowledgeAlert((await params).id);
    return NextResponse.json({ data: { acknowledged: true } }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'SOS_ACKNOWLEDGE_REJECTED', message: error instanceof Error ? error.message : 'Çağrı üstlenilemedi.' } }, { status: 400, headers: noStore });
  }
}
