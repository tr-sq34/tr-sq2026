import { NextResponse } from 'next/server';
import { safetyPage } from '@/lib/safety';

const noStore = { 'cache-control': 'no-store' };

export async function GET(request: Request) {
  const url = new URL(request.url);
  const { alerts, failure } = await safetyPage({ state: url.searchParams.get('state') ?? undefined });
  return NextResponse.json({ data: { alerts }, meta: { failure } }, { headers: noStore });
}
