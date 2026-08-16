import { NextResponse } from 'next/server';
import { newsImageStatus } from '@/lib/gatework';

const noStore = { 'cache-control': 'no-store' };

/// Taramanın bittiği yer. Panel yükledikten sonra burayı yokluyor; görsel
/// "ready" olana kadar yayınlama düğmesi açılmıyor, çünkü hazır olmayan bir
/// kimlikle yayınlanan haber servisten geri döner.
export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ownerId = new URL(request.url).searchParams.get('ownerId') ?? '';
    return NextResponse.json({ data: await newsImageStatus(id, ownerId) }, { headers: noStore });
  } catch {
    return NextResponse.json(
      { error: { code: 'MEDIA_STATUS_UNAVAILABLE', message: 'Görselin tarama durumu okunamadı.' } },
      { status: 400, headers: noStore },
    );
  }
}
