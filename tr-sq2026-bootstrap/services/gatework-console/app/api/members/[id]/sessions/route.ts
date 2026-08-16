import { NextResponse } from 'next/server';
import { memberSessions, revokeSessions } from '@/lib/members';

const noStore = { 'cache-control': 'no-store' };

// Açık oturumlar. Kimlik servisi cihaz imzasını ve ağ bloğunu tutuyor; tam IP
// hiçbir rolde gösterilmiyor çünkü hiçbir yerde saklanmıyor.
export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await memberSessions((await params).id) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'SESSIONS_UNAVAILABLE', message: error instanceof Error ? error.message : 'Oturumlar listelenemedi.' } }, { status: 400, headers: noStore });
  }
}

export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    await revokeSessions((await params).id, await request.json());
    return NextResponse.json({ data: { revoked: true } }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'SESSION_REVOKE_REJECTED', message: error instanceof Error ? error.message : 'Oturumlar kapatılamadı.' } }, { status: 400, headers: noStore });
  }
}
