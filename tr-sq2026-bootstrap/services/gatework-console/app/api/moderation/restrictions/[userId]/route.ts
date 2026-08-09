import { NextResponse } from 'next/server';
import { liftRestriction } from '@/lib/moderation';

const noStore = { 'cache-control': 'no-store' };

export async function DELETE(request: Request, { params }: { params: Promise<{ userId: string }> }) {
  try {
    return NextResponse.json({ data: await liftRestriction((await params).userId, await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'LIFT_REJECTED', message: error instanceof Error ? error.message : 'Kısıtlama kaldırılamadı.' } }, { status: 400, headers: noStore });
  }
}
