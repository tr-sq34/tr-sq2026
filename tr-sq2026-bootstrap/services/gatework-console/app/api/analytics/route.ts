import { NextResponse } from 'next/server';
import { analyticsPage } from '@/lib/analytics';

const noStore = { 'cache-control': 'no-store' };

export async function GET() {
  try {
    const { accounts, community, locations, failures } = await analyticsPage();
    return NextResponse.json({ data: { accounts, community, locations }, meta: { failures } }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'ANALYTICS_UNAVAILABLE', message: error instanceof Error ? error.message : 'Analitik okunamadı.' } }, { status: 400, headers: noStore });
  }
}
