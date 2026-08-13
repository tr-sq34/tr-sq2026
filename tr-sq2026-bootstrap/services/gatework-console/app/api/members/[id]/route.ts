import { NextResponse } from 'next/server';
import { communityMember } from '@/lib/members';

const noStore = { 'cache-control': 'no-store' };

// The community half of a member. Identity's half already arrived with the
// list, so the detail request only asks the service that has not answered yet.
export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await communityMember((await params).id) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'MEMBER_UNAVAILABLE', message: error instanceof Error ? error.message : 'Üye bilgisi alınamadı.' } }, { status: 400, headers: noStore });
  }
}
