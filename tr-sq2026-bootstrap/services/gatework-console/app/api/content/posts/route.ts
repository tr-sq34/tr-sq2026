import { NextResponse } from 'next/server';
import { publishOfficialPost } from '@/lib/gatework';
export async function POST(request: Request) { try { return NextResponse.json({ data: await publishOfficialPost(await request.json()) }, { status: 201, headers: { 'cache-control': 'no-store' } }); } catch { return NextResponse.json({ error: { code: 'OFFICIAL_POST_REJECTED', message: 'Resmî paylaşım yayınlanamadı.' } }, { status: 400, headers: { 'cache-control': 'no-store' } }); } }
