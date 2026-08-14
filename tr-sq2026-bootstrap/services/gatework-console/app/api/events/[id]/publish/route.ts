import { NextResponse } from 'next/server';
import { publishEvent } from '@/lib/events';

const noStore = { 'cache-control': 'no-store' };

export async function POST(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await publishEvent((await params).id) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'EVENT_PUBLISH_REJECTED', message: error instanceof Error ? error.message : 'Etkinlik yayınlanamadı.' } }, { status: 400, headers: noStore });
  }
}
