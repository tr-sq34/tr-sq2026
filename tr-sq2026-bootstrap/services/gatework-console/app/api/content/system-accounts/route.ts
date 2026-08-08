import { NextResponse } from 'next/server';
import { createSystemAccount } from '@/lib/gatework';
export async function POST(request: Request) { try { return NextResponse.json({ data: await createSystemAccount(await request.json()) }, { status: 201, headers: { 'cache-control': 'no-store' } }); } catch { return NextResponse.json({ error: { code: 'SYSTEM_ACCOUNT_CREATE_REJECTED', message: 'Resmî hesap oluşturulamadı.' } }, { status: 400, headers: { 'cache-control': 'no-store' } }); } }
