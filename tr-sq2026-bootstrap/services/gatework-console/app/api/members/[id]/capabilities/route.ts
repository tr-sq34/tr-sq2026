import { NextResponse } from 'next/server';
import { setCapabilities } from '@/lib/members';

const noStore = { 'cache-control': 'no-store' };

export async function PUT(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await setCapabilities((await params).id, await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'CAPABILITY_REJECTED', message: error instanceof Error ? error.message : 'Yetki güncellenemedi.' } }, { status: 400, headers: noStore });
  }
}
