import { NextResponse } from 'next/server';
import { getContentReport } from '@/lib/content-moderation';

const noStore = { 'cache-control': 'no-store' };

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    return NextResponse.json({ data: await getContentReport((await params).id) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'CONTENT_REPORT_UNAVAILABLE', message: error instanceof Error ? error.message : 'Şikâyet açılamadı.' } }, { status: 400, headers: noStore });
  }
}
