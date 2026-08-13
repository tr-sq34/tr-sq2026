import { NextResponse } from 'next/server';
import { openLocationAccess } from '@/lib/safety';

const noStore = { 'cache-control': 'no-store' };

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await openLocationAccess((await params).id, await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'SOS_LOCATION_ACCESS_REJECTED', message: error instanceof Error ? error.message : 'Konum erişimi açılamadı.' } }, { status: 400, headers: noStore });
  }
}
