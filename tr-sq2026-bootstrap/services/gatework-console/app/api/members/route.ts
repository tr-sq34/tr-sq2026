import { NextResponse } from 'next/server';
import { searchMembers } from '@/lib/members';

const noStore = { 'cache-control': 'no-store' };

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const data = await searchMembers({
      query: url.searchParams.get('query') ?? undefined,
      role: url.searchParams.get('role') ?? undefined,
    });
    return NextResponse.json({ data }, { headers: noStore });
  } catch (error) {
    // Identity decides authorization; the console only relays the refusal so an
    // operator sees why rather than an empty table.
    return NextResponse.json({ error: { code: 'MEMBERS_UNAVAILABLE', message: error instanceof Error ? error.message : 'Üyeler listelenemedi.' } }, { status: 400, headers: noStore });
  }
}
