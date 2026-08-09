import { NextResponse } from 'next/server';
import { decideReport } from '@/lib/moderation';

const noStore = { 'cache-control': 'no-store' };

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await decideReport((await params).id, await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'DECISION_REJECTED', message: error instanceof Error ? error.message : 'Karar kaydedilemedi.' } }, { status: 400, headers: noStore });
  }
}
