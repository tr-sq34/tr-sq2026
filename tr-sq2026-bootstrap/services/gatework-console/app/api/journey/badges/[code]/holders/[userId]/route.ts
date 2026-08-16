import { NextResponse } from 'next/server';
import { revokeBadge } from '@/lib/journey';

const noStore = { 'cache-control': 'no-store' };

export async function DELETE(_request: Request, { params }: { params: Promise<{ code: string; userId: string }> }) {
  try {
    const { code, userId } = await params;
    await revokeBadge(code, userId);
    return NextResponse.json({ data: { revoked: true } }, { headers: noStore });
  } catch (error) {
    return NextResponse.json(
      { error: { code: 'BADGE_REVOKE_REJECTED', message: error instanceof Error ? error.message : 'Rozet geri alınamadı.' } },
      { status: 400, headers: noStore },
    );
  }
}
