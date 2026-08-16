import { NextResponse } from 'next/server';
import { saveLegalDraft } from '@/lib/legal';

const noStore = { 'cache-control': 'no-store' };

export async function PUT(request: Request, { params }: { params: Promise<{ kind: string }> }) {
  try {
    const result = await saveLegalDraft((await params).kind, await request.json());
    return NextResponse.json({ data: result }, { headers: noStore });
  } catch (error) {
    // Servisin reddi olduğu gibi geçiyor: "yetkin yok" ile "başlık boş" aynı
    // cümleye indirilirse operatör neyi düzelteceğini bilemez.
    return NextResponse.json(
      { error: { code: 'LEGAL_DRAFT_REJECTED', message: error instanceof Error ? error.message : 'Taslak kaydedilemedi.' } },
      { status: 400, headers: noStore },
    );
  }
}
