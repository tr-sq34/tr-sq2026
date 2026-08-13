import { NextResponse } from 'next/server';
import { readLocation } from '@/lib/safety';

const noStore = { 'cache-control': 'no-store' };

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await readLocation((await params).id) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'SOS_LOCATION_SEALED', message: error instanceof Error ? error.message : 'Konum okunamadı.' } }, { status: 403, headers: noStore });
  }
}
