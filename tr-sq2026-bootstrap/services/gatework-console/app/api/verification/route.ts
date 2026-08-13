import { NextResponse } from 'next/server';
import { verificationPage } from '@/lib/verification';

const noStore = { 'cache-control': 'no-store' };

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const { overview, sessions, failure } = await verificationPage({ status: url.searchParams.get('status') ?? undefined });
    return NextResponse.json({ data: { overview, sessions }, meta: { failure } }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'VERIFICATION_UNAVAILABLE', message: error instanceof Error ? error.message : 'Doğrulama kayıtları alınamadı.' } }, { status: 400, headers: noStore });
  }
}
