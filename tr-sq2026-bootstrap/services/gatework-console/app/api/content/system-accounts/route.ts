import { NextResponse } from 'next/server';
import { listSystemAccounts } from '@/lib/content';
import { createSystemAccount } from '@/lib/gatework';

const noStore = { 'cache-control': 'no-store' };

export async function GET() {
  try {
    return NextResponse.json({ data: await listSystemAccounts() }, { headers: noStore });
  } catch {
    return NextResponse.json({ error: { code: 'SYSTEM_ACCOUNTS_UNAVAILABLE', message: 'Resmî hesaplar okunamadı.' } }, { status: 400, headers: noStore });
  }
}

export async function POST(request: Request) {
  try {
    return NextResponse.json({ data: await createSystemAccount(await request.json()) }, { status: 201, headers: noStore });
  } catch {
    return NextResponse.json({ error: { code: 'SYSTEM_ACCOUNT_CREATE_REJECTED', message: 'Resmî hesap oluşturulamadı.' } }, { status: 400, headers: noStore });
  }
}
