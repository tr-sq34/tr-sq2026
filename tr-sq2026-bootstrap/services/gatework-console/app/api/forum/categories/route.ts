import { NextResponse } from 'next/server';
import { createForumCategory, listForumCategories } from '@/lib/forum';

const noStore = { 'cache-control': 'no-store' };

export async function GET() {
  try {
    return NextResponse.json({ data: await listForumCategories() }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'FORUM_CATEGORIES_UNAVAILABLE', message: error instanceof Error ? error.message : 'Kategoriler alınamadı.' } }, { status: 400, headers: noStore });
  }
}

export async function POST(request: Request) {
  try {
    return NextResponse.json({ data: await createForumCategory(await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'FORUM_CATEGORY_REJECTED', message: error instanceof Error ? error.message : 'Kategori açılamadı.' } }, { status: 400, headers: noStore });
  }
}
