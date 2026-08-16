import { NextResponse } from 'next/server';
import { supportPage } from '@/lib/support';

const noStore = { 'cache-control': 'no-store' };

export async function GET(request: Request) {
  const url = new URL(request.url);
  const { requests, failure } = await supportPage({
    state: url.searchParams.get('state') ?? undefined,
    topic: url.searchParams.get('topic') ?? undefined,
  });
  return NextResponse.json({ data: { requests }, meta: { failure } }, { headers: noStore });
}
