import { NextResponse } from 'next/server';
import { setForumTopicState } from '@/lib/forum';

const noStore = { 'cache-control': 'no-store' };

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await setForumTopicState((await params).id, await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'FORUM_TOPIC_STATE_REJECTED', message: error instanceof Error ? error.message : 'Konu durumu değiştirilemedi.' } }, { status: 400, headers: noStore });
  }
}
