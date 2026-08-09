import { NextResponse } from 'next/server';
import { takeDownGroup } from '@/lib/moderation';

const noStore = { 'cache-control': 'no-store' };

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await takeDownGroup((await params).id, await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'TAKEDOWN_REJECTED', message: error instanceof Error ? error.message : 'Grup kapatılamadı.' } }, { status: 400, headers: noStore });
  }
}
