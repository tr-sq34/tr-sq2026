import { NextResponse } from 'next/server';
import { grantBadge } from '@/lib/journey';

const noStore = { 'cache-control': 'no-store' };

export async function POST(request: Request, { params }: { params: Promise<{ code: string }> }) {
  try {
    const result = await grantBadge((await params).code, await request.json());
    return NextResponse.json({ data: result }, { headers: noStore });
  } catch (error) {
    // Servisin reddi olduğu gibi geçiyor: "bu rozetin otomatik kuralı var" ile
    // "üye bulunamadı" aynı cümleye indirilirse operatör neyi düzelteceğini
    // bilemez.
    return NextResponse.json(
      { error: { code: 'BADGE_GRANT_REJECTED', message: error instanceof Error ? error.message : 'Rozet verilemedi.' } },
      { status: 400, headers: noStore },
    );
  }
}
