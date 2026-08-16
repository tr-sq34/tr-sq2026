import { NextResponse } from 'next/server';
import { badgeHolders } from '@/lib/journey';

const noStore = { 'cache-control': 'no-store' };

export async function GET(_request: Request, { params }: { params: Promise<{ code: string }> }) {
  try {
    return NextResponse.json({ data: await badgeHolders((await params).code) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json(
      { error: { code: 'BADGE_HOLDERS_UNAVAILABLE', message: error instanceof Error ? error.message : 'Rozeti taşıyanlar okunamadı.' } },
      { status: 400, headers: noStore },
    );
  }
}
