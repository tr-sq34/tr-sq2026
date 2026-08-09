import { NextResponse } from 'next/server';
import { claimReport } from '@/lib/moderation';

const noStore = { 'cache-control': 'no-store' };

export async function POST(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await claimReport((await params).id) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'CLAIM_REJECTED', message: error instanceof Error ? error.message : 'Şikâyet üstlenilemedi.' } }, { status: 400, headers: noStore });
  }
}
