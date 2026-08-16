import { NextResponse } from 'next/server';
import { journeyPage } from '@/lib/journey';

const noStore = { 'cache-control': 'no-store' };

// `failure` yanıtın içinde kalıyor: katalog okunamadığında ekran boş bir tablo
// değil, neden okunamadığını gösteriyor.
export async function GET() {
  const { overview, failure } = await journeyPage();
  return NextResponse.json({ data: { overview }, meta: { failure } }, { headers: noStore });
}
