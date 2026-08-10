import { NextResponse } from 'next/server';
import { decideContentReport } from '@/lib/content-moderation';

const noStore = { 'cache-control': 'no-store' };

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await decideContentReport((await params).id, await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'CONTENT_DECISION_REJECTED', message: error instanceof Error ? error.message : 'Karar kaydedilemedi.' } }, { status: 400, headers: noStore });
  }
}
