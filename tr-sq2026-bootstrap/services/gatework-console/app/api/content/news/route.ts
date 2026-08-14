import { NextResponse } from 'next/server';
import { listNewsArticles } from '@/lib/content';
import { publishNewsArticle } from '@/lib/gatework';

const noStore = { 'cache-control': 'no-store' };

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const rows = await listNewsArticles({
      category: url.searchParams.get('category') ?? undefined,
      limit: Number(url.searchParams.get('limit') ?? 50),
    });
    return NextResponse.json({ data: rows }, { headers: noStore });
  } catch {
    return NextResponse.json({ error: { code: 'NEWS_LIST_UNAVAILABLE', message: 'Haber listesi okunamadı.' } }, { status: 400, headers: noStore });
  }
}

export async function POST(request: Request) {
  try {
    return NextResponse.json({ data: await publishNewsArticle(await request.json()) }, { status: 201, headers: noStore });
  } catch {
    return NextResponse.json({ error: { code: 'NEWS_ARTICLE_REJECTED', message: 'Haber yayınlanamadı.' } }, { status: 400, headers: noStore });
  }
}
