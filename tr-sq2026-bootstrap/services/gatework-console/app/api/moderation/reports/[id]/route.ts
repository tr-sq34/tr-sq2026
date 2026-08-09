import { NextResponse } from 'next/server';
import { getReport } from '@/lib/moderation';

const noStore = { 'cache-control': 'no-store' };

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await getReport((await params).id) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'REPORT_UNAVAILABLE', message: error instanceof Error ? error.message : 'Şikâyet alınamadı.' } }, { status: 400, headers: noStore });
  }
}
