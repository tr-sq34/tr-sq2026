import { NextResponse } from 'next/server';
import { grantRole, revokeRole } from '@/lib/members';

const noStore = { 'cache-control': 'no-store' };

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    await grantRole((await params).id, await request.json());
    return NextResponse.json({ data: { granted: true } }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'ROLE_GRANT_REJECTED', message: error instanceof Error ? error.message : 'Rol verilemedi.' } }, { status: 400, headers: noStore });
  }
}

// DELETE with a body because taking a role back needs a reason, exactly like
// giving one: the audit line is the point of the endpoint.
export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    await revokeRole((await params).id, await request.json());
    return NextResponse.json({ data: { revoked: true } }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'ROLE_REVOKE_REJECTED', message: error instanceof Error ? error.message : 'Rol kaldırılamadı.' } }, { status: 400, headers: noStore });
  }
}
