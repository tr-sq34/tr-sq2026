import { NextResponse } from 'next/server';
import { replyToSupport } from '@/lib/support';

const noStore = { 'cache-control': 'no-store' };

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    await replyToSupport((await params).id, await request.json());
    return NextResponse.json({ data: { replied: true } }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'SUPPORT_REPLY_REJECTED', message: error instanceof Error ? error.message : 'Yanıt gönderilemedi.' } }, { status: 400, headers: noStore });
  }
}
