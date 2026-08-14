import { NextResponse } from 'next/server';
import { createEvent, listEvents } from '@/lib/events';

const noStore = { 'cache-control': 'no-store' };

export async function GET(request: Request) {
  try {
    const status = new URL(request.url).searchParams.get('status') ?? 'published';
    return NextResponse.json({ data: await listEvents(status) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'EVENTS_UNAVAILABLE', message: error instanceof Error ? error.message : 'Etkinlikler alınamadı.' } }, { status: 400, headers: noStore });
  }
}

export async function POST(request: Request) {
  try {
    return NextResponse.json({ data: await createEvent(await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'EVENT_CREATE_REJECTED', message: error instanceof Error ? error.message : 'Etkinlik kaydedilemedi.' } }, { status: 400, headers: noStore });
  }
}
