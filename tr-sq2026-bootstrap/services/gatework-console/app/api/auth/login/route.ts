import { NextResponse } from 'next/server';
import { z } from 'zod';
import { gateworkMe, identityLogin } from '@/lib/identity';
import { setSession } from '@/lib/session';

const inputSchema = z.object({ email: z.string().trim().email().max(254), password: z.string().min(1).max(128) });

export async function POST(request: Request) {
  try {
    const input = inputSchema.parse(await request.json());
    const login = await identityLogin(input.email, input.password);
    const member = await gateworkMe(login.accessToken);
    await setSession({ member, accessToken: login.accessToken, refreshToken: login.refreshToken, issuedAt: Date.now(), expiresAt: Date.now() + 8 * 60 * 60 * 1000 });
    return NextResponse.json({ data: { member } }, { headers: { 'cache-control': 'no-store' } });
  } catch (error) {
    const code = error instanceof Error ? error.message : 'LOGIN_FAILED';
    const status = code === 'NOT_AUTHORIZED' ? 403 : code === 'INVALID_LOGIN' ? 401 : 400;
    return NextResponse.json({ error: { code, message: code === 'NOT_AUTHORIZED' ? 'Bu hesap Gatework erişimine sahip değil.' : 'Giriş bilgileri doğrulanamadı.' } }, { status, headers: { 'cache-control': 'no-store' } });
  }
}
