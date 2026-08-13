import { NextResponse } from 'next/server';
import { auditPage } from '@/lib/audit';

const noStore = { 'cache-control': 'no-store' };

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const { rows, failures } = await auditPage({
      action: url.searchParams.get('action') ?? undefined,
      actorId: url.searchParams.get('actorId') ?? undefined,
      outcome: url.searchParams.get('outcome') ?? undefined,
      limit: Number(url.searchParams.get('limit') ?? 100),
    });
    // The failed sources travel with the rows rather than turning the whole
    // response into an error: a partial log has to say which part is missing,
    // or it reads as "nothing happened there".
    return NextResponse.json({ data: rows, meta: { failures } }, { headers: noStore });
  } catch (error) {
    return NextResponse.json({ error: { code: 'AUDIT_UNAVAILABLE', message: error instanceof Error ? error.message : 'Denetim kaydı alınamadı.' } }, { status: 400, headers: noStore });
  }
}
