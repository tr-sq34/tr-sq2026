import { NextResponse } from 'next/server';
import { legalPage } from '@/lib/legal';

const noStore = { 'cache-control': 'no-store' };

// `failure` yanıtın içinde kalıyor: metinler okunamadığında ekran boş bir
// editör değil, neden okunamadığını gösteriyor.
export async function GET() {
  const { documents, failure } = await legalPage();
  return NextResponse.json({ data: { documents }, meta: { failure } }, { headers: noStore });
}
