import { NextResponse } from 'next/server';
import { revokeSessions } from '@/lib/members';

const noStore = { 'cache-control': 'no-store' };

export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    await revokeSessions((await params).id, await request.json());
    return NextResponse.json({ data: { revoked: true } }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'SESSION_REVOKE_REJECTED', message: error instanceof Error ? error.message : 'Oturumlar kapatılamadı.' } }, { status: 400, headers: noStore });
  }
}
