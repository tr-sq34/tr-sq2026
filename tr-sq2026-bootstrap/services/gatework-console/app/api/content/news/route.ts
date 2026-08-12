import { NextResponse } from 'next/server';
import { publishNewsArticle } from '@/lib/gatework';
export async function POST(request: Request) { try { return NextResponse.json({ data: await publishNewsArticle(await request.json()) }, { status: 201, headers: { 'cache-control': 'no-store' } }); } catch { return NextResponse.json({ error: { code: 'NEWS_ARTICLE_REJECTED', message: 'Haber yayınlanamadı.' } }, { status: 400, headers: { 'cache-control': 'no-store' } }); } }
