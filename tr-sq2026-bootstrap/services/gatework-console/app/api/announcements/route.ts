import { NextResponse } from 'next/server';
import { listAnnouncements, sendAnnouncement } from '@/lib/announcements';

const noStore = { 'cache-control': 'no-store' };

export async function GET() {
  try {
    return NextResponse.json({ data: await listAnnouncements() }, { headers: noStore });
  } catch (error) {
    return NextResponse.json(
      { error: { code: 'ANNOUNCEMENTS_UNAVAILABLE', message: error instanceof Error ? error.message : 'Duyurular alınamadı.' } },
      { status: 400, headers: noStore },
    );
  }
}

export async function POST(request: Request) {
  try {
    return NextResponse.json({ data: await sendAnnouncement(await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json(
      { error: { code: 'ANNOUNCEMENT_REJECTED', message: error instanceof Error ? error.message : 'Duyuru gönderilemedi.' } },
      { status: 400, headers: noStore },
    );
  }
}
