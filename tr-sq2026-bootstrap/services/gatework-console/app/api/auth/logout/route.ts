import { NextResponse } from 'next/server';
import { clearSession, getSession } from '@/lib/session';
import { identityLogout } from '@/lib/identity';

export async function POST() {
  const session = await getSession();
  if (session) await identityLogout(session.refreshToken);
  await clearSession();
  return new NextResponse(null, { status: 204, headers: { 'cache-control': 'no-store' } });
}
