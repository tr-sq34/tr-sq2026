import { NextResponse } from 'next/server';
import { retractOfficialStory } from '@/lib/content';

const noStore = { 'cache-control': 'no-store' };

// Geri çekme, silme değil. Story okunamaz hâle geliyor; görüntülenmeleri,
// beğenileri ve kimin neden kaldırdığı kayıtta duruyor.
export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    return NextResponse.json({ data: await retractOfficialStory(id, await request.json()) }, { headers: noStore });
  } catch (error) {
    return NextResponse.json(
      { error: { code: 'STORY_RETRACT_REJECTED', message: error instanceof Error ? error.message : 'Story geri çekilemedi.' } },
      { status: 400, headers: noStore },
    );
  }
}
