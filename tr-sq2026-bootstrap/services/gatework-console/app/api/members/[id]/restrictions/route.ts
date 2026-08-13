import { NextResponse } from 'next/server';
import { liftContentRestriction } from '@/lib/content-moderation';
import { memberReasonSchema, restrictMember } from '@/lib/members';

const noStore = { 'cache-control': 'no-store' };

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await restrictMember((await params).id, await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'RESTRICTION_REJECTED', message: error instanceof Error ? error.message : 'Kısıtlama uygulanamadı.' } }, { status: 400, headers: noStore });
  }
}

// Lifting reuses the endpoint the moderation queue already calls: one
// restriction table, one way out of it, one audit action.
export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { reason } = memberReasonSchema.parse(await request.json());
    await liftContentRestriction((await params).id, reason);
    return NextResponse.json({ data: { lifted: true } }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'RESTRICTION_LIFT_REJECTED', message: error instanceof Error ? error.message : 'Kısıtlama kaldırılamadı.' } }, { status: 400, headers: noStore });
  }
}
