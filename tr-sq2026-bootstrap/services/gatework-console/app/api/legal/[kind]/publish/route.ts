import { NextResponse } from 'next/server';
import { publishLegal } from '@/lib/legal';

const noStore = { 'cache-control': 'no-store' };

export async function POST(_request: Request, { params }: { params: Promise<{ kind: string }> }) {
  try {
    const result = await publishLegal((await params).kind);
    return NextResponse.json({ data: result }, { headers: noStore });
  } catch (error) {
    return NextResponse.json(
      { error: { code: 'LEGAL_PUBLISH_REJECTED', message: error instanceof Error ? error.message : 'Metin yayımlanamadı.' } },
      { status: 400, headers: noStore },
    );
  }
}
