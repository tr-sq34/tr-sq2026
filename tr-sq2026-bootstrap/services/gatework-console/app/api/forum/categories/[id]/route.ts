import { NextResponse } from 'next/server';
import { updateForumCategory } from '@/lib/forum';

const noStore = { 'cache-control': 'no-store' };

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await updateForumCategory((await params).id, await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'FORUM_CATEGORY_UPDATE_REJECTED', message: error instanceof Error ? error.message : 'Kategori güncellenemedi.' } }, { status: 400, headers: noStore });
  }
}
