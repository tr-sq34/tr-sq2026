import { NextResponse } from 'next/server';
import { listForumTopics } from '@/lib/forum';

const noStore = { 'cache-control': 'no-store' };

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const data = await listForumTopics({
      categoryId: url.searchParams.get('categoryId') ?? undefined,
      state: url.searchParams.get('state') ?? undefined,
      query: url.searchParams.get('query') ?? undefined,
    });
    return NextResponse.json({ data }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'FORUM_TOPICS_UNAVAILABLE', message: error instanceof Error ? error.message : 'Konular alınamadı.' } }, { status: 400, headers: noStore });
  }
}
